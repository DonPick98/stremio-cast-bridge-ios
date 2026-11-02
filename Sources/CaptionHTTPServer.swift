import Foundation
import Network

/// Captions only. Every endpoint is scoped to a random token and the selected
/// receiver address. No movie links, filenames or credentials are served.
final class CaptionHTTPServer: @unchecked Sendable {
    private let queue = DispatchQueue(label:"app.castbridge.caption-http")
    private let localIP:String, peer:String
    private let token = UUID().uuidString.replacingOccurrences(of:"-",with:"")
    private var listener:NWListener?
    private var opening:CheckedContinuation<URL,Error>?
    private var connections:[UUID:NWConnection] = [:]
    private var assets:[String:(Data,String)] = [:]
    private var order:[String] = []
    private var state = Data("{}".utf8)
    private var stateEpoch = ""
    private var port:UInt16 = 0
    var onPosition:(@Sendable (String,Double,Bool)->Void)?
    init(localIP:String,peer:String){self.localIP=localIP;self.peer=peer}
    var prefix:String { "/captions/\(token)/" }
    func start() async throws -> URL {
        guard (CastWire.localIPv4(localIP) && CastWire.localIPv4(peer)) || (localIP == "127.0.0.1" && peer == "127.0.0.1") else { throw CaptionFailure.network }
        return try await withCheckedThrowingContinuation { c in
            queue.async {
                do {
                    self.opening=c
                    let parameters=NWParameters.tcp
                    parameters.requiredLocalEndpoint = .hostPort(host:NWEndpoint.Host(self.localIP),port:.any)
                    let listener=try NWListener(using:parameters);self.listener=listener
                    listener.stateUpdateHandler = { state in
                        if case .ready = state, let port=listener.port?.rawValue {
                            self.port=port;let ready=self.opening;self.opening=nil
                            ready?.resume(returning:URL(string:"http://\(self.localIP):\(port)\(self.prefix)state")!)
                        } else if case .failed = state { self.finish() }
                    }
                    listener.newConnectionHandler = { [weak self] in self?.accept($0) }
                    listener.start(queue:self.queue)
                    self.queue.asyncAfter(deadline:.now()+5){if self.opening != nil {self.finish()}}
                }catch{self.opening=nil;c.resume(throwing:CaptionFailure.network)}
            }
        }
    }
    func setState(epoch:String,data:Data){queue.async { if data.count <= 16384 {self.stateEpoch=epoch;self.state=data} }}
    func clearAssets(){queue.async{self.assets.removeAll();self.order.removeAll()}}
    func publish(_ data:Data,format:CaptionFormat) async throws -> URL {
        try await publish(data,extension:format.rawValue,type:format == .vtt ? "text/vtt; charset=utf-8":"text/plain; charset=utf-8",font:false)
    }
    func publishFont(_ font:CaptionFontData) async throws -> URL {
        guard ["ttf","otf","woff","woff2"].contains(font.kind) else{throw CaptionFailure.input}
        return try await publish(font.data,extension:font.kind,type:"font/"+font.kind,font:true)
    }
    private func publish(_ data:Data,extension ext:String,type:String,font:Bool) async throws -> URL {
        guard data.count <= 2_097_152 else {throw CaptionFailure.limit}
        return try await withCheckedThrowingContinuation { c in queue.async {
            guard self.port > 0 else {c.resume(throwing:CaptionFailure.network);return}
            let path=self.prefix+UUID().uuidString+"."+ext
            self.assets[path]=(data,type);if !font{self.order.append(path)}
            while !self.order.isEmpty && (self.order.count > 24 || self.assets.values.reduce(0,{$0+$1.0.count}) > 33_554_432) {
                let old=self.order.removeFirst();self.assets.removeValue(forKey:old)
            }
            c.resume(returning:URL(string:"http://\(self.localIP):\(self.port)\(path)")!)
        }}
    }
    private func accept(_ connection:NWConnection){
        guard connections.count < 8, case .hostPort(let host,_) = connection.endpoint, String(describing:host).replacingOccurrences(of:"::ffff:",with:"") == peer else {connection.cancel();return}
        let id=UUID();connections[id]=connection;connection.start(queue:queue)
        read(connection,id:id,buffer:Data())
        queue.asyncAfter(deadline:.now()+8){self.close(id)}
    }
    private func read(_ connection:NWConnection,id:UUID,buffer:Data){
        connection.receive(minimumIncompleteLength:1,maximumLength:4096){data,_,done,error in
            var buffer=buffer;if let data{buffer.append(data)}
            guard buffer.count <= 8192 else {self.reply(id,status:400);return}
            if buffer.range(of:Data("\r\n\r\n".utf8)) != nil {
                guard let text=String(data:buffer,encoding:.utf8),let line=text.components(separatedBy:"\r\n").first else {self.reply(id,status:400);return}
                let parts=line.split(separator:" ");guard parts.count == 3, ["GET","HEAD","OPTIONS"].contains(String(parts[0])),parts[1].hasPrefix(self.prefix),
                    let url=URLComponents(string:"http://local"+parts[1]) else {self.reply(id,status:404);return}
                if parts[0] == "OPTIONS" {self.reply(id,status:204);return}
                if url.path == self.prefix+"state" {
                    let values=Dictionary(url.queryItems?.map{($0.name,$0.value ?? "")} ?? [],uniquingKeysWith:{_,last in last})
                    guard values["epoch"] == self.stateEpoch else {self.reply(id,status:410);return}
                    if let raw=values["position"],let position=Double(raw),position.isFinite,position>=0,position<1e8 {
                        self.onPosition?(self.stateEpoch,position,values["paused"] == "1")
                    }
                    self.reply(id,status:200,type:"application/json",body:self.state,head:parts[0] == "HEAD");return
                }
                guard let asset=self.assets[url.path] else {self.reply(id,status:410);return}
                self.reply(id,status:200,type:asset.1,body:asset.0,head:parts[0] == "HEAD")
            }else if done || error != nil{self.close(id)}else{self.read(connection,id:id,buffer:buffer)}
        }
    }
    private func reply(_ id:UUID,status:Int,type:String="text/plain",body:Data=Data(),head:Bool=false){
        guard let connection=connections[id] else{return}
        var data=Data("HTTP/1.1 \(status) Response\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, HEAD, OPTIONS\r\nAccess-Control-Allow-Headers: Range, Content-Type, Accept-Encoding\r\nAccess-Control-Allow-Private-Network: true\r\nConnection: close\r\n\r\n".utf8)
        if !head{data.append(body)}
        connection.send(content:data,completion:.contentProcessed{_ in self.close(id)})
    }
    private func close(_ id:UUID){connections.removeValue(forKey:id)?.cancel()}
    private func finish(){let c=opening;opening=nil;c?.resume(throwing:CaptionFailure.network);listener?.cancel();listener=nil;for id in Array(connections.keys){close(id)};assets.removeAll();order.removeAll();port=0}
    func stop(){queue.async{self.finish()}}
}

