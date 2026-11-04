import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum StreamHeaderError: Error { case invalid, unsupported, network, tooLarge }

/// Reads only the initialization header. A video-only conversion must never be
/// treated as a successful audio repair, even when the encoder reports PLAYING.
enum PlayableStreamHeader {
    private struct Box { let type: String; let payload: Data }
    private static func number(_ data: Data, _ offset: Int, _ count: Int) -> UInt64 {
        data[offset..<(offset+count)].reduce(0) { ($0 << 8) | UInt64($1) }
    }
    private static func boxes(_ data: Data) throws -> [Box] {
        var result: [Box] = [], p = 0
        while p < data.count {
            guard data.count-p >= 8 else { throw StreamHeaderError.invalid }
            var size = number(data,p,4), header = 8
            let type = String(data:data[(p+4)..<(p+8)],encoding:.ascii) ?? ""
            if size == 1 { guard data.count-p >= 16 else { throw StreamHeaderError.invalid }; size = number(data,p+8,8); header = 16 }
            guard size >= header, size <= data.count-p else { throw StreamHeaderError.invalid }
            result.append(Box(type:type,payload:Data(data[(p+header)..<(p+Int(size))])))
            p += Int(size)
        }
        return result
    }
    private static func child(_ box: Box, _ path: [String]) throws -> Box? {
        var current = box
        for type in path { guard let next = try boxes(current.payload).first(where:{$0.type == type}) else { return nil }; current = next }
        return current
    }
    static func check(_ data: Data, contentType: String) throws -> Bool {
        guard data.count <= 1_048_576 else { throw StreamHeaderError.tooLarge }
        return try contentType == "video/webm" ? webm(data) : mp4(data)
    }
    private static func mp4(_ data: Data) throws -> Bool {
        var p = 0
        while data.count-p >= 8 {
            var size = number(data,p,4), header = 8
            let type = String(data:data[(p+4)..<(p+8)],encoding:.ascii) ?? ""
            if size == 1 { guard data.count-p >= 16 else { return false }; size = number(data,p+8,8); header = 16 }
            guard size >= header, size <= 1_048_576 else { throw StreamHeaderError.invalid }
            guard size <= data.count-p else { return false }
            if type == "moov" {
                let moov = Box(type:type,payload:Data(data[(p+header)..<(p+Int(size))]))
                var audio = false, video = false
                for track in try boxes(moov.payload).filter({$0.type == "trak"}) {
                    guard let handler = try child(track,["mdia","hdlr"]), handler.payload.count >= 12,
                          let descriptions = try child(track,["mdia","minf","stbl","stsd"]), descriptions.payload.count >= 8 else { continue }
                    let kind = String(data:handler.payload[8..<12],encoding:.ascii)
                    guard let entry = try boxes(Data(descriptions.payload.dropFirst(8))).first else { continue }
                    if kind == "soun" {
                        guard ["mp4a",".mp3","mp3 "].contains(entry.type), entry.payload.count >= 20 else { throw StreamHeaderError.unsupported }
                        let channels = number(entry.payload,16,2)
                        guard channels > 0 && channels <= 2 else { throw StreamHeaderError.unsupported }
                        audio = true
                    } else if kind == "vide" {
                        guard ["avc1","avc3"].contains(entry.type), entry.payload.count >= 78,
                              let avc = try boxes(Data(entry.payload.dropFirst(78))).first(where:{$0.type == "avcC"}), avc.payload.count >= 4 else { throw StreamHeaderError.unsupported }
                        guard [66,77,88,100].contains(Int(avc.payload[1])), avc.payload[3] <= 42 else { throw StreamHeaderError.unsupported }
                        video = true
                    }
                }
                guard audio && video else { throw StreamHeaderError.unsupported }
                return true
            }
            if type == "mdat" || type == "moof" { throw StreamHeaderError.invalid }
            p += Int(size)
        }
        return false
    }
    private static func vint(_ data: Data, _ p: Int, id: Bool) throws -> (UInt64,Int)? {
        guard p < data.count else { return nil }
        let first = data[p]
        guard first != 0 else { throw StreamHeaderError.invalid }
        var length = 1, mask: UInt8 = 0x80
        while first & mask == 0 { mask >>= 1; length += 1 }
        guard length <= (id ? 4 : 8) else { throw StreamHeaderError.invalid }
        guard data.count-p >= length else { return nil }
        var value = UInt64(id ? first : first & ~mask)
        if length > 1 { for i in 1..<length { value = (value << 8) | UInt64(data[p+i]) } }
        return (value,length)
    }
    private static func elements(_ data: Data) throws -> [(UInt64,Data)] {
        var result: [(UInt64,Data)] = [], p = 0
        while p < data.count {
            guard let (id,n) = try vint(data,p,id:true), let (size,m) = try vint(data,p+n,id:false),
                  size <= data.count-p-n-m else { throw StreamHeaderError.invalid }
            let start = p+n+m; result.append((id,Data(data[start..<(start+Int(size))]))); p = start+Int(size)
        }
        return result
    }
    private static func webm(_ data: Data) throws -> Bool {
        var p = 0
        while p < data.count {
            guard let (id,n) = try vint(data,p,id:true), let (size,m) = try vint(data,p+n,id:false) else { return false }
            let start = p+n+m
            if id == 0x18538067 { p = start; continue }
            guard size <= 1_048_576 else { throw StreamHeaderError.tooLarge }
            guard size <= data.count-start else { return false }
            if id == 0x1654AE6B {
                var audio = false, video = false
                for (_,entry) in try elements(Data(data[start..<(start+Int(size))])).filter({$0.0 == 0xAE}) {
                    let fields = try elements(entry)
                    let typeData = fields.first(where:{$0.0 == 0x83})?.1 ?? Data()
                    let type = typeData.reduce(UInt64(0)){($0<<8)|UInt64($1)}
                    let codec = fields.first(where:{$0.0 == 0x86}).flatMap{String(data:$0.1,encoding:.utf8)} ?? ""
                    if type == 1 { guard codec == "V_VP8" else { throw StreamHeaderError.unsupported }; video = true }
                    if type == 2 {
                        guard ["A_VORBIS","A_OPUS"].contains(codec) else { throw StreamHeaderError.unsupported }
                        let details = try fields.first(where:{$0.0 == 0xE1}).map{try elements($0.1)} ?? []
                        let channels = details.first(where:{$0.0 == 0x9F}).map { $0.1.reduce(UInt64(0)){($0<<8)|UInt64($1)} } ?? 1
                        guard channels > 0 && channels <= 2 else { throw StreamHeaderError.unsupported }; audio = true
                    }
                }
                guard audio && video else { throw StreamHeaderError.unsupported }; return true
            }
            p = start+Int(size)
        }
        return false
    }
    static func validateProducer(_ url: URL, contentType:String) async throws {
        guard url.scheme == "http", url.host == "127.0.0.1", url.user == nil, url.password == nil else { throw StreamHeaderError.invalid }
        let probe = ProducerHeaderRequest(contentType:contentType)
        try await withTaskCancellationHandler(operation:{try await probe.read(url)},onCancel:{probe.cancel()})
    }
}

