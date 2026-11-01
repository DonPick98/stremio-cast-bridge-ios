#if CAST_ENGINE_TESTING
import Foundation
@MainActor enum CaptionIntegrationValidation{
    static func run(documents:URL)async throws->[String:Any]{
        let root=documents.appendingPathComponent("CodecSamples"),input=root.appendingPathComponent("caption-hevc-eac3.mkv")
        let catalog=try await CaptionExtractor.catalog(input)
        guard catalog.tracks.count==13,catalog.tracks[0].isASS else{throw CaptionFailure.probe}
        let fonts=try await CaptionExtractor.fonts(input,catalog:catalog)
        let expectedFont=try Data(contentsOf:root.appendingPathComponent("caption-font.ttf"))
        let fontPassed=fonts.count==1 && fonts[0].data==expectedFont
        let complete=try await CaptionExtractor.fullDocument(input:input,track:catalog.tracks[0])
        let sparseFile=root.appendingPathComponent("caption-late.mkv")
        let sparseCatalog=try await CaptionExtractor.catalog(sparseFile)
        let sparse=try await CaptionExtractor.fullDocument(input:sparseFile,track:sparseCatalog.tracks[0])
        let fullPassed=complete.contains("EMBEDDED CAPTION AFTER SEEK") && sparse.contains("01:40") && sparse.contains("LATE CAPTION")
        var results:[[String:Any]]=[]
        let cases:[(String,URL,Int,CaptionFormat,Double,Double)]=[
            ("ass-zero",input,0,.ass,0,12.05),("ass-seek",input,0,.ass,7,12.05),
            ("vtt-zero",input,0,.vtt,0,12.05),("vtt-seek",input,0,.vtt,7,12.05),
            ("late-cue",root.appendingPathComponent("caption-late.mkv"),0,.vtt,102,150),
            ("silence",root.appendingPathComponent("caption-late.mkv"),0,.vtt,0,150)
        ]
        for (name,file,index,format,position,duration) in cases{
            let probe=try await CaptionExtractor.catalog(file),extractor=CaptionExtractor()
            var snapshot:CaptionSnapshot?,failure:CaptionFailure?
            try extractor.start(input:file,track:probe.tracks[index],format:format,position:position,duration:duration,onUpdate:{snapshot=$0},onFailure:{failure=$0})
            let deadline=Date().addingTimeInterval(27)
            while failure==nil && Date()<deadline {
                if let snapshot,snapshot.coveredUntil>=min(duration,CaptionWindow(position:position,duration:duration).end)-0.05{break}
                try await Task.sleep(nanoseconds:100_000_000)
            }
            extractor.stop();guard failure==nil,let snapshot else{throw failure ?? CaptionFailure.timeout}
            let text=String(decoding:snapshot.data,as:UTF8.self)
            let passed:Bool
            if name=="silence"{passed=text.trimmingCharacters(in:.whitespacesAndNewlines)=="WEBVTT" && snapshot.coveredUntil>=89 && !snapshot.sourceComplete}
            else if name=="late-cue"{passed=text.contains("01:40") && !text.contains("00:15.000")}
            else{passed=text.contains("EMBEDDED CAPTION AFTER SEEK") && (format == .ass ? text.contains("[V4+ Styles]"):text.contains("00:06"))}
            try snapshot.data.write(to:documents.appendingPathComponent("caption-window-\(name).\(format.rawValue)"))
            results.append(["name":name,"passed":passed,"coveredUntil":snapshot.coveredUntil,"sourceComplete":snapshot.sourceComplete,"bytes":snapshot.data.count])
        }
        let cancelled=CaptionExtractor();var callbacks=0
        try cancelled.start(input:input,track:catalog.tracks[0],format:.ass,position:0,duration:12,onUpdate:{_ in callbacks+=1},onFailure:{_ in callbacks+=1})
        cancelled.stop();try await Task.sleep(nanoseconds:250_000_000)
        let server=CaptionHTTPServer(localIP:"127.0.0.1",peer:"127.0.0.1")
        let stateURL=try await server.start();defer{server.stop()}
        server.setState(epoch:"epoch-test",data:Data(#"{"version":1,"type":"clear"}"#.utf8))
        let asset=try await server.publish(Data("WEBVTT\n\n".utf8),format:.vtt)
        let(body,response)=try await URLSession.shared.data(from:asset)
        var bad=URLComponents(url:stateURL,resolvingAgainstBaseURL:false)!;bad.queryItems=[URLQueryItem(name:"epoch",value:"wrong")]
        let(_,denied)=try await URLSession.shared.data(from:bad.url!)
        let gateway=(response as? HTTPURLResponse)?.statusCode==200 && body==Data("WEBVTT\n\n".utf8) && (response as? HTTPURLResponse)?.value(forHTTPHeaderField:"Access-Control-Allow-Origin")=="*" && (denied as? HTTPURLResponse)?.statusCode==410
        return ["passed":results.count==6&&results.allSatisfy{$0["passed"] as? Bool==true}&&callbacks==0&&gateway&&fontPassed&&fullPassed,"windows":results,"cancelledCleanly":callbacks==0,"gateway":gateway,"fontPreserved":fontPassed,"fullDocuments":fullPassed]
    }
}
#endif
