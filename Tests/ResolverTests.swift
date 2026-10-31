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

@main struct ResolverTests {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let resolver = RDNativeResolver(apiKey: String(repeating: "a", count: 30), session: URLSession(configuration: config))
        let subtitleCodec = "ass"
        var unavailable = false
        var responseHost = "1.download.real-debrid.com"
        StubProtocol.handler = { request in
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer " + String(repeating: "a", count: 30))
            switch request.url!.lastPathComponent {
            case "link":
                return (200, ["id": "test", "download": "https://\(responseHost)/file/test.mkv", "filename": "test.mkv"])
            case "test":
                if request.url!.path.contains("mediaInfos") {
                    return (200, ["details": ["video": ["codec": "h264", "width": 1920, "height": 1080, "fps": "24000/1001"], "audio": ["jpn1": ["lang_iso": "jpn", "codec": "aac"]], "subtitles": ["eng1": ["lang_iso": "eng", "codec": subtitleCodec]]]])
                }
                if unavailable { return (503, [:]) }
                return (200, ["apple": ["high": "https://stream.real-debrid.com/t/test/jpn1/none/aac/high.m3u8", "medium": "https://stream.real-debrid.com/t/test/jpn1/none/aac/medium.m3u8"]])
            default: fatalError("Unexpected API request")
            }
        }
        let link = URL(string: "https://real-debrid.com/d/test")!
        let media = try await resolver.prepare(directLink: link)
        precondition(media.directCompatible)
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
        responseHost = "example.com"
        do { _ = try await resolver.prepare(directLink: link); fatalError("Untrusted download accepted") } catch RDResolverError.invalidStream {}
        do { _ = try await resolver.prepare(directLink: URL(string: "https://example.com/file.mkv")!); fatalError("Untrusted input accepted") } catch RDResolverError.invalidStream {}
        print("Resolver tests passed: direct 1080p, tracks, exact quality, conversion outage and URL validation")
    }
}
