import Foundation
#if canImport(UIKit)
import SwiftUI
import UIKit
#endif

struct AppVersion:Equatable,Comparable {
    let components:[Int]
    init?(_ text:String) {
        let pieces=text.split(separator:".",omittingEmptySubsequences:false)
        guard (2...3).contains(pieces.count),pieces.allSatisfy({!$0.isEmpty && $0.allSatisfy({$0.isASCII && $0.isNumber})}),
              pieces.allSatisfy({Int($0).map{(0..<10_000_000).contains($0)} == true}) else{return nil}
        components=pieces.map{Int($0)!}+Array(repeating:0,count:3-pieces.count)
    }
    static func < (lhs:Self,rhs:Self)->Bool {lhs.components.lexicographicallyPrecedes(rhs.components)}
}
struct AppRelease:Decodable {
    struct Asset:Decodable {
        let name:String
        let browser_download_url:URL
        let size:Int64
        let digest:String?
    }
    let tag_name:String
    let draft:Bool
    let prerelease:Bool
    let body:String?
    let assets:[Asset]
}
struct AppUpdateManifest:Decodable {
    let version:String
    let build:Int
    let minimumIOS:String
    let bundleIdentifier:String
    let asset:String
    let sha256:String
}
struct AvailableAppUpdate {
    let version:String
    let build:Int
    let ipa:URL
    let notes:String
    var sideStoreURL:URL? {
        var components=URLComponents();components.scheme="sidestore";components.host="install"
        components.queryItems=[URLQueryItem(name:"url",value:ipa.absoluteString)]
        return components.url
    }
}
enum AppUpdateError:Error {case metadata,incompatible,http,limit}
enum AppUpdatePolicy {
    static let owner="DonPick98",repository="stremio-cast-bridge-ios"
    static let manifestName="cast-bridge-update.json"
    static func assetURL(_ url:URL,tag:String,name:String)->Bool {
        url.scheme=="https" && url.host=="github.com" && url.user==nil && url.password==nil && url.port==nil && url.query==nil && url.fragment==nil &&
        url.pathComponents==["/",owner,repository,"releases","download",tag,name] && !tag.contains("/") && !name.contains("/")
    }
    static func manifestAsset(_ release:AppRelease)throws->AppRelease.Asset {
        let found=release.assets.filter{$0.name==manifestName}
        guard !release.draft,!release.prerelease,found.count==1,let asset=found.first,asset.size>0,asset.size<=65_536,
              assetURL(asset.browser_download_url,tag:release.tag_name,name:asset.name) else{throw AppUpdateError.metadata}
        return asset
    }
    static func candidate(_ release:AppRelease,manifest:AppUpdateManifest,currentVersion:String,currentBuild:Int,systemVersion:String,bundleIdentifier:String)throws->AvailableAppUpdate? {
        _ = try manifestAsset(release)
        guard let version=AppVersion(manifest.version),let current=AppVersion(currentVersion),let minimum=AppVersion(manifest.minimumIOS),let system=AppVersion(systemVersion),
              (1...Int(Int32.max)).contains(manifest.build),manifest.bundleIdentifier==bundleIdentifier,
              release.tag_name=="v"+manifest.version,
              manifest.asset.hasSuffix(".ipa"),!manifest.asset.contains("/"),!manifest.asset.contains("\\"),
              manifest.sha256.range(of:"^[a-fA-F0-9]{64}$",options:.regularExpression) != nil else{throw AppUpdateError.metadata}
        guard version>current || (version==current && manifest.build>currentBuild) else{return nil}
        guard system>=minimum else{throw AppUpdateError.incompatible}
        let found=release.assets.filter{$0.name==manifest.asset}
        guard found.count==1,let ipa=found.first,ipa.size>1_048_576,ipa.size<=524_288_000,
              ipa.digest?.lowercased()=="sha256:"+manifest.sha256.lowercased(),
              assetURL(ipa.browser_download_url,tag:release.tag_name,name:ipa.name) else{throw AppUpdateError.metadata}
        return AvailableAppUpdate(version:manifest.version,build:manifest.build,ipa:ipa.browser_download_url,notes:String((release.body ?? "").prefix(12_000)))
    }
}

