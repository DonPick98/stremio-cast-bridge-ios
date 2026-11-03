import Foundation

final class HandoffStub: URLProtocol {
    static var status = 200
    static var method="POST"
    static var requests=0
    static var body = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        precondition(request.httpMethod == Self.method)
        Self.requests += 1
        if Self.method=="GET" {precondition(request.url?.host=="v3-cinemeta.strem.io" && request.url?.path=="/meta/series/tt1234567.json")}
        precondition(request.value(forHTTPHeaderField:"Authorization") == nil)
        let response = HTTPURLResponse(url:request.url!,statusCode:Self.status,httpVersion:nil,headerFields:nil)!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct HandoffTests {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HandoffStub.self]
        let client = BridgeClient(session:URLSession(configuration:config))
        HandoffStub.body = Data(#"{"version":1,"status":"ready","provider":"torrentio","type":"series","id":"tt1234567:1:1","selection":null,"subtitleLanguage":"eng"}"#.utf8)
        let ready = try await client.handoff(ticket:"test-only-ticket")
        precondition(ready.status == "ready")
        for status in [400,403,404,429,503] {
            HandoffStub.status = status
            do { _ = try await client.handoff(ticket:"test-only-ticket"); fatalError("Service error ignored") }
            catch BridgeError.handoffHTTP(let actual) { precondition(actual == status) }
        }
        HandoffStub.status = 410
        do { _ = try await client.handoff(ticket:"test-only-ticket"); fatalError("Expired accepted") } catch BridgeError.expired {}
        HandoffStub.status = 200; HandoffStub.body = Data("<html>Service unavailable</html>".utf8)
        do { _ = try await client.handoff(ticket:"test-only-ticket"); fatalError("HTML accepted") } catch BridgeError.invalidHandoffResponse {}
        HandoffStub.method="GET"
        HandoffStub.body=Data(#"{"meta":{"id":"tt1234567","videos":[{"id":"tt1234567:1:1","title":"Pilot","season":1,"episode":1}]}}"#.utf8)
        let videos=try await client.episodes(videoID:"tt1234567:1:1")
        precondition(videos.count==1 && videos[0].episode==1)
        let before=HandoffStub.requests
        do {_ = try await client.episodes(videoID:"https://private.example/key");fatalError("Unsafe ID accepted")} catch BridgeError.invalidLink {}
        precondition(HandoffStub.requests==before)
        HandoffStub.body=Data(#"{"meta":{"id":"tt999","videos":[]}}"#.utf8)
        do {_ = try await client.episodes(videoID:"tt1234567:1:1");fatalError("Wrong series accepted")} catch BridgeError.invalidHandoffResponse {}
        HandoffStub.status=503
        do {_ = try await client.episodes(videoID:"tt1234567:1:1");fatalError("Failed catalogue accepted")} catch BridgeError.network {}
        HandoffStub.status=200;HandoffStub.body=Data(repeating:32,count:2_000_001)
        do {_ = try await client.episodes(videoID:"tt1234567:1:1");fatalError("Oversize catalogue accepted")} catch BridgeError.network {}
        print("Handoff tests passed: ready, real expiry, service failures and invalid response")
    }
}


