import Foundation
import MobileVLCKit

/// Exercises the actual iOS binary on synthetic fixtures in CI, without accounts or Cast devices.
@MainActor enum NativeEngineValidation {
    static func run() async {
        let documents = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        let report = documents.appendingPathComponent("engine-validation.json")
        let input = documents.appendingPathComponent("h264-ac3.mkv")
        let output = documents.appendingPathComponent("converted.mp4")
        var result: [String:Any] = ["passed":false]
        do {
            let source = VLCMedia(url:input)
            source.addOption(":sout=#transcode{acodec=mp4a,ab=192,channels=2}:std{access=file,mux=avformat{mux=mp4,options={movflags=frag_keyframe+empty_moov+default_base_moof}},dst=\(output.path)}")
            source.addOption(":no-sout-all")
            let player = VLCMediaPlayer(options:["--quiet","--no-video-title-show"])
            player.media = source
            player.play()
            for i in 0..<200 {
                try await Task.sleep(nanoseconds:100_000_000)
                if player.state == .error { throw NSError(domain:"NativeEngine",code:1,userInfo:[NSLocalizedDescriptionKey:"Conversion failed"]) }
                if i > 5 && (player.state == .ended || player.state == .stopped) { break }
            }
            player.stop()
            let media = VLCMedia(url:output)
            media.parse(options:VLCMediaParsingOptions(rawValue:0))
            for _ in 0..<100 {
                if media.parsedStatus == .done { break }
                try await Task.sleep(nanoseconds:100_000_000)
            }
            let tracks = (media.tracksInformation as? [[String:Any]] ?? []).map { track -> [String:Any] in
                let code = (track[VLCMediaTracksInformationCodec] as? NSNumber)?.uint32Value ?? 0
                let codec = String(bytes:(0..<4).map { UInt8((code >> ($0*8)) & 255) },encoding:.ascii) ?? ""
                return ["type":track[VLCMediaTracksInformationType] as? String ?? "", "codec":codec,
                        "channels":(track[VLCMediaTracksInformationAudioChannelsNumber] as? NSNumber)?.intValue ?? 0]
            }
            result["tracks"] = tracks
            result["bytes"] = (try FileManager.default.attributesOfItem(atPath:output.path)[.size] as? NSNumber)?.intValue ?? 0
            result["passed"] = tracks.contains { ($0["codec"] as? String) == "h264" } && tracks.contains { ($0["codec"] as? String) == "mp4a" && ($0["channels"] as? Int) == 2 }
            let inspected = try await EmbeddedMediaEngine.inspect(input)
            result["inputAudio"] = inspected.audioCodecsDescription
            result["inputVideoConversion"] = inspected.requiresVideoConversion
            var gatewayResults: [[String:Any]] = []
            for mode in [EmbeddedMediaEngine.VideoMode.copy,.hardwareH264,.softwareVP8] {
                let engine = EmbeddedMediaEngine()
                do {
                    let url = try await engine.start(input:input,deviceIP:"127.0.0.1",start:0,videoMode:mode,audioID:nil,subtitleID:nil,style:SubtitleAppearance(),selfTest:true)
                    let capture = NativeStreamCapture()
                    let (body,cors) = try await capture.read(url)
                    let suffix = mode == .softwareVP8 ? "webm" : "mp4"
                    let file = documents.appendingPathComponent("gateway-\(gatewayResults.count).\(suffix)")
                    try body.write(to:file)
                    let checked = try await EmbeddedMediaEngine.inspect(file)
                    gatewayResults.append(["mode":String(describing:mode),"bytes":body.count,"cors":cors,"description":checked.videoDescription,"audio":checked.audioCodecsDescription,"passed":cors && !checked.audio.isEmpty])
                } catch {
                    gatewayResults.append(["mode":String(describing:mode),"passed":false,"error":error.localizedDescription])
                }
                engine.stop()
            }
            result["gateway"] = gatewayResults
            result["passed"] = (result["passed"] as? Bool == true) && (gatewayResults[0]["passed"] as? Bool == true) && (gatewayResults[2]["passed"] as? Bool == true)
            let matrix = await NativeCodecMatrixValidation.run(documents:documents)
            if !matrix.isEmpty {
                result["matrix"] = matrix
                result["passed"] = (result["passed"] as? Bool == true) && matrix.count == 25 && matrix.allSatisfy { $0["passed"] as? Bool == true }
            }
        } catch { result["error"] = "Native codec probe failed: \(error.localizedDescription)" }
        if let data = try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:report,options:.atomic) }
    }
}

private final class NativeStreamCapture: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<(Data,Bool),Error>?
    private var body = Data()
    private var cors = false
    private var session: URLSession?
    func read(_ url: URL) async throws -> (Data,Bool) {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForResource = 8; config.timeoutIntervalForRequest = 8
            let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration:config,delegate:self,delegateQueue:queue)
            self.session = session
            session.dataTask(with:url).resume()
        }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let http = response as? HTTPURLResponse
        cors = http?.statusCode == 200 && http?.value(forHTTPHeaderField:"Access-Control-Allow-Origin") == "*"
        completionHandler(cors ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        body.append(data.prefix(max(0,262_144-body.count)))
        if body.count >= 262_144 { dataTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let c = continuation; continuation = nil
        if body.count > 4096 { c?.resume(returning:(body,cors)) }
        else { c?.resume(throwing:EmbeddedMediaError.encoder) }
        session.finishTasksAndInvalidate(); self.session = nil
    }
}
