import Foundation

final class HandoffStub: URLProtocol {
    static var status = 200
    static var body = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        precondition(request.httpMethod == "POST")
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
        print("Handoff tests passed: ready, real expiry, service failures and invalid response")
    }
}