#if canImport(UIKit)
@MainActor final class AppUpdater:ObservableObject {
    static let shared=AppUpdater()
    @Published private(set) var busy=false
    @Published private(set) var available:AvailableAppUpdate?
    @Published private(set) var message="Controlla le nuove versioni pubblicate."
    private var lastAutomaticCheck=UserDefaults.standard.object(forKey:"cast.updates.lastChecked") as? Date ?? Date.distantPast
    var currentLabel:String {
        let info=Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "—") (\(info["CFBundleVersion"] as? String ?? "—"))"
    }
    func checkIfNeeded() async {
        guard UserDefaults.standard.bool(forKey:"cast.updates.automatic"),Date().timeIntervalSince(lastAutomaticCheck)>=86_400 else{return}
        await check()
    }
    func check() async {
        guard !busy else{return}
        busy=true;available=nil;lastAutomaticCheck=Date();UserDefaults.standard.set(lastAutomaticCheck,forKey:"cast.updates.lastChecked");message="Controllo le versioni disponibili…"
        defer{busy=false}
        do {
            let url=URL(string:"https://api.github.com/repos/\(AppUpdatePolicy.owner)/\(AppUpdatePolicy.repository)/releases/latest")!
            let (data,status)=try await fetch(url,limit:524_288)
            if status==404 {message="Nessuna versione pubblica disponibile. Le build di sviluppo si installano ancora manualmente.";return}
            guard status==200 else{throw AppUpdateError.http}
            let release=try JSONDecoder().decode(AppRelease.self,from:data)
            let asset=try AppUpdatePolicy.manifestAsset(release)
            let (manifestData,manifestStatus)=try await fetch(asset.browser_download_url,limit:65_536)
            guard manifestStatus==200 else{throw AppUpdateError.http}
            let manifest=try JSONDecoder().decode(AppUpdateManifest.self,from:manifestData)
            let info=Bundle.main.infoDictionary ?? [:]
            guard let version=info["CFBundleShortVersionString"] as? String,let rawBuild=info["CFBundleVersion"] as? String,let build=Int(rawBuild),
                  let canonical=info["CastBridgeCanonicalBundleID"] as? String else{throw AppUpdateError.metadata}
            available=try AppUpdatePolicy.candidate(release,manifest:manifest,currentVersion:version,currentBuild:build,systemVersion:UIDevice.current.systemVersion,bundleIdentifier:canonical)
            message=available==nil ? "Hai già questa versione o una build più recente.":"È disponibile una nuova versione."
        } catch is CancellationError {message="Controllo interrotto."}
        catch AppUpdateError.incompatible {message="La nuova versione richiede un aggiornamento di iOS."}
        catch AppUpdateError.metadata {message="La release non contiene un aggiornamento compatibile e completo. L’installazione non è disponibile."}
        catch {message="Non riesco a controllare gli aggiornamenti. Riprova più tardi."}
    }
    private func fetch(_ url:URL,limit:Int) async throws ->(Data,Int) {
        let config=URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest=10;config.timeoutIntervalForResource=20
        config.httpCookieStorage=nil;config.urlCredentialStorage=nil;config.urlCache=nil
        let session=URLSession(configuration:config);defer{session.invalidateAndCancel()}
        var request=URLRequest(url:url);request.setValue("CastBridge",forHTTPHeaderField:"User-Agent")
        let (bytes,response)=try await session.bytes(for:request)
        guard let http=response as? HTTPURLResponse,http.url?.scheme=="https" else{throw AppUpdateError.http}
        guard http.statusCode==200 else{return (Data(),http.statusCode)}
        if http.expectedContentLength>Int64(limit){throw AppUpdateError.limit}
        var data=Data()
        for try await byte in bytes{try Task.checkCancellation();guard data.count<limit else{throw AppUpdateError.limit};data.append(byte)}
        return (data,http.statusCode)
    }
    func install() {
        guard !busy,let url=available?.sideStoreURL,UIApplication.shared.applicationState == .active else{return}
        UIApplication.shared.open(url,options:[:]){[weak self] success in
            Task { @MainActor in self?.message=success ? "Continua in SideStore per firmare e installare l’aggiornamento.":"SideStore non è disponibile. Installa SideStore oppure usa l’installazione manuale." }
        }
    }
}
#endif
