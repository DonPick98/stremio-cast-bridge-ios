import Foundation

final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String: Any]))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, object) = try Self.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: object))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

actor ProgressLog {
    var states: [String] = []
    func append(_ state: String) { states.append(state) }
}
@main struct ResolverTests {
    static func main() async throws {
        precondition(CastContentIdentity.matches(expected:"https://example.test/movie",contentURL:"https://example.test/movie",contentID:"receiver-generated-id"))
        precondition(CastContentIdentity.matches(expected:"https://example.test/movie",contentURL:nil,contentID:"https://example.test/movie"))
        precondition(!CastContentIdentity.matches(expected:"https://example.test/movie",contentURL:"https://example.test/other",contentID:"unrelated"))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let resolver = RDNativeResolver(apiKey: String(repeating: "a", count: 30), session: URLSession(configuration: config))
        let subtitleCodec = "ass"
        var unavailable = false
        var responseHost = "1.download.real-debrid.com"
        var audioDetails = ["jpn1":["lang_iso":"jpn","codec":"aac"]]
        StubProtocol.handler = { request in
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer " + String(repeating: "a", count: 30))
            switch request.url!.lastPathComponent {
            case "link":
                return (200, ["id": "test", "download": "https://\(responseHost)/file/test.mkv", "filename": "test.mkv"])
            case "test":
                if request.url!.path.contains("mediaInfos") {
                    return (200, ["details": ["video": ["codec": "h264", "width": 1920, "height": 1080, "fps": "24000/1001"], "audio": audioDetails, "subtitles": ["eng1": ["lang_iso": "eng", "codec": subtitleCodec]]]])
                }
                if unavailable { return (503, [:]) }
                return (200, ["apple": ["high": "https://stream.real-debrid.com/t/test/jpn1/none/aac/high.m3u8", "medium": "https://stream.real-debrid.com/t/test/jpn1/none/aac/medium.m3u8"]])
            default: fatalError("Unexpected API request")
            }
        }
        let link = URL(string: "https://real-debrid.com/d/test")!
        let media = try await resolver.prepare(directLink: link)
        precondition(media.directCompatible)
        precondition(media.directAudioNotice == nil && media.audioCodecsDescription == "AAC")
        precondition(media.directContentType == "video/x-matroska")
        precondition(media.videoDescription.contains("1920×1080"))
        precondition(media.availableQualities.contains(.high))
        let converted = try media.streamURL(audio: "jpn1", subtitle: "eng1", quality: .high)
        precondition(converted.path == "/t/test/jpn1/eng1/aac/high.m3u8")
        do { _ = try media.streamURL(audio: "eng99"); fatalError("Invalid audio accepted") } catch RDResolverError.invalidTrack {}
        do { _ = try media.streamURL(audio: "jpn1", quality: .original); fatalError("Missing quality silently downgraded") } catch RDResolverError.invalidStream {}
        unavailable = true
        let directOnly = try await resolver.prepare(directLink: link)
        precondition(directOnly.availableQualities.isEmpty && directOnly.directCompatible)
        audioDetails = ["jpn1":["lang_iso":"jpn","codec":"ac3"]]
        let dolby = try await resolver.prepare(directLink:link)
        precondition(!dolby.directCompatible && dolby.audioCodecsDescription == "AC3" && dolby.directAudioNotice?.contains("Dolby") == true)
        audioDetails = ["jpn1":["lang_iso":"jpn","codec":"aac"],"eng1":["lang_iso":"eng","codec":"aac"]]
        let multiple = try await resolver.prepare(directLink:link)
        precondition(!multiple.directCompatible && multiple.directAudioNotice?.contains("sceglie l’audio del file") == true)
        audioDetails = ["jpn1":["lang_iso":"jpn","codec":"aac"]]
        responseHost = "example.com"
        do { _ = try await resolver.prepare(directLink: link); fatalError("Untrusted download accepted") } catch RDResolverError.invalidStream {}
        do { _ = try await resolver.prepare(directLink: URL(string: "https://example.com/file.mkv")!); fatalError("Untrusted input accepted") } catch RDResolverError.invalidStream {}
        unavailable = false; responseHost = "1.download.real-debrid.com"
        let normal = StubProtocol.handler!
        var additions = 0, infoCalls = 0, alwaysPending = false
        StubProtocol.handler = { request in
            let path = request.url!.path
            if path.contains("torrents/addMagnet") { additions += 1; return (201,["id":"fixture-torrent"]) }
            if path.contains("torrents/selectFiles") { return (204,[:]) }
            if path.contains("torrents/info") {
                infoCalls += 1
                if !alwaysPending && infoCalls == 1 { return (200,["status":"magnet_conversion","files":[],"progress":0]) }
                let status = alwaysPending ? "downloading" : infoCalls == 2 ? "waiting_files_selection" : infoCalls == 3 ? "downloading" : "downloaded"
                return (200,["status":status,"progress":alwaysPending ? 42 : status == "downloaded" ? 100 : 25,
                             "files":[["id":1,"path":"/test.mkv","bytes":100,"selected":status == "waiting_files_selection" ? 0 : 1]],"links":["https://real-debrid.com/d/test"]])
            }
            return try normal(request)
        }
        let progress = ProgressLog()
        let preparing = RDNativeResolver(apiKey:String(repeating:"a",count:30),session:URLSession(configuration:config),pollDelay:0,maxPreparationChecks:8)
        let ready = try await preparing.prepare(torrentHash:String(repeating:"b",count:40),filename:"test.mkv",onProgress:{state,_ in await progress.append(state)})
        precondition(ready.directCompatible && additions == 1 && infoCalls == 4)
        let states = await progress.states
        precondition(states == ["magnet_conversion","waiting_files_selection","downloading","downloaded","reading_metadata"])
        alwaysPending = true; additions = 0
        let pending = RDNativeResolver(apiKey:String(repeating:"a",count:30),session:URLSession(configuration:config),pollDelay:0,maxPreparationChecks:2)
        for _ in 0..<2 {
            do { _ = try await pending.prepare(torrentHash:String(repeating:"c",count:40),filename:"test.mkv"); fatalError("Pending source marked ready") }
            catch RDResolverError.fileNotReady(let state, let percent) { precondition(state == "downloading" && percent == 42) }
        }
        precondition(additions == 1,"Pending torrent was added more than once")
        for (status,code) in [(451,35),(451,36),(403,8)] {
            StubProtocol.handler = { _ in (status,["error_code":code,"error":"not displayed verbatim"]) }
            do { _ = try await resolver.prepare(directLink:link); fatalError("RD failure swallowed") }
            catch RDResolverError.apiFailure(let actualStatus,let actualCode,let stage) { precondition(actualStatus == status && actualCode == code && stage == "collegamento video") }
        }
        var rateRequests = 0
        StubProtocol.handler = { _ in rateRequests += 1; return (429,["error_code":34]) }
        for _ in 0..<2 {
            do { _ = try await resolver.prepare(directLink:link); fatalError("Rate limit ignored") }
            catch RDResolverError.rateLimited(let wait) { precondition(wait > 0) }
        }
        precondition(rateRequests == 1,"Cooldown sent another network request")
        print("Resolver tests passed: direct playback, automatic readiness, progress, pending reuse, RD codes and rate-limit cooldown")
    }
}
