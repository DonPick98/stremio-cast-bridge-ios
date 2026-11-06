import Foundation

@main struct LocalStreamProxyTests {
    static func main() async throws {
        let path = "/random-secret/stream.mp4"
        let get = try LocalStreamProxy.method(Data("GET \(path) HTTP/1.1\r\nHost: test\r\n\r\n".utf8),path:path)
        let head = try LocalStreamProxy.method(Data("HEAD \(path) HTTP/1.1\r\n\r\n".utf8),path:path)
        let partial = try LocalStreamProxy.method(Data("GET /random".utf8),path:path)
        precondition(get == "GET" && head == "HEAD" && partial == nil)
        for raw in ["GET /wrong HTTP/1.1\r\n\r\n", "POST \(path) HTTP/1.1\r\n\r\n", "GET \(path) HTTP/1.1\r\n\r\nsecond request",String(repeating:"X",count:8193)] {
            do { _ = try LocalStreamProxy.method(Data(raw.utf8),path:path); fatalError("Unexpected request accepted") } catch LocalStreamError.request {}
        }
        let media = Data([0,0,0,24,102,116,121,112])
        let upstream = Data("HTTP/1.0 200 OK\r\nContent-Type: application/octet-stream\r\nSet-Cookie: private\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)+media
        let (header,body) = try LocalStreamProxy.responseHeader(upstream)!
        let text = String(data:header,encoding:.utf8)!
        precondition(text.contains("Access-Control-Allow-Origin: *") && text.contains("Content-Type: video/mp4"))
        precondition(text.contains("Transfer-Encoding: chunked") && !text.contains("Set-Cookie"))
        precondition(body == media)
        do { _ = try LocalStreamProxy.responseHeader(Data("HTTP/1.1 302 Found\r\nLocation: https://example.test\r\n\r\n".utf8)); fatalError("Redirect accepted") } catch LocalStreamError.upstream {}
        do { _ = try LocalStreamProxy.responseHeader(Data(repeating:65,count:16385)); fatalError("Huge header accepted") } catch LocalStreamError.upstream {}
        let proxy=LocalStreamProxy(localIP:"127.0.0.1",peer:"127.0.0.1",producerPort:1)
        let stream=try await proxy.start()
        defer { proxy.stop() }
        let document=Data("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nSynthetic caption\n\n".utf8)
        precondition(proxy.installCaptionsBeforePlayback([2:document]))
        let caption=stream.deletingLastPathComponent().appendingPathComponent("subtitle-2.vtt")
        let (served,response)=try await URLSession.shared.data(from:caption)
        precondition(served==document && (response as? HTTPURLResponse)?.statusCode==200)
        precondition((response as? HTTPURLResponse)?.value(forHTTPHeaderField:"Access-Control-Allow-Origin")=="*")
        var request=URLRequest(url:stream);request.httpMethod="HEAD"
        _ = try await URLSession.shared.data(for:request)
        precondition(proxy.installCaptionsBeforePlayback([3:document]),"HEAD must not consume the producer")
        // Producer port intentionally closed: requesting media still seals the
        // manifest, even if delivery fails or the client disconnects.
        request.httpMethod="GET";request.timeoutInterval=2
        _ = try? await URLSession.shared.data(for:request)
        precondition(!proxy.installCaptionsBeforePlayback([4:document]))
        proxy.stop()
        precondition(!proxy.installCaptionsBeforePlayback([5:document]))
        print("Local stream tests passed: exact routing, CORS, prepared captions, HEAD, consumed/stopped manifest rejection")
    }
}

