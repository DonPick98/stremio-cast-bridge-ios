#if CAST_ENGINE_TESTING
import Foundation
import MobileVLCKit
import UIKit
import MediaPlayer

/// Exercises the actual iOS binary on synthetic fixtures in CI, without accounts or Cast devices.
@MainActor enum NativeEngineValidation {
    static func trace(_ text:String) { FileHandle.standardOutput.write(Data("Engine validation: \(text)\n".utf8)) }
    static func log(_ player:VLCMediaPlayer,to url:URL) {
        FileManager.default.createFile(atPath:url.path,contents:nil)
        guard let handle = try? FileHandle(forWritingTo:url) else { return }
        let logger = VLCFileLogger(fileHandle:handle); logger.level = .debug
        player.libraryInstance.loggers = [logger]
    }
    static func run() async {
        let documents = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        let report = documents.appendingPathComponent("engine-validation.json")
        let input = documents.appendingPathComponent("h264-ac3.mkv")
        let output = documents.appendingPathComponent("converted.mp4")
        var result: [String:Any] = ["passed":false]
        let controls = LockScreenPlayback()
        controls.update(title:"Playback validation",device:"Synthetic receiver",position:42,duration:240,playing:true,loading:false,local:true)
        let metadata = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        let mediaControls = (metadata[MPMediaItemPropertyPlaybackDuration] as? Double) == 240 && (metadata[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double) == 42 && MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled
        result["systemMediaControls"] = mediaControls
        controls.clear()
        do {
            trace("decoder")
            let repair = AudioRepairPipe()
            let repairedFile = documents.appendingPathComponent("repair-direct.mkv")
            repair.testingOutput = repairedFile
            do {
                _ = try await repair.start(input:documents.appendingPathComponent("CodecSamples/truehd.mkv"),position:0,audioIndex:0,subtitleIndex:nil)
                for _ in 0..<300 { if repair.finished { break }; try await Task.sleep(nanoseconds:100_000_000) }
                let checked = try await EmbeddedMediaEngine.inspect(repairedFile)
                result["decoder"] = ["passed":!repair.failed && repair.finished,"audio":checked.audioCodecsDescription,"video":checked.videoDescription]
            } catch { result["decoder"] = ["passed":false,"error":error.localizedDescription] }
            repair.stop()
            trace("core conversion")
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
            result["passed"] = mediaControls && tracks.contains { ($0["codec"] as? String) == "h264" } && tracks.contains { ($0["codec"] as? String) == "mp4a" && ($0["channels"] as? Int) == 2 }
            let inspected = try await EmbeddedMediaEngine.inspect(input)
            result["inputAudio"] = inspected.audioCodecsDescription
            result["inputVideoConversion"] = inspected.requiresVideoConversion
            var gatewayResults: [[String:Any]] = []
            let scenarios: [(EmbeddedMediaEngine.VideoMode,Bool,Bool)] = [(.copy,false,false),(.hardwareH264,false,false),(.softwareVP8,false,false),(.copy,true,false),(.copy,true,true)]
            for (mode,repairAudio,httpsInput) in scenarios {
                trace("gateway \(gatewayResults.count) begin")
                let engine = EmbeddedMediaEngine()
                do {
                    let began = Date()
                    let fixture = URL(string:"https://raw.githubusercontent.com/DonPick98/stremio-cast-bridge-ios/f14b900daaeae97a4970eea66b804ded21d9a82a/Tests/CodecSamples/h264-ac3.mkv")!
                    let source = httpsInput ? fixture : repairAudio ? documents.appendingPathComponent("CodecSamples/truehd.mkv") : input
                    let url = try await engine.start(input:source,deviceIP:"127.0.0.1",start:0,videoMode:mode,audioID:nil,subtitleID:nil,style:SubtitleAppearance(),repairAudio:repairAudio,selfTest:true)
                    trace("gateway \(gatewayResults.count) ready")
                    let capture = NativeStreamCapture()
                    let (body,cors,eof) = try await capture.read(url)
                    let suffix = mode == .softwareVP8 ? "webm" : "mp4"
                    let file = documents.appendingPathComponent("gateway-\(gatewayResults.count).\(suffix)")
                    try body.write(to:file)
                    let checked = try await EmbeddedMediaEngine.inspect(file)
                    gatewayResults.append(["mode":String(describing:mode),"audioRepair":repairAudio,"httpsInput":httpsInput,"bytes":body.count,"cors":cors,"eof":eof,"seconds":Date().timeIntervalSince(began),"description":checked.videoDescription,"audio":checked.audioCodecsDescription,"passed":cors && eof && !checked.audio.isEmpty])
                } catch {
                    gatewayResults.append(["mode":String(describing:mode),"passed":false,"error":error.localizedDescription])
                }
                engine.stop()
                trace("gateway \(gatewayResults.count) complete")
            }
            result["gateway"] = gatewayResults
            result["passed"] = (result["passed"] as? Bool == true) && gatewayResults.allSatisfy{$0["passed"] as? Bool == true}
            trace("codec matrix")
            let matrix = await NativeCodecMatrixValidation.run(documents:documents)
            if !matrix.isEmpty {
                result["matrix"] = matrix
                result["passed"] = (result["passed"] as? Bool == true) && matrix.count == 25 && matrix.allSatisfy { $0["passed"] as? Bool == true }
                trace("background conversion")
                let background = try await backgroundProbe(documents:documents)
                result["background"] = background
                result["passed"] = (result["passed"] as? Bool == true) && (background["passed"] as? Bool == true)
            }
        } catch { result["error"] = "Native codec probe failed: \(error.localizedDescription)" }
        if let data = try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:report,options:.atomic) }
    }
    private static func backgroundProbe(documents:URL) async throws -> [String:Any] {
        let engine = EmbeddedMediaEngine(); defer { engine.stop() }
        let input = documents.appendingPathComponent("CodecSamples/background-probe.mkv")
        let url = try await engine.start(input:input,deviceIP:"127.0.0.1",start:0,videoMode:.hardwareH264,audioID:nil,subtitleID:nil,style:SubtitleAppearance(),selfTest:true)
        let ready = try JSONSerialization.data(withJSONObject:["url":url.absoluteString])
        try ready.write(to:documents.appendingPathComponent("background-ready.json"),options:.atomic)
        let network = documents.appendingPathComponent("background-network.json")
        for _ in 0..<900 {
            if FileManager.default.fileExists(atPath:network.path) { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        let data = try Data(contentsOf:network)
        let metrics = try JSONSerialization.jsonObject(with:data) as? [String:Any] ?? [:]
        let offscreen = UIApplication.shared.applicationState == .background
        let helper = engine.testingBackgroundHelperPlaying
        let bytes = metrics["bytes"] as? Int ?? 0
        let seconds = metrics["seconds"] as? Double ?? 0
        let span = metrics["dataSpan"] as? Double ?? 0
        let lateBytes = metrics["lateBytes"] as? Int ?? 0
        let producerState = engine.testingProducerState
        engine.stop()
        for _ in 0..<50 { if engine.testingStopCompleted { break }; try await Task.sleep(nanoseconds:100_000_000) }
        let stopped = engine.testingStopCompleted
        return ["passed":offscreen && helper && stopped && bytes > 4096 && seconds >= 60 && span >= 55 && lateBytes > 4096,"offscreen":offscreen,"audioHelperPlaying":helper,"producerState":producerState,"stoppedCleanly":stopped,"bytesReadExternally":bytes,"seconds":seconds,"dataSpan":span,"lateBytes":lateBytes,"network":metrics]
    }
}

private final class NativeStreamCapture: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<(Data,Bool,Bool),Error>?
    private var body = Data()
    private var cors = false
    private var session: URLSession?
    func read(_ url: URL) async throws -> (Data,Bool,Bool) {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForResource = 12; config.timeoutIntervalForRequest = 12
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
        body.append(data.prefix(max(0,1_048_576-body.count)))
        if body.count >= 1_048_576 { dataTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let c = continuation; continuation = nil
        if body.count > 4096 { c?.resume(returning:(body,cors,error == nil)) }
        else { c?.resume(throwing:EmbeddedMediaError.encoder) }
        session.finishTasksAndInvalidate(); self.session = nil
    }
}
#endif
