import Foundation
@main struct CaptionModelTests{
    static func main()throws{
        let data=Data(#"{"streams":[{"index":0,"codec_type":"video","codec_name":"hevc"},{"index":4,"codec_type":"subtitle","codec_name":"hdmv_pgs_subtitle","tags":{"language":"eng"}},{"index":7,"codec_type":"subtitle","codec_name":"ass","tags":{"language":"ita"}},{"index":12,"codec_type":"attachment","tags":{"filename":"../untrusted/font.ttf"}}]}"#.utf8)
        let catalog=try CaptionCatalog.parse(data)
        precondition(catalog.tracks.count==2&&catalog.fonts.first?.index==12)
        let selected=try catalog.selected(ordinal:1,vlcID:7,language:"it",codec:"ssa")
        precondition(selected.index==7)
        let header=CaptionArguments.catalog(input:URL(fileURLWithPath:"/tmp/synthetic.mkv"),headerOnly:true)
        precondition(header.contains("-nofind_stream_info") && header.contains("-show_format") && header.contains("-show_streams"))
        precondition(!CaptionArguments.catalog(input:URL(fileURLWithPath:"/tmp/synthetic.mkv"),headerOnly:false).contains("-nofind_stream_info"))
        let retry=CaptionArguments.networkInputOptions
        precondition(!retry.contains("-reconnect_at_eof"),"Clean EOF must stay finite")
        let statuses=retry[retry.firstIndex(of:"-reconnect_on_http_error")!+1].split(separator:",")
        precondition(!statuses.contains("401") && !statuses.contains("403") && !statuses.contains("429"))
        let many:[String:Any]=["streams":(0..<16).map{["index":$0,"codec_type":"subtitle","codec_name":"ass","tags":["language":$0==1 ? "ita":"eng"]] as [String:Any]}]
        let all=try CaptionCatalog.parse(JSONSerialization.data(withJSONObject:many))
        precondition(all.tracks.count==16 && all.tracks.allSatisfy(\.isText))
        let exactASS=try all.selected(ordinal:1,vlcID:1,language:"ita",codec:"ssa")
        precondition(exactASS.index==1)
        do{_=try catalog.selected(ordinal:0,vlcID:4,language:"ita",codec:"ssa");preconditionFailure("Wrong track accepted")}catch{}
        let window=CaptionWindow(position:100,duration:150)
        precondition(window.start==85&&window.end==150)
        let args=CaptionArguments.extraction(input:"https://example.test/private",track:7,format:.ass,window:window,file:"/tmp/owned.ass")
        precondition(args.contains("-copyts")&&args.contains("0:7")&&args.contains("0:a:0"))
        precondition(args.firstIndex(of:"-t")! > args.firstIndex(of:"-i")!)
        precondition(args.filter{$0=="-t"}.count==2)
        precondition(args.filter{$0=="-i"}.count==1)
        let silence=try CaptionDocument.completePrefix(Data("WEBVTT\n".utf8),format:.vtt)
        let prefix=try CaptionDocument.completePrefix(Data("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\ncomplete\n\n00:00:03.000 -->".utf8),format:.vtt)
        precondition(silence==Data("WEBVTT\n\n".utf8))
        precondition(prefix==Data("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\ncomplete\n\n".utf8))
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        var now=Date()
        let cache=CaptionDocumentCache(directory:root,budget:300,countLimit:2,lifetime:60,clock:{now})
        let input=URL(string:"https://example.test/private?token=secret")!
        let keys=(1...3).map{CaptionDocumentCache.key(input:input,track:String($0))}
        precondition(Set(keys).count==3 && keys.allSatisfy{$0.count==64 && !$0.contains("secret")})
        func document(_ value:String)->String {"WEBVTT\n\n00:00:01.000 --> 00:00:02.000\n"+value}
        cache.put(document("A"),key:keys[0]);now+=1
        cache.put(document("B"),key:keys[1]);now+=1
        precondition(cache.get(keys[0]) != nil);now+=1
        cache.put(document("C"),key:keys[2])
        precondition(cache.get(keys[1])==nil && cache.get(keys[0]) != nil && cache.get(keys[2]) != nil)
        let reopened=CaptionDocumentCache(directory:root,budget:300,countLimit:2,lifetime:60,clock:{now})
        precondition(reopened.get(keys[0]) != nil)
        cache.put("not complete",key:keys[0]);precondition(cache.get(keys[0])==document("A"))
        now+=61;precondition(cache.get(keys[0])==nil)
        let budgetRoot=root.appendingPathComponent("budget")
        let bounded=CaptionDocumentCache(directory:budgetRoot,budget:80,countLimit:20,clock:{now})
        bounded.put(document("12345678"),key:keys[0]);now+=1
        bounded.put(document("abcdefgh"),key:keys[1])
        precondition(bounded.get(keys[0])==nil && bounded.get(keys[1]) != nil)
        let legacyRoot=root.appendingPathComponent("legacy")
        let legacy=CaptionDocumentCache(directory:legacyRoot,clock:{now})
        let invalidFile=legacyRoot.appendingPathComponent(keys[0]+".vtt")
        try Data("WEBVTT\n\n".utf8).write(to:invalidFile)
        precondition(legacy.get(keys[0])==nil && !FileManager.default.fileExists(atPath:invalidFile.path))
        legacy.put(document("Working"),key:keys[0])
        legacy.put("WEBVTT\n\n",key:keys[0])
        precondition(legacy.get(keys[0])==document("Working"))
        let keep=legacyRoot.appendingPathComponent("unrelated.json")
        try Data("keep".utf8).write(to:keep)
        precondition(legacy.diskBytes()>0)
        precondition(legacy.clear() && legacy.get(keys[0])==nil)
        precondition(FileManager.default.fileExists(atPath:keep.path) && legacy.diskBytes()==0)
        precondition(!DirectCaptionPolicy.needsMediaProxy(force:false,compatible:true,audioChanged:false,burn:false,textSelected:true,corsAllowed:true))
        precondition(!DirectCaptionPolicy.needsMediaProxy(force:false,compatible:true,audioChanged:false,burn:false,textSelected:true,corsAllowed:nil))
        precondition(DirectCaptionPolicy.needsMediaProxy(force:false,compatible:true,audioChanged:false,burn:false,textSelected:true,corsAllowed:false))
        precondition(DirectCaptionPolicy.needsMediaProxy(force:false,compatible:true,audioChanged:true,burn:false,textSelected:true,corsAllowed:true))
        precondition(DirectCaptionPolicy.needsMediaProxy(force:false,compatible:true,audioChanged:false,burn:true,textSelected:false,corsAllowed:true))
        let headers=["Access-Control-Allow-Origin":"*","Access-Control-Allow-Methods":"GET, HEAD, OPTIONS","Access-Control-Allow-Headers":"Range, Content-Type, Accept-Encoding"]
        let response=HTTPURLResponse(url:input,statusCode:206,httpVersion:nil,headerFields:headers)!
        precondition(DirectCaptionPolicy.allows(response:response,preflight:true))
        precondition(!DirectCaptionPolicy.allows(response:HTTPURLResponse(url:input,statusCode:200,httpVersion:nil,headerFields:[:])!,preflight:false))
        precondition(!DirectCaptionPolicy.allows(response:HTTPURLResponse(url:input,statusCode:204,httpVersion:nil,headerFields:["Access-Control-Allow-Origin":"*"])!,preflight:true))
        print("Direct caption routing/CORS and persistent bounded LRU: passed")
        print("Caption model passed: exact stream mapping, bitmap exclusion, bounded windows, original timestamps, independent coverage heartbeat and complete cue publication")
    }
}

