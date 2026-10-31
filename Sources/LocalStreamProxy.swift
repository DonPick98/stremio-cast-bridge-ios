import Foundation
import Network

enum LocalStreamError: Error { case address, listener, request, upstream }

/// Exact-token, selected-device-only HTTP bridge. It adds the CORS headers Cast
/// needs for external subtitles and applies TCP backpressure to the local encoder.
final class LocalStreamProxy: @unchecked Sendable {
    private let queue = DispatchQueue(label:"app.castbridge.local-stream")
    let token = UUID().uuidString.replacingOccurrences(of:"-",with:"")
    private let localIP: String
    private let peer: String
    private let producerPort: UInt16
    private let contentType: String
    private var listener: NWListener?
    private var opening: CheckedContinuation<URL,Error>?
    private var pairs: [UUID:Pair] = [:]
    private var stopped = false
    private final class Pair {
        let client: NWConnection
        var producer: NWConnection?
        init(_ client: NWConnection) { self.client = client }
    }
    init(localIP:String, peer:String, producerPort:UInt16, contentType:String = "video/mp4") {
        self.localIP = localIP; self.peer = peer; self.producerPort = producerPort; self.contentType = contentType
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
    private func finish() {
        stopped = true
        listener?.cancel(); listener = nil
        let c = opening; opening = nil; c?.resume(throwing:LocalStreamError.listener)
        for pair in pairs.values { pair.client.cancel(); pair.producer?.cancel() }
        pairs.removeAll()
    }
    private func close(_ id: UUID) {
        guard let pair = pairs.removeValue(forKey:id) else { return }
        pair.client.cancel(); pair.producer?.cancel()
    }
    private func accept(_ client: NWConnection) {
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
    static func method(_ data: Data, path: String) throws -> String? {
        guard data.count <= 8192 else { throw LocalStreamError.request }
        guard let range = data.range(of:Data("\r\n\r\n".utf8)) else { return nil }
        guard range.upperBound == data.endIndex,
              let header = String(data:data[..<range.lowerBound],encoding:.utf8),
              let line = header.components(separatedBy:"\r\n").first else { throw LocalStreamError.request }
        let parts = line.split(separator:" ",omittingEmptySubsequences:false)
        guard parts.count == 3, ["GET","HEAD","OPTIONS"].contains(String(parts[0])),
              parts[1] == Substring(path), ["HTTP/1.0","HTTP/1.1"].contains(String(parts[2])) else { throw LocalStreamError.request }
        return String(parts[0])
    }
    private func request(_ id: UUID, buffer: Data) {
        guard let pair = pairs[id] else { return }
        pair.client.receive(minimumIncompleteLength:1,maximumLength:4096) { [weak self] data,_,complete,error in
            guard let self, let pair = self.pairs[id] else { return }
            var received = buffer; if let data { received.append(data) }
            do {
                if let method = try Self.method(received,path:self.path) {
                    if method == "OPTIONS" {
                        let reply = "HTTP/1.1 204 No Content\r\n\(Self.cors)Content-Length: 0\r\nConnection: close\r\n\r\n"
                        pair.client.send(content:Data(reply.utf8),completion:.contentProcessed { _ in self.close(id) })
                    } else { self.connectProducer(id,method:method) }
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
                    pair.client.send(content:header+body,isComplete:complete,completion:.contentProcessed { error in
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
        upstream.receive(minimumIncompleteLength:1,maximumLength:65_536) { [weak self] data,_,complete,error in
            guard let self, let pair = self.pairs[id] else { return }
            if error != nil { self.close(id); return }
            pair.client.send(content:data,isComplete:complete,completion:.contentProcessed { error in
                if error != nil || complete { self.close(id) } else { self.pipe(id) }
            })
        }
    }
}
