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
        } catch { result["error"] = "Native codec probe failed: \(error.localizedDescription)" }
        if let data = try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:report,options:.atomic) }
    }
}
