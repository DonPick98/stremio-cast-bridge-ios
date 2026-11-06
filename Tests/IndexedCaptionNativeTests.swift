import Foundation
private final class RangeFixture:URLProtocol {
    static var bytes=Data()
    override class func canInit(with request:URLRequest)->Bool{request.url?.host=="range.example"}
    override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
    override func startLoading(){
        if request.url?.path=="/hold"{return}
        let range=request.value(forHTTPHeaderField:"Range")!.dropFirst(6).split(separator:"-").compactMap{Int($0)}
        let start=range[0],end=min(range[1],Self.bytes.count-1)
        let bad=request.url?.path=="/bad",ignored=request.url?.path=="/ignore"
        let headers=["Content-Range":"bytes \(bad ? start+1:start)-\(end)/\(Self.bytes.count)","ETag":request.url?.path=="/changed" && start>0 ? "changed":"fixture","Content-Length":String(end-start+1)]
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:ignored ? 200:206,httpVersion:"HTTP/1.1",headerFields:headers)!,cacheStoragePolicy:.notAllowed)
        var body=Self.bytes.subdata(in:start..<(end+1))
        if request.url?.path=="/oversize"{body.append(0)}
        if request.url?.path=="/truncated"{body.removeLast()}
        client?.urlProtocol(self,didLoad:body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading(){}
}
@main struct IndexedCaptionNativeTests {
    @MainActor static func main() async throws {
        let file=URL(fileURLWithPath:CommandLine.arguments[1])
        let script=URL(fileURLWithPath:CommandLine.arguments[2])
        let start=Date()
        let output=try await IndexedCaptionExtraction.extract(input:file,ordinal:0,language:"eng",script:script)
        precondition(output.frames==2 && output.text.contains("EARLY CAPTION") && output.text.contains("LATE CAPTION"))
        precondition(output.bytes<1_048_576)
        let localSeconds=Date().timeIntervalSince(start)
        RangeFixture.bytes=try Data(contentsOf:file)
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[RangeFixture.self]
        let remoteStart=Date()
        let remote=try await IndexedCaptionExtraction.extract(input:URL(string:"https://range.example/ok")!,ordinal:0,language:"eng",script:script,configuration:config)
        print("Indexed JSC timing: local=\(localSeconds) remote=\(Date().timeIntervalSince(remoteStart))")
        precondition(remote.text==output.text && remote.bytes<1_048_576)
        for path in ["bad","ignore","changed","oversize","truncated"] {
            do{_=try await IndexedCaptionExtraction.extract(input:URL(string:"https://range.example/"+path)!,ordinal:0,language:"eng",script:script,configuration:config);preconditionFailure("Invalid range accepted")}
            catch is IndexedCaptionExtraction.Failure{}
        }
        let held=Task{try await IndexedCaptionExtraction.extract(input:URL(string:"https://range.example/hold")!,ordinal:0,language:"eng",script:script,configuration:config)}
        try await Task.sleep(nanoseconds:50_000_000);held.cancel()
        do{_=try await held.value;preconditionFailure("In-flight cancellation ignored")}catch is CancellationError{}
        let cancelled=Task {try await IndexedCaptionExtraction.extract(input:file,ordinal:0,language:"eng",script:script)}
        cancelled.cancel()
        do{_=try await cancelled.value;preconditionFailure("Cancellation ignored")}catch is CancellationError{}
        print("Indexed JSC native passed: frames=\(output.frames) bytes=\(output.bytes) seconds=\(Date().timeIntervalSince(start))")
    }
}