private final class ProducerHeaderRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let contentType: String
    private var continuation: CheckedContinuation<Void,Error>?
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var cancelled = false
    private var body = Data()
    private var failure: Error?
    init(contentType:String) { self.contentType = contentType }
    func read(_ url:URL) async throws {
        try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
            lock.lock(); defer { lock.unlock() }
            if cancelled { continuation.resume(throwing:CancellationError()); return }
            self.continuation = continuation
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 15
            config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
            let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration:config,delegate:self,delegateQueue:queue); self.session = session
            let task = session.dataTask(with:url); self.task = task; task.resume()
        }
    }
    func cancel() { lock.lock(); cancelled = true; let t = task; lock.unlock(); t?.cancel() }
    func urlSession(_ session:URLSession, task:URLSessionTask, willPerformHTTPRedirection response:HTTPURLResponse, newRequest request:URLRequest, completionHandler:@escaping (URLRequest?)->Void) { failure = StreamHeaderError.invalid; completionHandler(nil) }
    func urlSession(_ session:URLSession, dataTask:URLSessionDataTask, didReceive response:URLResponse, completionHandler:@escaping (URLSession.ResponseDisposition)->Void) {
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { failure = StreamHeaderError.network; completionHandler(.cancel); return }
        completionHandler(.allow)
    }
    func urlSession(_ session:URLSession, dataTask:URLSessionDataTask, didReceive data:Data) {
        guard body.count+data.count <= 1_048_576 else { failure = StreamHeaderError.tooLarge; dataTask.cancel(); return }
        body.append(data)
        do {
            if try PlayableStreamHeader.check(body,contentType:contentType) {
                lock.lock(); let c = continuation; continuation = nil; lock.unlock()
                c?.resume(); dataTask.cancel()
            }
        } catch { failure = error; dataTask.cancel() }
    }
    func urlSession(_ session:URLSession, task:URLSessionTask, didCompleteWithError error:Error?) {
        lock.lock(); let c = continuation; continuation = nil; let cancelled = cancelled; self.task = nil; self.session = nil; lock.unlock()
        c?.resume(throwing:cancelled ? CancellationError() : failure ?? StreamHeaderError.network)
        session.finishTasksAndInvalidate()
    }
}
