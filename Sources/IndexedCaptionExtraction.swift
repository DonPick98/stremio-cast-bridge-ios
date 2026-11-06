import Foundation
import JavaScriptCore

/// Complete indexed Matroska extraction. No movie URL or subtitle text is logged.
@MainActor final class IndexedCaptionExtraction {
    enum Failure:LocalizedError {
        case unavailable,range,limit,coverage,cancelled,index(String)
        var errorDescription:String? {"Indexed captions: "+IndexedCaptionExtraction.failureCode(self)}
    }
    nonisolated static func failureCode(_ error:Error)->String {
        guard let failure=error as? Failure else{return "document"}
        switch failure {
        case .unavailable:return "unavailable"
        case .range:return "range"
        case .limit:return "limit"
        case .coverage:return "coverage"
        case .cancelled:return "cancelled"
        case .index(let code):return code
        }
    }
    struct Output {let text:String;let bytes:Int;let requests:Int;let frames:Int}
    private let input:URL
    private let transport:IndexedRangeTransport
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
        transport=IndexedRangeTransport(configuration:config)
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
                    resolve.call(withArguments:[body.base64EncodedString(),total])
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
        let failed:@convention(block)(JSValue)->Void={ [weak self] reason in
            let raw=reason.isString ? reason.toString():reason.forProperty("message")?.toString()
            let code=raw ?? "coverage"
            let known=["uid","index","codec","encoding","track","limit","count","coverage","cluster","truncated","range"]
            let safe=known.contains(code) || (code.count<40 && code.range(of:#"^(frames|blocks)_[0-9]+_[0-9]+$"#,options:.regularExpression) != nil)
            self?.finish(.failure(safe ? Failure.index(code):Failure.coverage))
        }
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
          nativeRead(Number(m[1]),Number(m[2]),(s,total)=>{
            // Pass binary chunks as one string, avoiding tens of thousands of
            // NSNumber/JSValue objects for each Range response.
            const alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
            const table=new Uint8Array(128);
            for(let i=0;i<64;i++)table[alphabet.charCodeAt(i)]=i;
            const length=s.length/4*3-(s.endsWith('==')?2:s.endsWith('=')?1:0);
            const a=new Uint8Array(length);let j=0;
            for(let i=0;i<s.length;i+=4){
              const v=table[s.charCodeAt(i)]<<18|table[s.charCodeAt(i+1)]<<12|table[s.charCodeAt(i+2)]<<6|table[s.charCodeAt(i+3)];
              if(j<length)a[j++]=v>>16;if(j<length)a[j++]=v>>8;if(j<length)a[j++]=v;
            }
            resolve({status:206,headers:{get:()=>`bytes ${m[1]}-${Number(m[1])+a.length-1}/${total}`},arrayBuffer:async()=>a.buffer});
          },reject);
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
        let (data,http)=try await transport.read(request:request,start:start,end:requestedEnd,size:size,validator:validator)
        let value=http.value(forHTTPHeaderField:"Content-Range")!
        let total=Int(value.split(separator:"/").last!)!
        guard size==nil || size==total else{throw Failure.range}
        size=total
        let identity=http.value(forHTTPHeaderField:"ETag") ?? http.value(forHTTPHeaderField:"Last-Modified")
        if let validator,identity != validator{throw Failure.range}
        if validator==nil{validator=identity}
        bytes+=data.count
        return(data,total)
    }
    private func finish(_ result:Result<Output,Error>) {
        guard active else{return};active=false
        timer?.cancel();timer=nil
        for task in tasks.values{task.cancel()};tasks.removeAll()
        transport.stop()
        let pending=continuation;continuation=nil
        context?.exceptionHandler=nil
        for name in ["nativeRead","nativeDone","nativeFailed"]{context?.setObject(NSNull(),forKeyedSubscript:name as NSString)}
        context=nil
        pending?.resume(with:result)
    }
}
/// Bounded chunk transport. URLSession delegate callbacks receive Data blocks,
/// avoiding an actor/async iterator transition for every byte of binary media.
private final class IndexedRangeTransport:NSObject,URLSessionDataDelegate,@unchecked Sendable {
    private final class Ticket:@unchecked Sendable {
        let lock=NSLock();var task:URLSessionDataTask?;var cancelled=false
        func assign(_ task:URLSessionDataTask){lock.lock();self.task=task;let cancel=cancelled;lock.unlock();if cancel{task.cancel()}}
        func cancel(){lock.lock();cancelled=true;let task=task;lock.unlock();task?.cancel()}
    }
    private final class Entry {
        let start:Int,end:Int,size:Int?,validator:String?
        let continuation:CheckedContinuation<(Data,HTTPURLResponse),Error>
        var response:HTTPURLResponse?,expected=0,data=Data()
        init(start:Int,end:Int,size:Int?,validator:String?,continuation:CheckedContinuation<(Data,HTTPURLResponse),Error>){self.start=start;self.end=end;self.size=size;self.validator=validator;self.continuation=continuation}
    }
    private let lock=NSLock()
    private var entries:[Int:Entry]=[:],received=0
    private var session:URLSession!
    init(configuration:URLSessionConfiguration){super.init();session=URLSession(configuration:configuration,delegate:self,delegateQueue:nil)}
    func read(request:URLRequest,start:Int,end:Int,size:Int?,validator:String?)async throws->(Data,HTTPURLResponse){
        let ticket=Ticket()
        return try await withTaskCancellationHandler(operation:{
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation{ continuation in
                let task=session.dataTask(with:request)
                let entry=Entry(start:start,end:end,size:size,validator:validator,continuation:continuation)
                lock.lock();entries[task.taskIdentifier]=entry;lock.unlock()
                ticket.assign(task);task.resume()
            }
        },onCancel:{ticket.cancel()})
    }
    func stop(){session.invalidateAndCancel()}
    private func fail(_ task:URLSessionTask,_ error:Error){
        lock.lock();let entry=entries.removeValue(forKey:task.taskIdentifier);lock.unlock()
        task.cancel();entry?.continuation.resume(throwing:error)
    }
    func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive response:URLResponse,completionHandler:@escaping(URLSession.ResponseDisposition)->Void){
        lock.lock();let entry=entries[dataTask.taskIdentifier];lock.unlock()
        guard let entry,let http=response as? HTTPURLResponse,http.statusCode==206,
              let value=http.value(forHTTPHeaderField:"Content-Range"),value.hasPrefix("bytes ") else{completionHandler(.cancel);fail(dataTask,IndexedCaptionExtraction.Failure.range);return}
        let p=value.dropFirst(6).split(whereSeparator:{$0=="-" || $0=="/"})
        let identity=http.value(forHTTPHeaderField:"ETag") ?? http.value(forHTTPHeaderField:"Last-Modified")
        guard p.count==3,let start=Int(p[0]),let end=Int(p[1]),let total=Int(p[2]),
              start==entry.start,total>start,end==min(entry.end,total-1),end>=start,
              entry.size==nil || entry.size==total,entry.validator==nil || entry.validator==identity,
              end-start+1<=1_048_576 else{completionHandler(.cancel);fail(dataTask,IndexedCaptionExtraction.Failure.range);return}
        entry.response=http;entry.expected=end-start+1;entry.data.reserveCapacity(entry.expected)
        completionHandler(.allow)
    }
    func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive data:Data){
        lock.lock()
        guard let entry=entries[dataTask.taskIdentifier] else{lock.unlock();return}
        guard entry.response != nil,entry.data.count+data.count<=entry.expected,received+data.count<=33_554_432 else{lock.unlock();fail(dataTask,IndexedCaptionExtraction.Failure.limit);return}
        entry.data.append(data);received+=data.count;lock.unlock()
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?){
        lock.lock();let entry=entries.removeValue(forKey:task.taskIdentifier);lock.unlock()
        guard let entry else{return}
        if let error{entry.continuation.resume(throwing:error)}
        else if let response=entry.response,entry.data.count==entry.expected{entry.continuation.resume(returning:(entry.data,response))}
        else{entry.continuation.resume(throwing:IndexedCaptionExtraction.Failure.range)}
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void){
        guard let url=request.url,url.scheme=="https",url.user==nil,url.password==nil else{completionHandler(nil);return}
        completionHandler(request)
    }
}
