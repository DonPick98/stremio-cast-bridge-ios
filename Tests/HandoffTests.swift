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
        let key=String(repeating:"A",count:32)
        let torrentio="https://torrentio.strem.fun/language=english%7Crealdebrid=\(key)/manifest.json"
        let parsed=try AddonConfigStore.parse(torrentio,provider:"torrentio")
        precondition(parsed.realDebridKey==key)
        let lite=try AddonConfigStore.parse("stremio://torrentio.strem.fun/lite/realdebrid=\(key)/manifest.json",provider:"torrentio")
        precondition(lite.realDebridKey==key && lite.manifest.scheme=="https")
        func comet(_ object:[String:Any],urlSafe:Bool=false)throws->String {
            var encoded=try JSONSerialization.data(withJSONObject:object).base64EncodedString()
            if urlSafe {encoded=encoded.replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")}
            return "https://comet.elfhosted.com/"+encoded+"/manifest.json"
        }
        let legacy:[String:Any]=["debridService":"realdebrid","debridApiKey":key]
        let modern:[String:Any]=["debridServices":[["service":"torbox","apiKey":"other-service"],["service":"realdebrid","apiKey":key]]]
        var empty=legacy;empty["debridServices"]=[]
        for object in [legacy,modern,empty] {
            for safe in [false,true] {
                let result=try AddonConfigStore.parse(comet(object,urlSafe:safe),provider:"comet")
                precondition(result.realDebridKey==key)
            }
        }
        var overrides=legacy;overrides["debridServices"]=[["service":"torbox","apiKey":"other-service"]]
        var malformed=legacy;malformed["debridServices"]="invalid"
        for input in [try comet(overrides),try comet(malformed),try comet([:]),try comet(["debridService":"realdebrid","debridApiKey":"short"]),"https://comet.elfhosted.com/manifest.json"] {
            do {_ = try AddonConfigStore.parse(input,provider:"comet");fatalError("Unconfigured or overridden RD accepted")}
            catch AddonConfigError.missingRealDebrid {}
        }
        do {_ = try AddonConfigStore.parse(torrentio.replacingOccurrences(of:"torrentio.strem.fun",with:"untrusted.example"),provider:"torrentio");fatalError("Unknown host accepted")}
        catch AddonConfigError.invalidManifest {}
        print("Addon configuration tests passed: Torrentio/lite, Comet legacy/modern, precedence, URL-safe base64 and rejection")
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



