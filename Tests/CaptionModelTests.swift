import Foundation
@main struct CaptionModelTests{
    static func main()throws{
        let data=Data(#"{"streams":[{"index":0,"codec_type":"video","codec_name":"hevc"},{"index":4,"codec_type":"subtitle","codec_name":"hdmv_pgs_subtitle","tags":{"language":"eng"}},{"index":7,"codec_type":"subtitle","codec_name":"ass","tags":{"language":"ita"}},{"index":12,"codec_type":"attachment","tags":{"filename":"../untrusted/font.ttf"}}]}"#.utf8)
        let catalog=try CaptionCatalog.parse(data)
        precondition(catalog.tracks.count==2&&catalog.fonts.first?.index==12)
        let selected=try catalog.selected(ordinal:1,vlcID:7,language:"it",codec:"ssa")
        precondition(selected.index==7)
        do{_=try catalog.selected(ordinal:0,vlcID:4,language:"ita",codec:"ssa");preconditionFailure("Wrong track accepted")}catch{}
        let window=CaptionWindow(position:100,duration:150)
        precondition(window.start==85&&window.end==150)
        let args=CaptionArguments.extraction(input:"https://example.test/private",track:7,format:.ass,window:window,file:"/tmp/owned.ass",progressFD:19)
        precondition(args.contains("-copyts")&&args.contains("0:7")&&args.contains("0:a:0"))
        precondition(args.firstIndex(of:"-t")! < args.firstIndex(of:"-i")!)
        precondition(args.filter{$0=="-i"}.count==1)
        let silence=try CaptionDocument.completePrefix(Data("WEBVTT\n".utf8),format:.vtt)
        let prefix=try CaptionDocument.completePrefix(Data("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\ncomplete\n\n00:00:03.000 -->".utf8),format:.vtt)
        precondition(silence==Data("WEBVTT\n\n".utf8))
        precondition(prefix==Data("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\ncomplete\n\n".utf8))
        print("Caption model passed: exact stream mapping, bitmap exclusion, bounded windows, original timestamps, independent coverage heartbeat and complete cue publication")
    }
}
