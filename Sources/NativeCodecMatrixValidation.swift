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
            var row: [String:Any] = ["name":name,"passed":false]
            do {
                let filename = item["filename"] as? String ?? ""
                let input = folder.appendingPathComponent(filename)
                let original = try await EmbeddedMediaEngine.inspect(input)
                let burn = item["burn"] as? Bool ?? false
                let audio = (item["selectAlternate"] as? Bool == true ? original.audio.last : original.audio.first)!
                let subtitle = burn ? original.subtitles.first : nil
                if burn && subtitle == nil { throw EmbeddedMediaError.metadata }
                let mode: EmbeddedMediaEngine.VideoMode = original.requiresVideoConversion || burn ? .hardwareH264 : .copy
                let output = documents.appendingPathComponent("matrix-\(name).mp4")
                let media = VLCMedia(url:input)
                let copyAudio = ["aac","mp3"].contains(audio.codec.lowercased()) && (audio.channels ?? 0) > 0 && (audio.channels ?? 0) <= 2
                media.addOption(":sout=\(EmbeddedMediaEngine.outputChain(videoMode:mode,copyAudio:copyAudio,burn:burn,access:"file",target:output.path))")
                media.addOption(":no-sout-all")
                if let id = Int(audio.key.dropFirst(4)) { media.addOption(":audio-track-id=\(id)") }
                if let subtitle, let id = Int(subtitle.key.dropFirst(4)) { media.addOption(":sub-track-id=\(id)") }
                else { media.addOption(":no-spu"); media.addOption(":no-sout-spu") }
                let player = VLCMediaPlayer(options:["--quiet","--no-video-title-show"])
                player.media = media; player.play()
                for i in 0..<250 {
                    try await Task.sleep(nanoseconds:100_000_000)
                    if player.state == .error { player.stop(); throw EmbeddedMediaError.encoder }
                    if i > 5 && (player.state == .ended || player.state == .stopped) { break }
                }
                player.stop()
                let converted = try await EmbeddedMediaEngine.inspect(output)
                row["inputAudio"] = original.audioCodecsDescription
                row["inputVideo"] = original.videoDescription
                row["outputAudio"] = converted.audioCodecsDescription
                row["outputVideo"] = converted.videoDescription
                row["outputChannels"] = converted.audio.first?.channels ?? 0
                row["videoMode"] = String(describing:mode)
                row["audioTracks"] = original.audio.count
                row["chosenAudio"] = audio.language
                row["subtitleBurn"] = burn
                row["passed"] = converted.videoDescription.hasPrefix("H264") && (converted.audio.first?.channels ?? 0) == 2
            } catch { row["error"] = error.localizedDescription }
            results.append(row)
        }
        return results
    }
}
