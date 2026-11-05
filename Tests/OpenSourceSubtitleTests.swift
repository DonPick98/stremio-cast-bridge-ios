// Selected regression scenarios adapted from SubtitleKit SRTVTTSBVTests.swift
// (Dionysis Karatzas, MIT, revision728d62dac9fbda7fabd299eed3673ce36c85c267).
// Encoding coverage follows SwiftSubtitles' non-lossy decoder (Darren Ford, MIT).
// Complete licenses are in ThirdPartyLicenses/SubtitleKit-MIT.txt and SwiftSubtitles-MIT.txt.
import Foundation

@main struct OpenSourceSubtitleTests {
    static func normalize(_ data:Data,case label:String) throws -> String {
        do { return try SubtitleDocument.normalize(data) }
        catch { fatalError("Caption regression failed: "+label+" ("+String(describing:error)+")") }
    }
    static func main() throws {
        let compact="1\r\n00:00:00,500 --> 00:00:02,000\r\nFirst\r\n17\r\n00:00:02,500 --> 00:00:04,000\r\nSecond\r\n30\r\n00:00:04,500 --> 00:00:06,000\r\nThird"
        let parsed=try normalize(Data(compact.utf8),case:"compact indices")
        precondition(parsed.components(separatedBy:" --> ").count==4)
        precondition(parsed.contains("First\n\n00:00:02.500") && parsed.contains("Second\n\n00:00:04.500"))
        let short="1\n0:0:1,5 --> 0:0:2,25\nHello <b>world</b>"
        let padded=try normalize(Data(short.utf8),case:"short clocks")
        precondition(padded.contains("00:00:01.500 --> 00:00:02.250") && padded.contains("<b>world</b>"))
        for (fraction,expected) in [("1","100"),("01","010"),("001","001")] {
            let text="1\n0:0:1."+fraction+" --> 0:0:2\nFraction"
            let result=try normalize(Data(text.utf8),case:"fraction "+fraction)
            precondition(result.contains("00:00:01."+expected+" --> 00:00:02.000"))
        }
        let empty="1\n0:0:0,000 --> 0:0:1,000\n\n2\n0:0:1,000 --> 0:0:2,000\nWorking\n"
        let nonempty=try normalize(Data(empty.utf8),case:"empty cue")
        precondition(nonempty.components(separatedBy:" --> ").count==2 && nonempty.contains("Working"))
        let ass="[events]\n  format: layer, start, end, text\n  dialogue: 0,0:00:01.00,0:00:02.00,{\\i1}Hello, with commas"
        let assResult=try normalize(Data(ass.utf8),case:"ASS lowercase")
        precondition(assResult.contains("Hello, with commas") && !assResult.contains("{\\i1}"))
        let unicode="1\n00:00:01,000 --> 00:00:02,000\nCaffè 日本語"
        let little=Data([0xff,0xfe,0,0])+unicode.data(using:.utf32LittleEndian)!
        let big=Data([0,0,0xfe,0xff])+unicode.data(using:.utf32BigEndian)!
        let encodings=[Data(unicode.utf8),little,big,unicode.data(using:.utf16)!,unicode.data(using:.utf16LittleEndian)!,unicode.data(using:.utf16BigEndian)!]
        for (index,data) in encodings.enumerated() {
            let result=try normalize(data,case:"encoding \(index)")
            precondition(result.contains("Caffè 日本語"))
        }
        for invalid in ["1\n0:99:1 --> 0:99:2\nBad","1\n999999999999:0:1 --> 999999999999:0:2\nBad","1\n0:0:2 --> 0:0:1\nBad"] {
            do {_ = try SubtitleDocument.normalize(Data(invalid.utf8));fatalError("Invalid clock accepted")}
            catch StreamHeaderError.invalid {}
        }
        #if !canImport(ObjectiveC)
        print("Linux core only: Apple charset detection and URLSession transport are not exercised")
        #endif
        print("Open-source caption adaptation passed: cue boundaries, fractional clocks, empty cues, ASS fields, UTF32/UTF16/UTF8 and bounds")
    }
}
