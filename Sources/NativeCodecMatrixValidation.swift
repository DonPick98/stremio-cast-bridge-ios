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
                let repairAudio = AudioRepairPipe.required(audio.codec)
                var attempts: [[String:String]] = []
                for mode in EmbeddedMediaEngine.modes(requiresVideo:original.requiresVideoConversion || burn,video:original.video,burn:burn) {
                    row["stage"] = "conversion"
                    let ext = mode == .softwareVP8 ? "webm" : "mp4"
                    let label = String(describing:mode)
                    let output = documents.appendingPathComponent("matrix-\(name)-\(label).\(ext)")
                    do {
                        let engine = EmbeddedMediaEngine(); defer { engine.stop() }
                        do {
                            let url = try await engine.start(input:input,deviceIP:"127.0.0.1",start:item["start"] as? Double ?? 0,videoMode:mode,audioID:Int(audio.key.dropFirst(4)),subtitleID:subtitle.flatMap{Int($0.key.dropFirst(4))},style:SubtitleAppearance(),copyAudio:copyAudio,repairAudio:repairAudio,audioIndex:original.audio.firstIndex(where:{$0.key == audio.key}) ?? 0,subtitleIndex:subtitle.flatMap{s in original.subtitles.firstIndex(where:{$0.key == s.key})},video:original.video,selfTest:true)
                            let (body,_,eof) = try await NativeStreamCapture().read(url)
                            guard eof else { throw EmbeddedMediaError.encoder }
                            try body.write(to:output)
                            let converted = try await EmbeddedMediaEngine.inspect(output)
                            row["outputAudio"] = converted.audioCodecsDescription; row["outputVideo"] = converted.videoDescription
                            row["outputChannels"] = converted.audio.first?.channels ?? 0; row["videoMode"] = label
                            row["audioRepair"] = repairAudio; row["audioTracks"] = original.audio.count
                            row["chosenAudio"] = audio.language; row["subtitleBurn"] = burn
                            row["passed"] = (converted.audio.first?.channels ?? 0) == 2; row["stage"] = "complete"
                            let canonical = documents.appendingPathComponent("matrix-\(name).\(ext)")
                            try? FileManager.default.removeItem(at:canonical); try FileManager.default.copyItem(at:output,to:canonical)
                            break
                        } catch { attempts.append(["mode":label,"error":String(describing:error)]); continue }
                    }

                }
                row["attempts"] = attempts
            } catch { row["error"] = error.localizedDescription }
            results.append(row)
        }
        return results
    }
}
#endif
