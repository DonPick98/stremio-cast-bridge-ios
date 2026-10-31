import Foundation

@main struct SubtitleTests {
    static func main() async throws {
        let data = try Data(contentsOf: URL(fileURLWithPath:CommandLine.arguments[1]))
        let reader: MkvSubtitleExtractor.Reader = { offset,count in
            guard offset >= 0, count > 0, offset+count <= data.count else { throw SubtitleError.network }
            return data.subdata(in:offset..<offset+count)
        }
        let en = try await MkvSubtitleExtractor.extract(read:reader,language:"en")
        precondition(en.contains("00:00:01.000 --> 00:00:03.000"))
        precondition(en.contains("Hello &amp; &lt;world&gt;"))
        let it = try await MkvSubtitleExtractor.extract(read:reader,language:"it")
        precondition(it.contains("Ciao\nmondo"))
        precondition(!it.contains("Default"))
        do { _ = try MkvSubtitleExtractor.vint([0],0); fatalError("Invalid EBML accepted") } catch SubtitleError.malformed {}
        do { _ = try MkvSubtitleExtractor.header([0x1a]); fatalError("Truncated EBML accepted") } catch SubtitleError.malformed {}
        do { _ = try MkvSubtitleExtractor.clean("not an ASS packet",codec:"S_TEXT/ASS"); fatalError("Invalid ASS accepted") } catch SubtitleError.malformed {}
        do { _ = try await MkvSubtitleExtractor.extract(read:{_,_ in Data(repeating:0,count:65536)},language:"en"); fatalError("Invalid file accepted") } catch SubtitleError.malformed {}
        print("Subtitle tests passed: indexed UTF8/ASS, languages, exact times, escaping, malformed input")
    }
}
