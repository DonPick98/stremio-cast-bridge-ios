import Foundation
import JavaScriptCore

/// Complete indexed Matroska extraction. No movie URL or subtitle text is logged.
@MainActor final class IndexedCaptionExtraction {
    enum Failure:Error {case unavailable,range,limit,coverage,cancelled}
    struct Output {let text:String;let bytes:Int;let requests:Int;let frames:Int}
    private let input:URL
    private let session:URLSession
    private var context:JSContext?
    private var continuation:CheckedContinuation<Output,Error>?
    private var tasks:[UUID:Task<Void,Never>]=[:]
    private var timer:Task<Void,Never>?
    private var size:Int?
    private var validator:String?
    private var bytes=0,requests=0
    private var active=true
    init(input:URL,configuration:URLSessionConfiguration?=nil) {
        self.input=input
        let config=configuration ?? URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest=5;config.timeoutIntervalForResource=12
        config.httpMaximumConnectionsPerHost=4;config.urlCache=nil
        config.httpCookieStorage=nil;config.urlCredentialStorage=nil
        session=URLSession(configuration:config,delegate:IndexedCaptionRedirect(),delegateQueue:nil)
    }
    static func extract(input:URL,ordinal:Int,language:String,script:URL?=nil,configuration:URLSessionConfiguration?=nil) async throws -> Output {
        guard input.isFileURL || (input.scheme=="https" && input.user==nil && input.password==nil),ordinal>=0,ordinal<256 else{throw Failure.unavailable}
        let job=IndexedCaptionExtraction(input:input,configuration:configuration)
        return try await withTaskCancellationHandler(operation:{
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                job.continuation=continuation
                job.start(ordinal:ordinal,language:language,script:script)
            }
        },onCancel:{Task{@MainActor in job.finish(.failure(CancellationError()))}})
    }
    private func start(ordinal:Int,language:String,script:URL?) {
        guard let url=script ?? Bundle.main.url(forResource:"MKVSubtitleExtractor",withExtension:"js"),
              let data=try? Data(contentsOf:url),data.count<131072,let source=String(data:data,encoding:.utf8),let js=JSContext() else{finish(.failure(Failure.unavailable));return}
        context=js
        js.exceptionHandler={ [weak self] _,_ in self?.finish(.failure(Failure.coverage)) }
        let decode:@convention(block)(JSValue)->String={ value in
            let bytes=(value.toArray() as? [NSNumber] ?? []).map{$0.uint8Value}
            return String(decoding:bytes,as:UTF8.self)
        }
        let encode:@convention(block)(String)->[UInt8]={Array($0.utf8)}
        let read:@convention(block)(Double,Double,JSValue,JSValue)->Void={ [weak self] first,last,resolve,reject in
            guard let self,self.active else{return}
            let id=UUID()
            self.tasks[id]=Task { [weak self] in
                guard let self else{return}
                defer{self.tasks[id]=nil}
                do {
                    let (body,total)=try await self.read(first:first,last:last)
                    guard self.active,!Task.isCancelled else{return}
                    resolve.call(withArguments:[Array(body),total])
                }catch {
                    guard self.active else{return}
                    reject.call(withArguments:["range"])
                }
            }
        }
        let done:@convention(block)(JSValue)->Void={ [weak self] result in
            guard let self,let object=result.toDictionary(),let text=object["text"] as? String,text.utf8.count<=1_048_576,
                  let count=object["frames"] as? NSNumber else{self?.finish(.failure(Failure.coverage));return}
            self.finish(.success(Output(text:text,bytes:self.bytes,requests:self.requests,frames:count.intValue)))
        }
        let failed:@convention(block)()->Void={ [weak self] in self?.finish(.failure(Failure.coverage)) }
        js.setObject(decode,forKeyedSubscript:"nativeDecode" as NSString)
        js.setObject(encode,forKeyedSubscript:"nativeEncode" as NSString)
        js.setObject(read,forKeyedSubscript:"nativeRead" as NSString)
        js.setObject(done,forKeyedSubscript:"nativeDone" as NSString)
        js.setObject(failed,forKeyedSubscript:"nativeFailed" as NSString)
        js.evaluateScript("""
        globalThis.TextDecoder=class {decode(a){return nativeDecode(Array.from(a||[]));}};
        globalThis.TextEncoder=class {encode(s){return new Uint8Array(nativeEncode(s));}};
        globalThis.fetch=(url,options)=>new Promise((resolve,reject)=>{
          const m=/^bytes=(\\d+)-(\\d+)$/.exec(options.headers.Range);
          if(!m){reject('range');return;}
          nativeRead(Number(m[1]),Number(m[2]),(a,total)=>resolve({status:206,
            headers:{get:()=>`bytes ${m[1]}-${Number(m[1])+a.length-1}/${total}`},
            arrayBuffer:async()=>new Uint8Array(a).buffer}),reject);
        });
        """)
        js.evaluateScript(source)
        guard active else{return}
        js.setObject(ordinal,forKeyedSubscript:"captionOrdinal" as NSString)
        js.setObject(language,forKeyedSubscript:"captionLanguage" as NSString)
        js.evaluateScript("CastMKV.indexedASS('native',captionOrdinal,captionLanguage).then(nativeDone,nativeFailed);")
        timer=Task{[weak self] in try? await Task.sleep(nanoseconds:12_000_000_000);guard !Task.isCancelled else{return};self?.finish(.failure(Failure.limit))}
    }
    private func read(first:Double,last:Double) async throws -> (Data,Int) {
        guard active,first.isFinite,last.isFinite,first>=0,last>=first,last-first<1_048_576,
              first.rounded(.down)==first,last.rounded(.down)==last,last<Double(Int.max),requests<2048,bytes<33_554_432 else{throw Failure.limit}
        requests+=1
        let start=Int(first),requestedEnd=Int(last)
        if input.isFileURL {
            let total=try input.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard start<total else{throw Failure.range}
            let file=try FileHandle(forReadingFrom:input);defer{try? file.close()}
            try file.seek(toOffset:UInt64(start));let data=try file.read(upToCount:min(requestedEnd-start+1,total-start)) ?? Data()
            bytes+=data.count;return(data,total)
        }
        var request=URLRequest(url:input);request.setValue("bytes=\(start)-\(requestedEnd)",forHTTPHeaderField:"Range")
        request.setValue("identity",forHTTPHeaderField:"Accept-Encoding")
        if let validator{request.setValue(validator,forHTTPHeaderField:"If-Range")}
        let (stream,response)=try await session.bytes(for:request)
        guard let http=response as? HTTPURLResponse,http.statusCode==206,
              let value=http.value(forHTTPHeaderField:"Content-Range"),value.hasPrefix("bytes ") else{throw Failure.range}
        let parts=value.dropFirst(6).split(whereSeparator:{$0=="-" || $0=="/"})
        guard parts.count==3,let actualStart=Int(parts[0]),let end=Int(parts[1]),let total=Int(parts[2]),
              actualStart==start,end==min(requestedEnd,total-1),total>start,end>=start,
              size==nil || size==total else{throw Failure.range}
        size=total
        let identity=http.value(forHTTPHeaderField:"ETag") ?? http.value(forHTTPHeaderField:"Last-Modified")
        if let validator,identity != validator{throw Failure.range}
        if validator==nil{validator=identity}
        var data=Data();data.reserveCapacity(end-start+1)
        for try await byte in stream {
            try Task.checkCancellation()
            guard active,data.count<end-start+1,bytes<33_554_432 else{throw Failure.limit}
            data.append(byte);bytes+=1
        }
        guard data.count==end-start+1 else{throw Failure.range}
        return(data,total)
    }
    private func finish(_ result:Result<Output,Error>) {
        guard active else{return};active=false
        timer?.cancel();timer=nil
        for task in tasks.values{task.cancel()};tasks.removeAll()
        session.invalidateAndCancel()
        let pending=continuation;continuation=nil
        context?.exceptionHandler=nil
        for name in ["nativeRead","nativeDone","nativeFailed"]{context?.setObject(NSNull(),forKeyedSubscript:name as NSString)}
        context=nil
        pending?.resume(with:result)
    }
}
private final class IndexedCaptionRedirect:NSObject,URLSessionTaskDelegate {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void) {
        guard let url=request.url,url.scheme=="https",url.user==nil,url.password==nil else{completionHandler(nil);return}
        completionHandler(request)
    }
}