/// Standard receiver text service. It never reads or relays video bytes.
@MainActor final class StandardCaptionHost {
    private var server:CaptionHTTPServer?
    private var previous:CaptionHTTPServer?
    private var revision=UUID()
    private(set) var urls:[Int:URL]=[:]
    private(set) var identity=""
    private(set) var peer=""
    private(set) var window=SubtitleWindow(center:0)
    func identifier(kind:Int,delay:Double)->Int?{
        guard let id=window.identifier(kind:kind,delay:delay),urls[id] != nil else{return nil};return id
    }
    func prepare(text:String,kind:Int,identity:String,delay:Double,peer:String,localIP:String) async throws {
        let token=UUID();revision=token
        let candidate=CaptionHTTPServer(localIP:localIP,peer:peer)
        var installed=false;defer{if !installed{candidate.stop()}}
        _ = try await candidate.start()
        let nextWindow=SubtitleWindow(center:delay)
        var next:[Int:URL]=[:]
        for variant in nextWindow.variants(kind:kind){
            try Task.checkCancellation();guard revision==token else{throw CancellationError()}
            next[variant.id]=try await candidate.publish(WebVTTTimeline.rebased(text,offset:0,delay:variant.delay),format:.vtt)
        }
        try Task.checkCancellation();guard revision==token else{throw CancellationError()}
        // Keep the previous URLs alive until the replacement LOAD is acknowledged.
        previous?.stop();previous=server;server=candidate;installed=true
        urls=next;window=nextWindow;self.identity=identity;self.peer=peer
    }
    func acknowledge(){previous?.stop();previous=nil}
    func cancelPreparation(){revision=UUID()}
    func stop(){revision=UUID();server?.stop();previous?.stop();server=nil;previous=nil;urls=[:];identity="";peer=""}
    static func supportsDirectMedia(_ url:URL) async -> Bool {
        guard url.scheme=="https",url.user==nil,url.password==nil else{return false}
        let config=URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest=4;config.timeoutIntervalForResource=6
        config.httpCookieStorage=nil;config.urlCredentialStorage=nil;config.urlCache=nil
        let session=URLSession(configuration:config);defer{session.invalidateAndCancel()}
        do{
            // Read headers only, even if a server ignores Range and returns a movie.
            var request=URLRequest(url:url);request.setValue("https://www.gstatic.com",forHTTPHeaderField:"Origin")
            request.setValue("bytes=0-0",forHTTPHeaderField:"Range")
            let (_,response)=try await session.bytes(for:request)
            guard let response=response as? HTTPURLResponse,DirectCaptionPolicy.allows(response:response,preflight:false),response.url?.scheme=="https" else{return false}
            try Task.checkCancellation()
            request.httpMethod="OPTIONS";request.setValue(nil,forHTTPHeaderField:"Range")
            request.setValue("GET",forHTTPHeaderField:"Access-Control-Request-Method")
            request.setValue("range, content-type, accept-encoding",forHTTPHeaderField:"Access-Control-Request-Headers")
            let (_,preflight)=try await session.bytes(for:request)
            guard let preflight=preflight as? HTTPURLResponse else{return false}
            return DirectCaptionPolicy.allows(response:preflight,preflight:true)
        }catch{return false}
    }
}
