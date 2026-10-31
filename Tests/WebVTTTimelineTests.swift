import Foundation
@main struct WebVTTTimelineTests {
    static func main() throws {
        let input = "WEBVTT\n\n1\n00:00:10.000 --> 00:00:12.000\nOld\n\n2\n00:00:58.500 --> 00:01:04.250 align:start\nCiao\nHello\n\n3\n00:02:00.000 --> 00:02:02.000\nLater\n"
        let result = String(data:try WebVTTTimeline.rebased(input,offset:60),encoding:.utf8)!
        precondition(!result.contains("Old") && result.contains("00:00:00.000 --> 00:00:04.250 align:start"))
        precondition(result.contains("Ciao\nHello") && result.contains("00:01:00.000 --> 00:01:02.000"))
        let empty = String(data:try WebVTTTimeline.rebased(input,offset:1000),encoding:.utf8)!
        precondition(empty.hasPrefix("WEBVTT") && !empty.contains("-->"))
        do { _ = try WebVTTTimeline.rebased("bad",offset:1); fatalError("Invalid subtitle accepted") } catch StreamHeaderError.invalid {}
        do { _ = try WebVTTTimeline.rebased("WEBVTT\n\n999999999999999999999999:00:00.000 --> 999999999999999999999999:00:01.000\nBad\n",offset:0); fatalError("Unbounded timestamp accepted") } catch StreamHeaderError.invalid {}
        print("Caption timeline tests passed: seeking, clipped cues, settings and text preservation")
    }
}
