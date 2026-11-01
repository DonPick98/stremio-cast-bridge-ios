import Foundation
import Network
import Darwin

enum LocalStreamError: Error { case address, listener, request, upstream, initialization }

/// An anonymous socket pair retains every encoder packet. Unlike VLC's live
/// HTTP circular buffer, it cannot skip an initial GOP or overwrite a slow reader.
final class MediaOutputChannel: @unchecked Sendable {
    private let queue = DispatchQueue(label:"app.castbridge.media-output")
    private let reader:Int32
    let writer:Int32
    private var listener:NWListener?
    private var client:NWConnection?
    private var source:DispatchSourceRead?
    private var suspended = false
    private var stopped = false
    private var opening:CheckedContinuation<Void,Error>?
    init() throws {
        var pair:[Int32] = [-1,-1]
        guard Darwin.socketpair(AF_UNIX,SOCK_STREAM,0,&pair) == 0 else { throw LocalStreamError.listener }
        reader = pair[0]; writer = pair[1]
        _ = fcntl(reader,F_SETFL,O_NONBLOCK)
        var flag:Int32 = 1
        _ = setsockopt(writer,SOL_SOCKET,SO_NOSIGPIPE,&flag,socklen_t(MemoryLayout<Int32>.size))
    }
    deinit { Darwin.close(writer) }
    func start(port:UInt16,path:String,type:String) async throws {
        try await withCheckedThrowingContinuation { (c:CheckedContinuation<Void,Error>) in
            queue.async {
                self.opening = c
                do {
                    let params = NWParameters.tcp
                    params.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:NWEndpoint.Port(rawValue:port)!)
                    let listener = try NWListener(using:params); self.listener = listener
                    listener.stateUpdateHandler = { [weak self] state in
                        guard let self, !self.stopped else { return }
                        if case .ready = state { let c = self.opening; self.opening = nil; c?.resume() }
                        else if case .failed = state { self.finish() }
                    }
                    listener.newConnectionHandler = { [weak self] connection in
                        guard let self, !self.stopped, self.client == nil else { connection.cancel(); return }
                        self.client = connection
                        connection.stateUpdateHandler = { [weak self] state in if case .failed = state { self?.finish() } }
                        connection.start(queue:self.queue)
                        self.request(connection,path:path,type:type,buffer:Data())
                    }
                    listener.start(queue:self.queue)
                    self.queue.asyncAfter(deadline:.now()+8) { if self.opening != nil { self.finish() } }
                } catch { self.finish() }
            }
        }
    }
    private func request(_ client:NWConnection,path:String,type:String,buffer:Data) {
        client.receive(minimumIncompleteLength:1,maximumLength:4096) { [weak self] data,_,complete,error in
            guard let self, !self.stopped else { return }
            var buffer = buffer; if let data { buffer.append(data) }
            do {
                if let method = try LocalStreamProxy.method(buffer,path:path), method == "GET" {
                    let header = Data("HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nConnection: close\r\n\r\n".utf8)
                    client.send(content:header,completion:.contentProcessed { [weak self] error in
                        guard let self, !self.stopped else { return }
                        if error != nil { self.finish(); return }
                        let source = DispatchSource.makeReadSource(fileDescriptor:self.reader,queue:self.queue)
                        self.source = source
                        source.setEventHandler { [weak self] in self?.pump() }
                        let fd = self.reader; source.setCancelHandler { Darwin.close(fd) }
                        source.resume()
                    })
                } else if complete || error != nil { self.finish() }
                else { self.request(client,path:path,type:type,buffer:buffer) }
            } catch { self.finish() }
        }
    }
    private func pump() {
        guard !stopped, !suspended, let source, let client else { return }
        source.suspend(); suspended = true
        var bytes = [UInt8](repeating:0,count:16_384)
        let count = Darwin.read(reader,&bytes,16_384)
        if count > 0 {
            client.send(content:Data(bytes.prefix(count)),completion:.contentProcessed { [weak self] error in
                guard let self, !self.stopped else { return }
                if error != nil { self.finish() }
                else { self.suspended = false; self.source?.resume() }
            })
        } else if count == 0 {
            client.send(content:nil,contentContext:.finalMessage,isComplete:true,completion:.contentProcessed { [weak self] _ in self?.finish() })
        } else if errno == EAGAIN || errno == EINTR { suspended = false; source.resume() }
        else { finish() }
    }
    func endWriting() { queue.async { _ = Darwin.shutdown(self.writer,SHUT_WR) } }
    func stop() { queue.async { self.finish() } }
    private func finish() {
        guard !stopped else { return }; stopped = true
        let c = opening; opening = nil; c?.resume(throwing:LocalStreamError.listener)
        listener?.stateUpdateHandler = nil; listener?.newConnectionHandler = nil; listener?.cancel(); listener = nil
        client?.stateUpdateHandler = nil; client?.cancel(); client = nil
        // Shutdown also unblocks VLC's duplicated writer before it is released.
        _ = Darwin.shutdown(reader,SHUT_RDWR)
        if let source { if suspended { suspended = false; source.resume() }; source.cancel(); self.source = nil }
        else { Darwin.close(reader) }
        _ = Darwin.shutdown(writer,SHUT_RDWR)
    }
}

