#if CAST_ENGINE_TESTING
import Foundation
import MobileVLCKit

@MainActor enum NativeCodecMatrixValidation {
    static func run(documents:URL) async -> [[String:Any]] {
        let folder = documents.appendingPathComponent("CodecSamples")
        guard let data = try? Data(contentsOf:folder.appendingPathComponent("manifest.json")),
              let cases = try? JSONSerialization.jsonObject(with:data) as? [[String:Any]] else { return [] }
        var results: [[String:Any]] = []
        for item in cases {
            let name = item["name"] as? String ?? "unknown"
            var row: [String:Any] = ["name":name,"passed":false,"stage":"input"]
            do {
                let input = folder.appendingPathComponent(item["filename"] as? String ?? "")
                let original = try await EmbeddedMediaEngine.inspect(input)
                row["inputAudio"] = original.audioCodecsDescription; row["inputVideo"] = original.videoDescription
                let burn = item["burn"] as? Bool ?? false
                let audio = (item["selectAlternate"] as? Bool == true ? original.audio.last : original.audio.first)!
                let subtitle = burn ? original.subtitles.first : nil
                if burn && subtitle == nil { throw EmbeddedMediaError.metadata }
                let copyAudio = ["aac","mp3"].contains(audio.codec.lowercased()) && (audio.channels ?? 0) > 0 && (audio.channels ?? 0) <= 2
                var attempts: [[String:String]] = []
                for mode in EmbeddedMediaEngine.modes(requiresVideo:original.requiresVideoConversion || burn) {
                    row["stage"] = "conversion"
                    let type = mode == .softwareVP8 ? "video/webm" : "video/mp4"
                    let ext = mode == .softwareVP8 ? "webm" : "mp4"
                    let output = documents.appendingPathComponent("matrix-\(name)-\(String(describing:mode)).\(ext)")
                    let media = VLCMedia(url:input)
                    media.addOption(":sout=\(EmbeddedMediaEngine.outputChain(videoMode:mode,copyAudio:copyAudio,burn:burn,access:"file",target:output.path))")
                    media.addOption(":no-sout-all"); media.addOption(":sout-mux-caching=4000")
                    if original.audio.count > 1, let id = Int(audio.key.dropFirst(4)) { media.addOption(":audio-track-id=\(id)") }
                    if let subtitle, let id = Int(subtitle.key.dropFirst(4)) { media.addOption(":sub-track-id=\(id)") }
                    else { media.addOption(":no-spu"); media.addOption(":no-sout-spu") }
                    let player = VLCMediaPlayer(options:["--quiet","--no-video-title-show"])
                    do {
                        player.media = media; player.play()
                        for i in 0..<300 {
                            try await Task.sleep(nanoseconds:100_000_000)
                            if player.state == .error { throw EmbeddedMediaError.encoder }
                            if i > 5 && (player.state == .ended || player.state == .stopped) { break }
                        }
                        player.stop()
                        row["stage"] = "output"
                        let header = try Data(contentsOf:output).prefix(1_048_576)
                        guard try PlayableStreamHeader.check(Data(header),contentType:type) else { throw StreamHeaderError.invalid }
                        let converted = try await EmbeddedMediaEngine.inspect(output)
                        row["outputAudio"] = converted.audioCodecsDescription; row["outputVideo"] = converted.videoDescription
                        row["outputChannels"] = converted.audio.first?.channels ?? 0; row["videoMode"] = String(describing:mode)
                        row["audioTracks"] = original.audio.count; row["chosenAudio"] = audio.language; row["subtitleBurn"] = burn
                        row["passed"] = (converted.audio.first?.channels ?? 0) == 2
                        row["stage"] = "complete"
                        let canonical = documents.appendingPathComponent("matrix-\(name).\(ext)")
                        try? FileManager.default.removeItem(at:canonical); try FileManager.default.copyItem(at:output,to:canonical)
                        break
                    } catch { player.stop(); attempts.append(["mode":String(describing:mode),"error":String(describing:error)]) }
                }
                row["attempts"] = attempts
            } catch { row["error"] = error.localizedDescription }
            results.append(row)
        }
        return results
    }
}
#endif
