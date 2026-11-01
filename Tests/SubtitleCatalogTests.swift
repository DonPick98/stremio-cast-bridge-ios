import Foundation

@main struct SubtitleCatalogTests {
    static func main() throws {
        let data = Data(#"{"subtitles":[{"id":"wrong","url":"https://example.com/wrong.srt","lang":"eng","subtitleFileName":"Show.S01E00.Pilot.srt"},{"id":"right","url":"https://example.com/right.srt","lang":"eng","subtitleFileName":"Show.S01E01.DVDRip.Group.srt","fpsMilli":29970},{"id":"right","url":"https://example.com/right.srt","lang":"eng"},{"id":"unsafe","url":"http://example.com/no.srt","lang":"ita"}]}"#.utf8)
        let rows = try SubtitleCatalog.decode(data,filename:"Show.S01E01.DVDRip.Group.mkv",fps:29.97)
        precondition(rows.count == 2 && rows[0].id == "right")
        let url = try SubtitleCatalog.requestURL(type:"series",id:"tt1234567:1:1",filename:"A & B.mkv",size:1000000,hash:"0123456789abcdef")
        precondition(url.host == "opensubtitles-v3.strem.io" && url.query == nil)
        precondition(url.path.contains("videoHash=0123456789abcdef") && url.path.contains("videoSize=1000000"))
        do { _ = try SubtitleCatalog.requestURL(type:"series",id:"../bad",filename:nil,size:nil,hash:nil); fatalError("Invalid identity accepted") } catch SubtitleCatalogError.identity {}
        let wrapped = URL(string:"http://127.0.0.1:11470/subtitles.vtt?from=https%3A%2F%2Fexample.com%2Fcaptions.srt")!
        precondition(OnlineSubtitle.safeURL(wrapped)?.absoluteString == "https://example.com/captions.srt")
        precondition(OnlineSubtitle.safeURL(URL(string:"https://user:password@example.com/file")!) == nil)
        let zeros = Data(repeating:0,count:65536)
        precondition(SubtitleCatalog.hash(first:zeros,last:zeros,size:131072) == "0000000000020000")
        var one = zeros; one[0] = 1
        precondition(SubtitleCatalog.hash(first:one,last:zeros,size:131072) == "0000000000020001")
        let window = SubtitleWindow(center:42)
        precondition(window.variants(kind:1).count == 21)
        precondition(Set(window.variants(kind:1).map(\.id)).count == 21)
        precondition(window.identifier(kind:1,delay:42) == 1)
        precondition(window.identifier(kind:1,delay:42.5) == 10011)
        precondition(window.identifier(kind:1,delay:49) == nil)
        precondition(SubtitleWindow.kind(20009) == 2)
        precondition(SubtitleWindow.normalized(.nan) == 0 && SubtitleWindow.normalized(500) == 300)
        let srt = "1\r\n00:00:04,250 --> 00:00:06,750\r\nCiao mondo\r\n"
        let vtt = try SubtitleDocument.normalize(Data(srt.utf8))
        precondition(vtt.contains("00:00:04.250 --> 00:00:06.750") && vtt.hasPrefix("WEBVTT"))
        let utf16 = srt.data(using:.utf16)!
        let decodedUTF16 = try SubtitleDocument.normalize(utf16)
        precondition(decodedUTF16.contains("Ciao mondo"))
        let ass = "[Script Info]\nTitle: test\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:04.25,0:00:06.75,Default,,0,0,0,,{\\i1}Ciao\\Nmondo\n"
        let decodedASS = try SubtitleDocument.normalize(Data(ass.utf8))
        precondition(decodedASS.contains("Ciao\nmondo"))
        do { _ = try SubtitleDocument.normalize(Data("<html>Error</html>".utf8)); fatalError("HTML accepted") } catch StreamHeaderError.invalid {}
        print("Subtitle catalogue, exact episode ranking, transport, hash, encodings, SRT/ASS and timing-window tests passed")
    }
}