/// Exact-token, selected-device-only HTTP bridge. It adds the CORS headers Cast
/// needs for external subtitles and applies TCP backpressure to the local encoder.
final class LocalStreamProxy: @unchecked Sendable {
    private let queue = DispatchQueue(label:"app.castbridge.local-stream")
    let token = UUID().uuidString.replacingOccurrences(of:"-",with:"")
    private let localIP: String
    private let peer: String
    private let producerPort: UInt16
    private let contentType: String
    private let captions: [Int:Data]
    private var listener: NWListener?
    private var opening: CheckedContinuation<URL,Error>?
    private var pairs: [UUID:Pair] = [:]
    private var stopped = false
    private var producerEnded = false
    private func trace(_ message:String) {
#if CAST_ENGINE_TESTING
        FileHandle.standardOutput.write(Data("Cast proxy \(Date().timeIntervalSince1970): \(message)\n".utf8))
#endif
    }
    private var preparing: CheckedContinuation<Void,Error>?
    private var warm: Warm?
    private final class Warm {
        let connection: NWConnection
        var header = Data()
        var body = Data()
        var complete = false
        var ready = false
        init(_ connection:NWConnection) { self.connection = connection }
    }
    private final class Pair {
        let client: NWConnection
        var producer: NWConnection?
        var waiting = false
        var sending = false
        var lastData = Date()
        init(_ client: NWConnection) { self.client = client }
    }
    init(localIP:String, peer:String, producerPort:UInt16, contentType:String = "video/mp4", captions:[Int:Data] = [:]) {
        self.localIP = localIP; self.peer = peer; self.producerPort = producerPort; self.contentType = contentType; self.captions = captions
    }
    var path: String { "/\(token)/stream.mp4" }
    func start() async throws -> URL {
        guard (CastWire.localIPv4(localIP) && CastWire.localIPv4(peer)) || (localIP == "127.0.0.1" && peer == "127.0.0.1") else { throw LocalStreamError.address }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard !self.stopped else { continuation.resume(throwing:CancellationError()); return }
                self.opening = continuation
                do {
                    let parameters = NWParameters.tcp
                    parameters.requiredLocalEndpoint = .hostPort(host:NWEndpoint.Host(self.localIP),port:.any)
                    let listener = try NWListener(using:parameters)
                    self.listener = listener
                    listener.stateUpdateHandler = { [weak self] state in
                        guard let self else { return }
                        if case .ready = state, let port = listener.port,
                           let url = URL(string:"http://\(self.localIP):\(port.rawValue)\(self.path)") {
                            let c = self.opening; self.opening = nil; c?.resume(returning:url)
                        } else if case .failed = state { self.finish() }
                    }
                    listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                    listener.start(queue:self.queue)
                    self.queue.asyncAfter(deadline:.now()+8) { if self.opening != nil { self.finish() } }
                } catch { self.opening = nil; continuation.resume(throwing:LocalStreamError.listener) }
            }
        }
    }
    func stop() { queue.async { self.finish() } }
    /// Keep the validated initialization and first media bytes on the very
    /// connection that the receiver will consume, rather than probing and
    /// discarding the beginning of a short video.
    func prepare(onHeaders: (@Sendable () -> Void)? = nil) async throws {
        try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
            queue.async {
                guard !self.stopped, self.warm == nil, let port = NWEndpoint.Port(rawValue:self.producerPort) else { continuation.resume(throwing:LocalStreamError.upstream); return }
                self.preparing = continuation
                let stream = Warm(NWConnection(host:"127.0.0.1",port:port,using:.tcp))
                self.warm = stream
                stream.connection.stateUpdateHandler = { [weak self] state in
                    guard let self, self.warm === stream else { return }
                    if case .ready = state {
                        let request = "GET \(self.path) HTTP/1.1\r\nHost: 127.0.0.1:\(self.producerPort)\r\nConnection: close\r\n\r\n"
                        stream.connection.send(content:Data(request.utf8),completion:.contentProcessed { error in
                            if error != nil { self.failPreparation() } else { self.readWarmHeader(stream,buffer:Data(),onHeaders:onHeaders) }
                        })
                    } else if case .failed = state { self.failPreparation(error:.upstream) }
                }
                stream.connection.start(queue:self.queue)
                self.queue.asyncAfter(deadline:.now()+15) { if self.preparing != nil { self.failPreparation() } }
            }
        }
    }
    private func failPreparation(error:LocalStreamError = .initialization) {
        warm?.connection.stateUpdateHandler = nil; warm?.connection.cancel(); warm = nil
        let c = preparing; preparing = nil; c?.resume(throwing:error)
    }
    private func readWarmHeader(_ stream:Warm,buffer:Data,onHeaders:(@Sendable () -> Void)?) {
        stream.connection.receive(minimumIncompleteLength:1,maximumLength:65_536) { [weak self] data,_,complete,error in
            guard let self, self.warm === stream, self.preparing != nil else { return }
            var received = buffer; if let data { received.append(data) }
            do {
                if let (header,body) = try Self.responseHeader(received,contentType:self.contentType) {
                    stream.header = header; stream.body = body; stream.complete = complete
                    onHeaders?()
                    self.validateWarm(stream)
                } else if complete || error != nil { self.failPreparation() }
                else { self.readWarmHeader(stream,buffer:received,onHeaders:onHeaders) }
            } catch { self.failPreparation() }
        }
    }
    private func validateWarm(_ stream:Warm) {
        do {
            if try PlayableStreamHeader.check(stream.body,contentType:contentType) {
                stream.ready = true
                let c = preparing; preparing = nil; c?.resume(); return
            }
            guard !stream.complete, stream.body.count < 1_048_576 else { failPreparation(); return }
            stream.connection.receive(minimumIncompleteLength:1,maximumLength:min(65_536,1_048_576-stream.body.count)) { [weak self] data,_,complete,error in
                guard let self, self.warm === stream, self.preparing != nil else { return }
                if let data { stream.body.append(data) }; stream.complete = complete
                if error != nil { self.failPreparation() } else { self.validateWarm(stream) }
            }
        } catch { failPreparation() }
    }
    func producerDidEnd() { queue.async { self.producerEnded = true; self.finishDrainedStreams() } }
    private func finishDrainedStreams() {
        guard producerEnded, !stopped else { return }
        for (id,pair) in pairs where pair.producer != nil && pair.waiting && !pair.sending && Date().timeIntervalSince(pair.lastData) > 1 {
            pair.waiting = false
            pair.client.send(content:nil,contentContext:.finalMessage,isComplete:true,completion:.contentProcessed { [weak self] _ in self?.close(id) })
        }
        queue.asyncAfter(deadline:.now()+0.5) { [weak self] in self?.finishDrainedStreams() }
    }
    private func finish() {
        stopped = true
        failPreparation()
        listener?.stateUpdateHandler = nil; listener?.newConnectionHandler = nil
        listener?.cancel(); listener = nil
        let c = opening; opening = nil; c?.resume(throwing:LocalStreamError.listener)
        for pair in pairs.values { pair.client.stateUpdateHandler = nil; pair.producer?.stateUpdateHandler = nil; pair.client.cancel(); pair.producer?.cancel() }
        pairs.removeAll()
    }
    private func close(_ id: UUID) {
        guard let pair = pairs.removeValue(forKey:id) else { return }
        pair.client.stateUpdateHandler = nil; pair.producer?.stateUpdateHandler = nil
        pair.client.cancel(); pair.producer?.cancel()
    }
    private func accept(_ client: NWConnection) {
        trace("accept \(client.endpoint)")
        guard !stopped, pairs.count < 8, case .hostPort(let host,_) = client.endpoint,
              String(describing:host).components(separatedBy:"%")[0] == peer else { client.cancel(); return }
        let id = UUID(); pairs[id] = Pair(client)
        client.stateUpdateHandler = { [weak self] state in if case .failed = state { self?.close(id) } }
        client.start(queue:queue)
        request(id,buffer:Data())
        queue.asyncAfter(deadline:.now()+20) { [weak self] in
            if let pair = self?.pairs[id], pair.producer == nil { self?.close(id) }
        }
    }
    static func method(_ data: Data, path: String, additionalPaths:[String] = []) throws -> String? {
        guard data.count <= 8192 else { throw LocalStreamError.request }
        guard let range = data.range(of:Data("\r\n\r\n".utf8)) else { return nil }
        guard range.upperBound == data.endIndex,
              let header = String(data:data[..<range.lowerBound],encoding:.utf8),
              let line = header.components(separatedBy:"\r\n").first else { throw LocalStreamError.request }
        let parts = line.split(separator:" ",omittingEmptySubsequences:false)
        guard parts.count == 3, ["GET","HEAD","OPTIONS"].contains(String(parts[0])),
              ([path]+additionalPaths).contains(String(parts[1])), ["HTTP/1.0","HTTP/1.1"].contains(String(parts[2])) else { throw LocalStreamError.request }
        return String(parts[0])
    }
    private func request(_ id: UUID, buffer: Data) {
        guard let pair = pairs[id] else { return }
        pair.client.receive(minimumIncompleteLength:1,maximumLength:4096) { [weak self] data,_,complete,error in
            guard let self, let pair = self.pairs[id] else { return }
            var received = buffer; if let data { received.append(data) }
            do {
                let captionPaths = self.captions.keys.map { "/\(self.token)/subtitle-\($0).vtt" }
                if let method = try Self.method(received,path:self.path,additionalPaths:captionPaths) {
                    self.trace("request \(method), warm=\(self.warm?.ready == true)")
                    if method == "OPTIONS" {
                        let reply = "HTTP/1.1 204 No Content\r\n\(Self.cors)Content-Length: 0\r\nConnection: close\r\n\r\n"
                        pair.client.send(content:Data(reply.utf8),completion:.contentProcessed { _ in self.close(id) })
                    } else {
                        let firstLine = String(data:received,encoding:.utf8)?.components(separatedBy:"\r\n").first ?? ""
                        let parts = firstLine.split(separator:" ")
                        let requested = parts.count > 1 ? String(parts[1]) : ""
                        if let key = self.captions.keys.first(where:{requested == "/\(self.token)/subtitle-\($0).vtt"}), let caption = self.captions[key] {
                            let head = "HTTP/1.1 200 OK\r\n\(Self.cors)Content-Type: text/vtt; charset=utf-8\r\nContent-Length: \(caption.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
                            let content = Data(head.utf8) + (method == "HEAD" ? Data() : caption)
                            pair.client.send(content:content,isComplete:true,completion:.contentProcessed { _ in self.close(id) })
                        } else { self.connectProducer(id,method:method) }
                    }
                } else if complete || error != nil { self.close(id) }
                else { self.request(id,buffer:received) }
            } catch { self.close(id) }
        }
    }
    private static let cors = "Access-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, HEAD, OPTIONS\r\nAccess-Control-Allow-Headers: Range, Content-Type, Accept\r\nAccess-Control-Expose-Headers: Content-Length, Content-Range, Accept-Ranges\r\n"
    static func responseHeader(_ data: Data, contentType: String = "video/mp4") throws -> (Data,Data)? {
        guard data.count <= 81_920 else { throw LocalStreamError.upstream }
        guard let range = data.range(of:Data("\r\n\r\n".utf8)) else {
            if data.count > 16_384 { throw LocalStreamError.upstream }
            return nil
        }
        guard range.lowerBound <= 16_384, let header = String(data:data[..<range.lowerBound],encoding:.utf8) else { throw LocalStreamError.upstream }
        var lines = header.components(separatedBy:"\r\n")
        guard let status = lines.first?.split(separator:" "), status.count >= 2, status[1] == "200" else { throw LocalStreamError.upstream }
        lines.removeFirst()
        let forbidden = ["content-type","connection","cache-control","access-control-allow-origin","accept-ranges","set-cookie"]
        lines = lines.filter { line in
            guard let colon = line.firstIndex(of:":") else { return false }
            return !forbidden.contains(line[..<colon].trimmingCharacters(in:.whitespaces).lowercased())
        }
        guard ["video/mp4","video/webm"].contains(contentType) else { throw LocalStreamError.upstream }
        let head = "HTTP/1.1 200 OK\r\n" + lines.map{$0+"\r\n"}.joined() + cors + "Content-Type: \(contentType)\r\nCache-Control: no-store\r\nAccept-Ranges: none\r\nConnection: close\r\n\r\n"
        return (Data(head.utf8),Data(data[range.upperBound...]))
    }
    private func connectProducer(_ id: UUID, method: String) {
        guard let pair = pairs[id], let port = NWEndpoint.Port(rawValue:producerPort) else { close(id); return }
        if method == "HEAD" {
            let header = Data("HTTP/1.1 200 OK\r\n\(Self.cors)Content-Type: \(contentType)\r\nAccept-Ranges: none\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
            pair.client.send(content:header,contentContext:.finalMessage,isComplete:true,completion:.contentProcessed { [weak self] _ in self?.close(id) })
            return
        }
        if let stream = warm, stream.ready {
            trace("warm transfer header=\(stream.header.count) body=\(stream.body.count)")
            if method == "HEAD" {
                pair.client.send(content:stream.header,contentContext:.finalMessage,isComplete:true,completion:.contentProcessed { [weak self] _ in self?.close(id) })
                return
            }
            warm = nil; stream.connection.stateUpdateHandler = nil
            pair.producer = stream.connection
            stream.connection.stateUpdateHandler = { [weak self] state in if case .failed = state { self?.close(id) } }
            pair.client.send(content:stream.header+stream.body,contentContext:stream.complete ? .finalMessage : .defaultMessage,isComplete:true,completion:.contentProcessed { [weak self] error in
                guard let self else { return }
                self.trace("warm send done error=\(String(describing:error))")
                if error != nil || stream.complete { self.close(id) } else { self.pipe(id) }
            })
            return
        }
        let upstream = NWConnection(host:"127.0.0.1",port:port,using:.tcp)
        pair.producer = upstream
        var sent = false
        upstream.stateUpdateHandler = { [weak self] state in
            guard let self, self.pairs[id] != nil else { return }
            if case .ready = state, !sent {
                sent = true
                let head = "\(method) \(self.path) HTTP/1.1\r\nHost: 127.0.0.1:\(self.producerPort)\r\nConnection: close\r\n\r\n"
                upstream.send(content:Data(head.utf8),completion:.contentProcessed { error in
                    if error != nil { self.close(id) } else { self.upstreamHeader(id,buffer:Data()) }
                })
            } else if case .failed = state { self.close(id) }
        }
        upstream.start(queue:queue)
    }
    private func upstreamHeader(_ id: UUID, buffer: Data) {
        guard let pair = pairs[id], let upstream = pair.producer else { return }
        upstream.receive(minimumIncompleteLength:1,maximumLength:65_536) { [weak self] data,_,complete,error in
            guard let self, let pair = self.pairs[id] else { return }
            var received = buffer; if let data { received.append(data) }
            do {
                if let (header,body) = try Self.responseHeader(received,contentType:self.contentType) {
                    pair.client.send(content:header+body,contentContext:complete ? .finalMessage : .defaultMessage,isComplete:complete,completion:.contentProcessed { error in
                        if error != nil { self.close(id) }
                        else if complete { self.close(id) }
                        else { self.pipe(id) }
                    })
                } else if error != nil || complete { self.close(id) }
                else { self.upstreamHeader(id,buffer:received) }
            } catch { self.close(id) }
        }
    }
    private func pipe(_ id: UUID) {
        guard let pair = pairs[id], let upstream = pair.producer else { return }
        pair.waiting = true
        upstream.receive(minimumIncompleteLength:1,maximumLength:65_536) { [weak self] data,_,complete,error in
            guard let self, let pair = self.pairs[id] else { return }
            pair.waiting = false; pair.lastData = Date(); pair.sending = true
            if error != nil { self.close(id); return }
            pair.client.send(content:data,contentContext:complete ? .finalMessage : .defaultMessage,isComplete:complete,completion:.contentProcessed { error in
                pair.sending = false
                if error != nil || complete { self.close(id) } else { self.pipe(id) }
            })
        }
    }
}
