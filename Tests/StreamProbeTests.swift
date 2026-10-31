import Foundation

final class PlaylistStub: URLProtocol {
    static var handler: ((URLRequest) -> (Int,Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status,data) = Self.handler(request)
        let response = HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct StreamProbeTests {
    static func main() async throws {
        let root = URL(string:"https://stream.real-debrid.com/t/fixture/eng1/none/aac/high.m3u8")!
        let media = Data("#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\nsegment.ts\n#EXT-X-ENDLIST\n".utf8)
        precondition(RDStreamProbe.allowed(root))
        for raw in ["http://stream.real-debrid.com/a", "https://stream.real-debrid.com.evil.test/a", "https://user:pass@stream.real-debrid.com/a", "https://127.0.0.1/a", "https://stream.real-debrid.com:443/a"] {
            precondition(!RDStreamProbe.allowed(URL(string:raw)!))
        }
        guard case .media = try RDStreamProbe.parse(media,url:root) else { fatalError("Media rejected") }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [PlaylistStub.self]
        var paths: [String] = []
        PlaylistStub.handler = { request in
            precondition(request.value(forHTTPHeaderField:"Authorization") == nil)
            precondition(request.value(forHTTPHeaderField:"Range") == "bytes=0-262143")
            paths.append(request.url!.lastPathComponent)
            return request.url!.lastPathComponent == "high.m3u8" ? (200,Data("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=2000000\nchild.m3u8\n".utf8)) : (200,media)
        }
        try await RDStreamProbe.check(root,configuration:config)
        precondition(paths == ["high.m3u8","child.m3u8"])
        PlaylistStub.handler = { _ in (403,Data("private body must not be displayed".utf8)) }
        do { try await RDStreamProbe.check(root,configuration:config); fatalError("HTTP error accepted") }
        catch RDStreamProbeError.http(let code) { precondition(code == 403) }
        for data in [Data("<html>not a playlist</html>".utf8),Data("{\"error\":\"private token\"}".utf8)] {
            PlaylistStub.handler = { _ in (200,data) }
            do { try await RDStreamProbe.check(root,configuration:config); fatalError("Invalid manifest accepted") }
            catch RDStreamProbeError.invalidManifest {}
        }
        PlaylistStub.handler = { _ in (200,Data("#EXTM3U\n#EXT-X-TARGETDURATION:6\n".utf8)) }
        do { try await RDStreamProbe.check(root,configuration:config); fatalError("Empty conversion accepted") }
        catch RDStreamProbeError.notReady {}
        PlaylistStub.handler = { _ in (200,Data(repeating:65,count:262_145)) }
        do { try await RDStreamProbe.check(root,configuration:config); fatalError("Oversized response accepted") }
        catch RDStreamProbeError.tooLarge {}
        PlaylistStub.handler = { _ in (200,Data("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nhigh.m3u8\n".utf8)) }
        do { try await RDStreamProbe.check(root,configuration:config); fatalError("Playlist cycle accepted") }
        catch RDStreamProbeError.invalidManifest {}
        do { _ = try RDStreamProbe.parse(Data("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nhttps://evil.test/a.m3u8\n".utf8),url:root); fatalError("Foreign variant accepted") }
        catch RDStreamProbeError.unsafeURL {}
        let cancelled = Task { try await RDStreamProbe.check(root,configuration:config) }
        cancelled.cancel()
        do { try await cancelled.value; fatalError("Cancellation ignored") } catch is CancellationError {}
        print("Stream probe tests passed: master/media HLS, HTTP failures, invalid/empty body, bounds, host scope, cycle and cancellation")
    }
}
