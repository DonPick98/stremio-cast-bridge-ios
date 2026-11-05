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
        let compact="1\n00:00:01,000 --> 00:00:02,000\nFirst\n2\n00:00:03,000 --> 00:00:04,000\nSecond"
        let fixed=try SubtitleDocument.normalize(Data(compact.utf8))
        precondition(fixed.contains("First\n\n00:00:03.000") && !fixed.contains("First\n2"))
        let numeric="00:00:01,000 --> 00:00:02,000\n2024\n00:00:03,000 --> 00:00:04,000\nSecond"
        let numberText=try SubtitleDocument.normalize(Data(numeric.utf8));precondition(numberText.contains("2024"))
        for bad in ["WEBVTT","WEBVTTgarbage\n\n00:00:01.000 --> 00:00:02.000\nBad", "WEBVTT\n\nNOTE No captions", "WEBVTT\n\n00:00:01.000 --> 00:00:02.000", "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nFirst\n00:00:03.000 --> 00:00:04.000\nSecond"] {
            do {_ = try SubtitleDocument.normalize(Data(bad.utf8));fatalError("Invalid complete WebVTT accepted")}
            catch StreamHeaderError.invalid {}
        }
        let annotated="WEBVTT\n\nNOTE Comment --> ignored\n\ncue-id\n00:00:01.000 --> 00:00:02.000 align:start\n<i>Valid</i>"
        let annotationText=try SubtitleDocument.normalize(Data(annotated.utf8));precondition(annotationText.contains("<i>Valid</i>"))
        let fr=OnlineSubtitle(id:"fr",url:URL(string:"https://example.com/fr.srt")!,lang:"fra")
        let wrong=OnlineSubtitle(id:"en",url:URL(string:"https://example.com/en.srt")!,lang:"eng")
        precondition(SubtitleCatalog.sourceURL([wrong,fr],language:"fr-CA",fallback:nil,fallbackLanguage:nil)==fr.url)
        precondition(SubtitleCatalog.sourceURL([wrong],language:"fr",fallback:wrong.url,fallbackLanguage:"eng")==nil)
        precondition(SubtitleCatalog.sourceURL([],language:"it",fallback:wrong.url,fallbackLanguage:"ita")==wrong.url)
        precondition(SubtitleCatalog.sourceURL([fr],language:"off",fallback:fr.url,fallbackLanguage:"fr")==nil)
        precondition(SubtitleLanguage.code("English")=="en")
        precondition(SubtitleCatalog.sourceURL([],language:"en",fallback:wrong.url,fallbackLanguage:nil)==wrong.url)
        print("Subtitle catalogue, exact episode ranking, transport, hash, encodings, SRT/ASS and timing-window tests passed")
    }
}
