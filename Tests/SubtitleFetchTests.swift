import Foundation

private final class SubtitleFixtureProtocol:URLProtocol {
    override class func canInit(with request:URLRequest)->Bool { request.url?.host == "subtitle.example" }
    override class func canonicalRequest(for request:URLRequest)->URLRequest { request }
    override func startLoading() {
        let path=request.url!.path
        let srt="1\n00:00:01,000 --> 00:00:02,000\nFirst\n2\n00:00:03,000 --> 00:00:04,000\nSecond\n"
        let status=path == "/404" ? 404:200
        let response=HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"application/octet-stream"])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        let data:Data
        switch path {
        case "/utf16":data=srt.data(using:.utf16)!
        case "/empty":data=Data("WEBVTT\n\n".utf8)
        case "/html":data=Data("<html>Service unavailable</html>".utf8)
        case "/bad-vtt":data=Data("WEBVTT\n\n00:00:03.000 --> 00:00:02.000\nBad\n".utf8)
        case "/large":data=Data(repeating:65,count:1_048_577)
        case "/cancel":return // Keep the body open until the caller cancels.
        default:data=Data(srt.utf8)
        }
        client?.urlProtocol(self,didLoad:data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct SubtitleFetchTests {
    static func fetch(_ path:String) async throws -> String {
        let config=URLSessionConfiguration.ephemeral
        config.protocolClasses=[SubtitleFixtureProtocol.self]
        return try await WebVTTTimeline.fetch(URL(string:"https://subtitle.example/"+path)!,configuration:config)
    }
    static func main() async throws {
        for kind in ["srt","utf16"] {
            let text=try await fetch(kind)
            precondition(text.components(separatedBy:" --> ").count==3)
            precondition(text.contains("First\n\n00:00:03.000") && text.contains("Second"))
        }
        for kind in ["empty","html","bad-vtt"] {
            do {_ = try await fetch(kind);fatalError("Invalid complete document accepted")}
            catch SubtitleFetchError.format {}
        }
        do {_ = try await fetch("404");fatalError("HTTP failure accepted")}
        catch SubtitleFetchError.http(404) {}
        do {_ = try await fetch("large");fatalError("Oversized file accepted")}
        catch SubtitleFetchError.limit {}
        do {_ = try await WebVTTTimeline.fetch(URL(string:"http://subtitle.example/srt")!);fatalError("Unsafe transport accepted")}
        catch StreamHeaderError.invalid {}
        let task=Task {try await fetch("cancel")}
        try await Task.sleep(nanoseconds:50_000_000)
        task.cancel()
        do {_ = try await task.value;fatalError("Cancelled request completed")}
        catch is CancellationError {}
        catch let error as URLError {precondition(error.code == .cancelled)}
        print("Subtitle fetch passed: SRT without separators, UTF16, empty/malformed/HTML rejection, HTTP, size limit, HTTPS and cancellation")
    }
}
