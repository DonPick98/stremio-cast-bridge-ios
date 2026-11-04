import Foundation
@main struct AppUpdateTests {
    static func main() throws {
        precondition(AppVersion("1.9")! < AppVersion("1.10.0")!)
        precondition(AppVersion("0.8.1")==AppVersion("0.8.1"))
        precondition(AppVersion("16.1")==AppVersion("16.1.0"))
        for bad in ["v1.2","1","1.2.3.4","-1.2","1..2","1.2-beta","1.2.1e9","1.٢","99999999999999999999.0"] {precondition(AppVersion(bad)==nil)}
        let base="https://github.com/DonPick98/stremio-cast-bridge-ios/releases/download/v0.8.2/"
        let hash=String(repeating:"a",count:64)
        func release(tag:String="v0.8.2",draft:Bool=false,prerelease:Bool=false,url:String?=nil,digest:String?=nil,duplicate:Bool=false)->AppRelease {
            let manifest=AppRelease.Asset(name:AppUpdatePolicy.manifestName,browser_download_url:URL(string:base+AppUpdatePolicy.manifestName)!,size:1024,digest:nil)
            let ipa=AppRelease.Asset(name:"CastBridge.ipa",browser_download_url:URL(string:url ?? base+"CastBridge.ipa")!,size:50_000_000,digest:digest ?? "sha256:"+hash)
            return AppRelease(tag_name:tag,draft:draft,prerelease:prerelease,body:"Release notes",assets:[manifest,ipa]+(duplicate ? [ipa]:[]))
        }
        func manifest(bundle:String="app.example.castbridge",sha:String?=nil,build:Int=36,minimum:String="16.1")->AppUpdateManifest {
            AppUpdateManifest(version:"0.8.2",build:build,minimumIOS:minimum,bundleIdentifier:bundle,asset:"CastBridge.ipa",sha256:sha ?? hash)
        }
        func candidate(_ row:AppRelease,_ info:AppUpdateManifest?=nil,version:String="0.8.1",build:Int=35,ios:String="27.2") throws->AvailableAppUpdate? {
            try AppUpdatePolicy.candidate(row,manifest:info ?? manifest(),currentVersion:version,currentBuild:build,systemVersion:ios,bundleIdentifier:"app.example.castbridge")
        }
        let good=try candidate(release())!
        precondition(good.version=="0.8.2" && good.build==36)
        let components=URLComponents(url:good.sideStoreURL!,resolvingAgainstBaseURL:false)!
        precondition(components.scheme=="sidestore" && components.host=="install")
        precondition(components.queryItems?.first?.value==base+"CastBridge.ipa")
        let equal=try candidate(release(),version:"0.8.2",build:36)
        let older=try candidate(release(),version:"0.9.0",build:1)
        let newerBuild=try candidate(release(),version:"0.8.2",build:35)
        precondition(equal==nil && older==nil && newerBuild != nil)
        func rejected(_ block:()throws->Void) {
            do{try block();fatalError("Invalid update accepted")}catch AppUpdateError.metadata{}catch AppUpdateError.incompatible{}catch{fatalError("Unexpected update error")}
        }
        for row in [release(draft:true),release(prerelease:true),release(tag:"v0.8.3"),release(duplicate:true),release(digest:"sha256:"+String(repeating:"b",count:64))] {
            rejected{_ = try candidate(row)}
        }
        for info in [manifest(bundle:"other.app"),manifest(sha:"invalid"),manifest(build:0),manifest(minimum:"99.0")] {
            rejected{_ = try candidate(release(),info)}
        }
        for url in ["http://github.com/DonPick98/stremio-cast-bridge-ios/releases/download/v0.8.2/CastBridge.ipa",base+"CastBridge.ipa?token=bad",base+"CastBridge.ipa#x","https://github.com/other/repo/releases/download/v0.8.2/CastBridge.ipa","https://github.com.evil.example/download/CastBridge.ipa",base+"Other.ipa"] {
            rejected{_ = try candidate(release(url:url))}
        }
        let encoded=Data(#"{"version":"0.8.2","build":36,"minimumIOS":"16.1","bundleIdentifier":"app.example.castbridge","asset":"CastBridge.ipa","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#.utf8)
        let decoded=try JSONDecoder().decode(AppUpdateManifest.self,from:encoded)
        precondition(decoded.build==36)
        print("App updates passed: numeric version/build order, OS compatibility, exact release/asset/bundle, digest coherence, duplicate rejection and SideStore URL round-trip")
    }
}
