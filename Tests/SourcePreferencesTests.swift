import Foundation
@main struct SourcePreferencesTests {
    static func main() {
        let suite="cast.sources.tests."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer{defaults.removePersistentDomain(forName:suite)}
        struct Row {let id:String;let height:Int?;let bytes:Int64?}
        let rows=[Row(id:"4k",height:2160,bytes:100),Row(id:"unknown",height:nil,bytes:nil),Row(id:"1080",height:1080,bytes:50),Row(id:"720small",height:720,bytes:10),Row(id:"720big",height:720,bytes:20),Row(id:"720unknown",height:720,bytes:nil)]
        func order()->[String]{SourcePreferences.ordered(rows,defaults:defaults){($0.height,$0.bytes)}.map(\.id)}
        precondition(order()==rows.map(\.id))
        defaults.set(720,forKey:"cast.sources.resolution")
        defaults.set("small",forKey:"cast.sources.order")
        precondition(order()==["720small","720big","720unknown","unknown","1080","4k"])
        defaults.set("large",forKey:"cast.sources.order")
        precondition(order()==["720big","720small","720unknown","unknown","1080","4k"])
        defaults.set(1080,forKey:"cast.sources.resolution")
        precondition(order().first=="1080")
        defaults.set(9999,forKey:"cast.sources.resolution")
        defaults.set("invalid",forKey:"cast.sources.order")
        precondition(order()==rows.map(\.id))
        for (text,height) in [("Synthetic.1080p.mkv",1080),("Synthetic.720P.x264",720),("2160p",2160)]{precondition(SourcePreferences.resolution(text)==height)}
        for unknown in ["720p1080p","1080p or 720p","unknown","1080pixels","10720p"]{precondition(SourcePreferences.resolution(unknown)==nil)}
        defaults.set("keep",forKey:"cast.account.private")
        defaults.set("it",forKey:"cast.preferred.audio")
        SourcePreferences.reset(defaults:defaults)
        precondition(order()==rows.map(\.id))
        precondition(defaults.string(forKey:"cast.account.private")=="keep" && defaults.string(forKey:"cast.preferred.audio")=="it")
        print("Source preferences passed: stable original order, explicit resolution tiers, known sizes first, unknown/ambiguous metadata and isolated reset")
    }
}
