import Foundation
import Security

struct BridgeHandoff: Decodable {
    let version: Int
    let status: String
    let provider: String
    let type: String
    let id: String
    let selection: String?
    let subtitleLanguage: String?
    let externalSubtitleURL: URL?
}

struct AddonResponse: Decodable { let streams: [AddonStream] }
struct AddonStream: Decodable, Identifiable {
    var id: String { url + "|" + descriptionText }
    let url: String
    let name: String?
    let description: String?
    let title: String?
    let infoHash: String?
    let behaviorHints: Hints?
    let subtitles: [Subtitle]?
    enum CodingKeys: String, CodingKey { case url, name, description, title, infoHash, behaviorHints, subtitles }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        url = (try? c.decode(String.self, forKey:.url)) ?? ""
        name = try? c.decode(String.self, forKey:.name)
        description = try? c.decode(String.self, forKey:.description)
        title = try? c.decode(String.self, forKey:.title)
        infoHash = try? c.decode(String.self, forKey:.infoHash)
        behaviorHints = try? c.decode(Hints.self, forKey:.behaviorHints)
        subtitles = try? c.decode([Subtitle].self, forKey:.subtitles)
    }
    struct Subtitle: Decodable { let url: String; let lang: String?; let id:String?; let label:String? }
    struct Hints: Decodable {
        let filename: String?
        let bingeGroup: String?
        let videoSize: Int64?
        let videoHash: String?
        let proxyHeaders: ProxyHeaders?
    }
    struct ProxyHeaders: Decodable { let request: [String:String]? }
    var descriptionText: String { description ?? title ?? "" }
    var fileSizeLabel: String { SourceFileSize.label(bytes:behaviorHints?.videoSize,description:descriptionText) ?? "Dimensione non disponibile" }
    var displayName: String { [name, descriptionText].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n") }
    var filename: String? {
        if let s = behaviorHints?.filename, !s.isEmpty { return s }
        if let u = URL(string: url), u.host?.hasPrefix("torrentio.") == true,
           u.path.contains("/resolve/realdebrid/"), u.pathExtension.range(of: "^(mkv|mp4|m4v|avi|webm)$", options: [.regularExpression, .caseInsensitive]) != nil { return u.lastPathComponent }
        return nil
    }
    var torrentHash: String? {
        let parts = [infoHash, behaviorHints?.bingeGroup?.components(separatedBy: "|").last] + (URL(string:url)?.pathComponents.map(Optional.some) ?? [])
        return parts.compactMap { $0 }.first { $0.range(of: "^[a-fA-F0-9]{40}$", options: .regularExpression) != nil }?.lowercased()
    }
    var identity: String {
        let filename = self.filename ?? descriptionText.components(separatedBy: .newlines).first { $0.range(of: "\\.(mkv|mp4|m4v|avi|webm|mov|ts)\\b", options: [.regularExpression, .caseInsensitive]) != nil }
        func norm(_ input: String) -> String {
            input.precomposedStringWithCompatibilityMapping
                .replacingOccurrences(of: "^[^\\p{L}\\p{N}\\[\\(]+", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        if let filename, !filename.isEmpty { return "file:" + norm(filename) }
        return "text:" + norm(name ?? "") + "|" + norm(descriptionText)
    }
}

enum BridgeError: LocalizedError {
    case invalidLink, expired, network, noSources, cannotResolve
    case sourceHTTP(Int)
    case handoffHTTP(Int), invalidHandoffResponse
    var errorDescription: String? {
        switch self {
        case .invalidLink: return "Collegamento non valido. Riapri la sorgente da Stremio."
        case .expired: return "L’elenco delle sorgenti in Stremio contiene un collegamento scaduto (HTTP 410). Aggiorna l’elenco dell’episodio; ricliccare una sorgente dello stesso elenco non rinnova il collegamento."
        case .network: return "Non riesco a contattare il servizio. Controlla la connessione e riprova."
        case .noSources: return "Nessuna sorgente disponibile. Riprova da Stremio."
        case .cannotResolve: return "Non riesco a preparare questo file. Prova un’altra sorgente."
        case .sourceHTTP(let status): return "L’add-on non ha risolto la sorgente (HTTP \(status)). Attendi prima di riprovare se segnala un limite di richieste."
        case .handoffHTTP(let status):
            if status == 400 { return "Il servizio non riconosce il collegamento Stremio (HTTP 400). Potrebbe appartenere a una configurazione precedente; non è un errore Real-Debrid." }
            if status == 429 { return "Il servizio che apre le sorgenti limita le richieste (HTTP 429). Attendi prima di riprovare." }
            return "Il servizio che apre le sorgenti non ha risposto correttamente (HTTP \(status)). Non è ancora iniziata la richiesta a Real-Debrid."
        case .invalidHandoffResponse: return "Il servizio che apre le sorgenti ha restituito una risposta inattesa (BRIDGE_RESPONSE)."
        }
    }
}

final class BridgeClient {
    static let shared = BridgeClient()
    private let session: URLSession
    init(session: URLSession? = nil) {
        if let session { self.session = session; return }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.urlCache = nil
        config.httpCookieStorage = nil
        self.session = URLSession(configuration: config)
    }
    private let endpoint = URL(string: "https://stremio-chromecast-bridge.donotpeek.chatgpt.site/api/bridge/native")!

    func ticket(from url: URL) throws -> String {
        guard url.scheme?.lowercased() == "stremiocast", url.host?.lowercased() == "open",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.filter({ $0.name == "ticket" }).count == 1,
              let ticket = items.first(where: { $0.name == "ticket" })?.value,
              ticket.count >= 20, ticket.count <= 12000,
              ticket.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else { throw BridgeError.invalidLink }
        return ticket
    }
    func handoff(ticket: String) async throws -> BridgeHandoff {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        req.httpBody = try JSONEncoder().encode(["ticket": ticket])
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw BridgeError.network }
        if http.statusCode == 410 { throw BridgeError.expired }
        guard http.statusCode == 200 else { throw BridgeError.handoffHTTP(http.statusCode) }
        guard data.count <= 100_000, let result = try? JSONDecoder().decode(BridgeHandoff.self, from: data) else { throw BridgeError.invalidHandoffResponse }
        guard result.version == 1, result.status == "ready", ["movie", "series"].contains(result.type),
              ["torrentio", "comet"].contains(result.provider), !result.id.isEmpty, result.id.count <= 300 else { throw BridgeError.invalidLink }
        return result
    }
    func episodes(videoID:String) async throws -> [SeriesEpisode] {
        guard let id=SeriesNavigation.seriesID(videoID),
              let url=URL(string:"https://v3-cinemeta.strem.io/meta/series/\(id).json") else { throw BridgeError.invalidLink }
        let (data,response)=try await session.data(from:url)
        guard (response as? HTTPURLResponse)?.statusCode==200,data.count<=2_000_000 else{throw BridgeError.network}
        struct Response:Decodable { struct Meta:Decodable {let id:String;let videos:[SeriesEpisode]?};let meta:Meta }
        let decoded=try JSONDecoder().decode(Response.self,from:data)
        guard decoded.meta.id==id else{throw BridgeError.invalidHandoffResponse}
        return decoded.meta.videos ?? []
    }
    func sources(_ handoff: BridgeHandoff, manifest: URL) async throws -> [AddonStream] {
        guard var parts = URLComponents(url:manifest, resolvingAgainstBaseURL:false) else { throw BridgeError.invalidLink }
        let allowed = CharacterSet(charactersIn:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encodedID = handoff.id.addingPercentEncoding(withAllowedCharacters: allowed) else { throw BridgeError.invalidLink }
        parts.percentEncodedPath = String(parts.percentEncodedPath.dropLast("manifest.json".count)) + "stream/" + handoff.type + "/" + encodedID + ".json"
        guard let url = parts.url else { throw BridgeError.invalidLink }
        var req = URLRequest(url:url)
        req.setValue("application/json", forHTTPHeaderField:"Accept")
        let (data, response) = try await session.data(for:req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= 2_000_000 else { throw BridgeError.network }
        let decoded = try JSONDecoder().decode(AddonResponse.self, from:data)
        let sources = decoded.streams.filter { s in
            guard let u = URL(string:s.url), u.scheme == "https", u.host != nil, u.user == nil, u.password == nil else { return false }
            return !s.descriptionText.localizedCaseInsensitiveContains("Comet public rate-limit exceeded")
        }
        guard !sources.isEmpty else { throw BridgeError.noSources }
        return Array(sources.prefix(150))
    }
    func resolveDirect(_ stream: AddonStream) async throws -> URL {
        guard stream.behaviorHints?.proxyHeaders?.request?.isEmpty != false, let url = URL(string:stream.url), url.scheme == "https" else { throw BridgeError.cannotResolve }
        if isRealDebridDownload(url) { return url }
        var req = URLRequest(url:url); req.httpMethod = "HEAD"
        let (_, response) = try await session.data(for:req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400, http.statusCode != 405 {
            throw BridgeError.sourceHTTP(http.statusCode)
        }
        guard let final = response.url, isRealDebridDownload(final), let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else { throw BridgeError.cannotResolve }
        return final
    }
    private func isRealDebridDownload(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased(), url.user == nil, url.password == nil else { return false }
        return host.hasSuffix(".download.real-debrid.com") || (host == "real-debrid.com" && url.path.hasPrefix("/d/"))
    }
}


struct AddonConfiguration {
    let provider: String
    let manifest: URL
    let realDebridKey: String
}

enum AddonConfigError: LocalizedError {
    case invalidProvider, invalidManifest, missingRealDebrid, keychain
    var errorDescription: String? {
        switch self {
        case .invalidProvider: return "Add-on non supportato."
        case .invalidManifest: return "Il collegamento dell’add-on non è valido."
        case .missingRealDebrid: return "Il collegamento non contiene una configurazione Real-Debrid valida."
        case .keychain: return "Non riesco a salvare la configurazione nel portachiavi dell’iPhone."
        }
    }
}

/// Only the personal manifest is persisted, in the device Keychain. No credentials
/// are sent to the bridge handoff endpoint or placed in the app deep link.
struct AddonConfigStore {
    private static let service = "app.castbridge.addons"
    static func parse(_ input: String, provider: String) throws -> AddonConfiguration {
        guard ["torrentio", "comet"].contains(provider) else { throw AddonConfigError.invalidProvider }
        var value = input.trimmingCharacters(in:.whitespacesAndNewlines)
        if value.lowercased().hasPrefix("stremio://") { value = "https://" + String(value.dropFirst("stremio://".count)) }
        guard value.count <= 5000, var parts = URLComponents(string:value),
              parts.scheme?.lowercased() == "https", let host = parts.host?.lowercased(),
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.percentEncodedPath.hasSuffix("/manifest.json") else { throw AddonConfigError.invalidManifest }
        let permitted = provider == "torrentio" ? ["torrentio.strem.fun", "torrentio.elfhosted.com"] : ["comet.elfhosted.com"]
        guard permitted.contains(host) else { throw AddonConfigError.invalidManifest }
        parts.fragment = nil
        guard let manifest = parts.url else { throw AddonConfigError.invalidManifest }
        let key: String?
        if provider == "torrentio" {
            let path = parts.percentEncodedPath.removingPercentEncoding ?? parts.percentEncodedPath
            let pattern = #"(?:^|[|/])realdebrid=([^|/]+)"#
            let expression = try NSRegularExpression(pattern:pattern)
            let ns = path as NSString
            if let match = expression.firstMatch(in:path, range:NSRange(location:0,length:ns.length)), match.numberOfRanges > 1, match.range(at:1).location != NSNotFound {
                key = ns.substring(with:match.range(at:1))
            } else { key = nil }
        } else {
            let encoded = parts.percentEncodedPath.split(separator:"/").first.map(String.init)?.removingPercentEncoding ?? ""
            var base64 = encoded.replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/")
            base64 += String(repeating:"=", count:(4 - base64.count % 4) % 4)
            if let data = Data(base64Encoded:base64),
               let object = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
               let services = object["debridServices"] as? [[String:Any]],
               let service = services.first(where:{ ($0["service"] as? String)?.lowercased() == "realdebrid" }) {
                key = service["apiKey"] as? String
            } else { key = nil }
        }
        guard let key, key.range(of:#"^[A-Za-z0-9_-]{20,150}$"#,options:.regularExpression) != nil else { throw AddonConfigError.missingRealDebrid }
        return AddonConfiguration(provider:provider,manifest:manifest,realDebridKey:key)
    }
    private static func query(_ provider: String) -> [String:Any] {
        [kSecClass as String:kSecClassGenericPassword,
         kSecAttrService as String:service,
         kSecAttrAccount as String:provider]
    }
    static func load(provider: String) throws -> AddonConfiguration? {
        var attributes = query(provider)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let bytes = result as? Data, let value = String(data:bytes,encoding:.utf8) else { throw AddonConfigError.keychain }
        return try parse(value,provider:provider)
    }
    static func save(_ configuration: AddonConfiguration) throws {
        let data = Data(configuration.manifest.absoluteString.utf8)
        let q = query(configuration.provider)
        let values: [String:Any] = [kSecValueData as String:data, kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let updated = SecItemUpdate(q as CFDictionary, values as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw AddonConfigError.keychain }
        var record = q
        for (key,value) in values { record[key] = value }
        guard SecItemAdd(record as CFDictionary,nil) == errSecSuccess else { throw AddonConfigError.keychain }
    }
}

