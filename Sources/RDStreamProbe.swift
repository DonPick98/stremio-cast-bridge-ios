import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum RDStreamProbeError: LocalizedError {
    case http(Int), invalidManifest, notReady, unsafeURL, tooLarge, redirect, network
    var errorDescription: String? {
        switch self {
        case .http(let code): return "Il flusso compatibile Real-Debrid risponde HTTP \(code). Non è stato inviato alla TV; il video già avviato resta invariato."
        case .notReady: return "Real-Debrid non ha fornito segmenti riproducibili per questa conversione. Il video già avviato resta invariato."
        case .invalidManifest: return "Real-Debrid non ha restituito una playlist HLS valida per la conversione. Il video già avviato resta invariato."
        case .unsafeURL, .redirect: return "Il flusso compatibile rimanda a un indirizzo non previsto. Non è stato inviato alla TV."
        case .tooLarge: return "La risposta di conversione supera il limite previsto per una playlist. Non è stata inviata alla TV."
        case .network: return "Non riesco a verificare il flusso compatibile dalla connessione dell’iPhone. Il video già avviato resta invariato."
        }
    }
}

/// Checks only bounded HLS playlists on the phone, never downloads the movie.
/// A successful check does not establish receiver reachability or codec support.
enum RDStreamProbe {
    static func allowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil, let host = url.host?.lowercased() else { return false }
        return host.range(of:#"^(?:[a-z0-9-]+\.)?stream\.real-debrid\.com$"#,options:.regularExpression) != nil
    }
    enum Playlist { case master(URL), media }
    static func parse(_ data: Data, url: URL) throws -> Playlist {
        guard data.count <= 262_144, let text = String(data:data,encoding:.utf8) else { throw RDStreamProbeError.invalidManifest }
        let cleaned = text.hasPrefix("\u{feff}") ? String(text.dropFirst()) : text
        let lines = cleaned.components(separatedBy:.newlines).map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }
        guard lines.first == "#EXTM3U" else { throw RDStreamProbeError.invalidManifest }
        if let stream = lines.firstIndex(where:{$0.hasPrefix("#EXT-X-STREAM-INF:")}) {
            guard let raw = lines.dropFirst(stream+1).first(where:{!$0.isEmpty && !$0.hasPrefix("#")}),
                  let child = URL(string:raw,relativeTo:url)?.absoluteURL, allowed(child) else { throw RDStreamProbeError.unsafeURL }
            return .master(child)
        }
        guard lines.contains(where:{$0.hasPrefix("#EXTINF:")}),
              let raw = lines.first(where:{!$0.isEmpty && !$0.hasPrefix("#")}),
              let segment = URL(string:raw,relativeTo:url)?.absoluteURL else { throw RDStreamProbeError.notReady }
        guard allowed(segment) else { throw RDStreamProbeError.unsafeURL }
        return .media
    }
    static func check(_ url: URL, configuration: URLSessionConfiguration = .ephemeral) async throws {
        guard allowed(url) else { throw RDStreamProbeError.unsafeURL }
        var next = url, seen = Set<URL>()
        for _ in 0..<3 {
            try Task.checkCancellation()
            guard seen.insert(next).inserted else { throw RDStreamProbeError.invalidManifest }
            let request = PlaylistRequest(configuration:configuration)
            let (data,finalURL) = try await withTaskCancellationHandler(operation:{ try await request.read(next) },onCancel:{ request.cancel() })
            switch try parse(data,url:finalURL) {
            case .media: return
            case .master(let child): next = child
            }
        }
        throw RDStreamProbeError.invalidManifest
    }
}

/// A serial delegate bounds memory even when the server ignores the Range header.
private final class PlaylistRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let configuration: URLSessionConfiguration
    private var continuation: CheckedContinuation<(Data,URL),Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var cancelled = false
    private var body = Data()
    private var finalURL: URL?
    private var failure: Error?
    init(configuration: URLSessionConfiguration) { self.configuration = configuration }
    func read(_ url: URL) async throws -> (Data,URL) {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock(); defer { lock.unlock() }
            if cancelled { continuation.resume(throwing:CancellationError()); return }
            self.continuation = continuation
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.urlCache = nil
            configuration.timeoutIntervalForResource = 20
            let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration:configuration,delegate:self,delegateQueue:queue)
            self.session = session
            var request = URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:15)
            request.setValue("application/vnd.apple.mpegurl, application/x-mpegURL",forHTTPHeaderField:"Accept")
            request.setValue("bytes=0-262143",forHTTPHeaderField:"Range")
            let task = session.dataTask(with:request); self.task = task; task.resume()
        }
    }
    func cancel() { lock.lock(); cancelled = true; let task = task; lock.unlock(); task?.cancel() }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, RDStreamProbe.allowed(url) else { failure = RDStreamProbeError.redirect; completionHandler(nil); return }
        completionHandler(request)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, let url = http.url, RDStreamProbe.allowed(url) else { failure = RDStreamProbeError.unsafeURL; completionHandler(.cancel); return }
        guard http.statusCode == 200 || http.statusCode == 206 else { failure = RDStreamProbeError.http(http.statusCode); completionHandler(.cancel); return }
        guard response.expectedContentLength <= 262_144 else { failure = RDStreamProbeError.tooLarge; completionHandler(.cancel); return }
        finalURL = url; completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard body.count + data.count <= 262_144 else { failure = RDStreamProbeError.tooLarge; dataTask.cancel(); return }
        body.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let continuation = continuation; self.continuation = nil; let cancelled = cancelled; self.session = nil; self.task = nil; lock.unlock()
        defer { session.finishTasksAndInvalidate() }
        if cancelled { continuation?.resume(throwing:CancellationError()) }
        else if let failure { continuation?.resume(throwing:failure) }
        else if error != nil { continuation?.resume(throwing:RDStreamProbeError.network) }
        else if let finalURL { continuation?.resume(returning:(body,finalURL)) }
        else { continuation?.resume(throwing:RDStreamProbeError.invalidManifest) }
    }
}
