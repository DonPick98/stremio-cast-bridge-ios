import Foundation
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum CastContentIdentity {
    static func matches(expected: String, contentURL: String?, contentID: String?) -> Bool {
        !expected.isEmpty && (contentURL == expected || contentID == expected)
    }
}

/// A track reported by Real-Debrid for this particular file.
struct RDTrack: Identifiable, Hashable {
    let key: String
    let language: String
    let label: String
    let codec: String
    var id: String { key }
}

enum RDQuality: String, CaseIterable {
    case medium, high, original
}

enum RDResolverError: LocalizedError {
    case invalidConfiguration, invalidFile, fileNotIdentified
    case fileNotReady(String, Int?)
    case rateLimited(Int)
    case apiFailure(status: Int, code: Int?, stage: String)
    case unavailable, invalidResponse, invalidTrack, invalidStream, http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "La configurazione Real-Debrid non è valida."
        case .invalidFile: return "Il file selezionato non può essere identificato."
        case .fileNotIdentified: return "Non riesco a trovare esattamente il file scelto."
        case .fileNotReady(let state, let progress):
            let labels = ["queued":"in coda", "downloading":"in download", "magnet_conversion":"lettura torrent", "waiting_files_selection":"attesa selezione file", "compressing":"compressione", "uploading":"preparazione collegamento"]
            return "Questa sorgente non è pronta per lo streaming. Real-Debrid è ancora in stato \(labels[state] ?? "file non pronto")\(progress.map { " (\($0)%)" } ?? "") dopo l’attesa massima. Scegli un’altra sorgente o controlla la preparazione nel tuo account RD."
        case .rateLimited(let seconds): return "Real-Debrid limita le richieste. Attendi almeno \(seconds) secondi prima di riprovare."
        case .apiFailure(let status, let code, let stage):
            let diagnostic = "HTTP \(status)\(code.map { ", RD \($0)" } ?? "") · \(stage)"
            if code == 35 { return "Real-Debrid rifiuta questo file (\(diagnostic))." }
            if code == 36 { return "Real-Debrid segnala un limite di utilizzo (\(diagnostic))." }
            return "Real-Debrid non ha completato la richiesta (\(diagnostic))."
        case .unavailable: return "Il file non è disponibile su Real-Debrid."
        case .invalidResponse: return "Real-Debrid ha restituito una risposta non valida."
        case .invalidTrack: return "La traccia scelta non è disponibile."
        case .invalidStream: return "Il collegamento video ricevuto non è valido."
        case .http(let code): return "Real-Debrid ha risposto con errore \(code)."
        }
    }
}

/// Shared, in-memory pacing across resolvers. No tokens or links are persisted.
actor RDRequestGate {
    static let shared = RDRequestGate()
    private var next: [String:Date] = [:]
    private var blocked: [String:Date] = [:]
    private var torrents: [String:(String,Date)] = [:]
    func enter(_ account: String) async throws {
        try Task.checkCancellation()
        if let until = blocked[account], until > Date() { throw RDResolverError.rateLimited(Int(ceil(until.timeIntervalSinceNow))) }
        let when = max(Date(), next[account] ?? .distantPast)
        next[account] = when.addingTimeInterval(0.4)
        let delay = when.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(nanoseconds:UInt64(delay*1e9)) }
        try Task.checkCancellation()
        if let until = blocked[account], until > Date() { throw RDResolverError.rateLimited(Int(ceil(until.timeIntervalSinceNow))) }
    }
    func block(_ account: String, seconds: Int) { blocked[account] = Date().addingTimeInterval(Double(seconds)) }
    func torrent(_ key: String) -> String? {
        guard let (id,time) = torrents[key], Date().timeIntervalSince(time) < 300 else { torrents[key] = nil; return nil }
        return id
    }
    func remember(_ id: String, key: String) {
        if torrents.count >= 64, let oldest = torrents.min(by:{$0.value.1 < $1.value.1})?.key { torrents[oldest] = nil }
        torrents[key] = (id,Date())
    }
    func forget(_ key: String) { torrents[key] = nil }
}

/// A validated original file and, when available, HLS conversion variants.
/// Conversion selects one audio track and can burn a subtitle into the picture.
struct RDPreparedMedia {
    // The transcode URL identifies Real-Debrid's default audio track. It is not
    // necessarily the original language, so the user can still change it.
    let audio: [RDTrack]
    let subtitles: [RDTrack]
    let defaultAudioKey: String
    let directURL: URL
    let directContentType: String
    let directCompatible: Bool
    let videoDescription: String
    let duration: Double
    fileprivate let variants: [String: String]

    var availableQualities: [RDQuality] { RDQuality.allCases.filter { variants[$0.rawValue] != nil } }

    var audioCodecsDescription: String {
        Array(Set(audio.map { $0.codec.trimmingCharacters(in:.whitespacesAndNewlines).uppercased() }.filter { !$0.isEmpty })).sorted().joined(separator:" / ")
    }
    var directAudioNotice: String? {
        let codecs = audio.map { $0.codec.lowercased().replacingOccurrences(of:"-",with:"").replacingOccurrences(of:"_",with:"") }
        if codecs.contains(where:{ ["ac3","eac3","ec3"].contains($0) }) {
            return "Audio Dolby (\(audioCodecsDescription)): nel file originale la riproduzione dipende anche dal supporto della TV. Il video può partire senza audio."
        }
        if codecs.contains(where:{ $0.contains("dts") || $0.contains("truehd") }) {
            return "Audio \(audioCodecsDescription): il Chromecast classico può riprodurre il video senza decodificare questa traccia."
        }
        if audio.count > 1 { return "Nel percorso diretto il Chromecast sceglie l’audio del file: la traccia può essere diversa da quella selezionata per la conversione." }
        if codecs.isEmpty || codecs.contains("") { return "Il formato audio non è indicato: l’avvio del video non conferma che l’audio sia riproducibile." }
        return nil
    }

    func streamURL(audio: String, subtitle: String? = nil, quality: RDQuality = .high) throws -> URL {
        guard self.audio.contains(where: { $0.key == audio }),
              subtitle == nil || subtitles.contains(where: { $0.key == subtitle }) else {
            throw RDResolverError.invalidTrack
        }
        let sub = subtitle ?? "none"
        guard let raw = variants[quality.rawValue],
              var components = URLComponents(string: raw),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              host.range(of: #"^(?:[a-z0-9-]+\.)?stream\.real-debrid\.com$"#, options: .regularExpression) != nil,
              components.user == nil, components.password == nil, components.port == nil else {
            throw RDResolverError.invalidStream
        }
        var parts = components.path.components(separatedBy: "/")
        guard parts.count == 7, parts[0].isEmpty, parts[1] == "t",
              parts[2].range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil,
              parts[6].range(of: #"^[a-zA-Z0-9_-]+\.m3u8$"#, options: .regularExpression) != nil,
              audio.range(of: #"^[a-zA-Z]{2,3}[0-9]{1,3}$"#, options: .regularExpression) != nil,
              sub == "none" || sub.range(of: #"^[a-zA-Z]{2,3}[0-9]{1,3}$"#, options: .regularExpression) != nil else {
            throw RDResolverError.invalidStream
        }
        parts[3] = audio
        parts[4] = sub
        parts[5] = "aac"
        components.path = parts.joined(separator: "/")
        guard let url = components.url else { throw RDResolverError.invalidStream }
        return url
    }
}

/// All RD calls run on the phone's connection, preserving IP-bound debrid links.
/// Preparing a torrent can add it to the account and select a file in that torrent.
struct RDNativeResolver {
    private let apiKey: String
    private let session: URLSession
    private let pollDelay: UInt64
    private let maxPreparationChecks: Int
    private var account: String { SHA256.hash(data:Data(apiKey.utf8)).map{String(format:"%02x",$0)}.joined() }

    init(apiKey: String, session: URLSession = .shared, pollDelay: UInt64 = 5_000_000_000, maxPreparationChecks: Int = 36) {
        self.apiKey = apiKey
        self.session = session
        self.pollDelay = pollDelay
        self.maxPreparationChecks = min(36,max(1,maxPreparationChecks))
    }

    func prepare(torrentHash: String, filename: String, videoSize: Int64? = nil,
                 onProgress: @escaping @Sendable (String,Int?) async -> Void = {_,_ in}) async throws -> RDPreparedMedia {
        guard torrentHash.range(of: #"^[a-fA-F0-9]{40}$"#, options: .regularExpression) != nil,
              !filename.isEmpty, filename.count <= 500 else { throw RDResolverError.invalidFile }
        let cacheKey = account + "|" + torrentHash.lowercased() + "|" + basename(filename) + "|" + String(videoSize ?? 0)
        let id: String
        if let saved = await RDRequestGate.shared.torrent(cacheKey) { id = saved }
        else {
            let added = try await api("torrents/addMagnet", form: ["magnet": "magnet:?xt=urn:btih:\(torrentHash)"])
            guard let newID = added["id"] as? String, validID(newID) else { throw RDResolverError.invalidResponse }
            id = newID
            await RDRequestGate.shared.remember(id,key:cacheKey)
        }
        let infoPath = "torrents/info/\(id)"
        let wanted = basename(filename)
        guard !wanted.isEmpty else { throw RDResolverError.invalidFile }
        var info: [String:Any] = [:], selectedOnce = false
        let deadline = Date().addingTimeInterval(180)
        for check in 0..<maxPreparationChecks {
            try Task.checkCancellation()
            if check > 0 {
                guard Date() < deadline else { break }
                try await Task.sleep(nanoseconds:pollDelay)
            }
            do { info = try await api(infoPath) }
            catch { await RDRequestGate.shared.forget(cacheKey); throw error }
            let status = info["status"] as? String ?? ""
            let rawProgress = (info["progress"] as? NSNumber)?.intValue
            let progress = rawProgress.map { min(100,max(0,$0)) }
            await onProgress(status,progress)
            if ["magnet_error", "error", "virus", "dead"].contains(status) {
                await RDRequestGate.shared.forget(cacheKey)
                throw RDResolverError.unavailable
            }
            guard let files = info["files"] as? [[String:Any]], !files.isEmpty else { continue }
            var matches = files.filter { basename($0["path"] as? String ?? "") == wanted }
            if matches.count > 1, let videoSize { matches = matches.filter { ($0["bytes"] as? NSNumber)?.int64Value == videoSize } }
            guard matches.count == 1, let targetID = (matches[0]["id"] as? NSNumber)?.intValue, targetID > 0 else { throw RDResolverError.fileNotIdentified }
            if (matches[0]["selected"] as? NSNumber)?.intValue != 1 {
                if !selectedOnce {
                    _ = try await api("torrents/selectFiles/\(id)",form:["files":String(targetID)])
                    selectedOnce = true
                }
                continue
            }
            guard status == "downloaded" else { continue }
            guard let links = info["links"] as? [String] else { throw RDResolverError.invalidResponse }
            let selected = files.filter { ($0["selected"] as? NSNumber)?.intValue == 1 }
            guard selected.count == links.count,
                  let index = selected.firstIndex(where:{($0["id"] as? NSNumber)?.intValue == targetID}),
                  let link = URL(string:links[index]) else { throw RDResolverError.invalidResponse }
            await onProgress("reading_metadata",100)
            return try await prepare(directLink:link)
        }
        let progress = (info["progress"] as? NSNumber)?.intValue
        throw RDResolverError.fileNotReady(info["status"] as? String ?? "",progress.map{min(100,max(0,$0))})
    }

    /// Accepts an account link from Real-Debrid, not an arbitrary third-party URL.
    func prepare(directLink: URL) async throws -> RDPreparedMedia {
        guard isRealDebridLink(directLink) else { throw RDResolverError.invalidStream }
        let unrestricted = try await api("unrestrict/link", form: ["link": directLink.absoluteString])
        guard let id = unrestricted["id"] as? String, validID(id) else { throw RDResolverError.invalidResponse }
        guard let rawDownload = unrestricted["download"] as? String,
              let download = URL(string: rawDownload), download.scheme?.lowercased() == "https",
              let downloadHost = download.host?.lowercased(),
              downloadHost.range(of: #"^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+download\.real-debrid\.com$"#, options: .regularExpression) != nil,
              download.user == nil, download.password == nil, download.port == nil else {
            throw RDResolverError.invalidStream
        }
        async let info = api("streaming/mediaInfos/\(id)")
        async let transcodes = try? api("streaming/transcode/\(id)")
        let (media, converted) = try await (info, transcodes)
        guard let details = media["details"] as? [String: Any] else { throw RDResolverError.invalidResponse }
        let appleValues = converted?["apple"] as? [String: Any] ?? [:]
        let apple = appleValues.compactMapValues { $0 as? String }
        let audio = tracks(details["audio"])
        guard !audio.isEmpty else { throw RDResolverError.invalidResponse }
        let preferredURL = apple["medium"] ?? apple["high"] ?? apple.values.first
        let preferredKey: String? = preferredURL.flatMap { raw in
            guard let url = URL(string: raw) else { return nil }
            let pieces = url.path.split(separator: "/")
            return pieces.count > 2 ? String(pieces[2]) : nil
        }
        let defaultAudioKey = audio.first(where: { $0.key == preferredKey })?.key ?? audio[0].key
        let videoContainer = details["video"] as? [String: Any] ?? [:]
        let video: [String: Any]
        if videoContainer["codec"] is String {
            video = videoContainer
        } else {
            let key = videoContainer.keys.sorted().first {
                $0.range(of: #"^[a-zA-Z]{2,3}[0-9]{1,3}$"#, options: .regularExpression) != nil &&
                (videoContainer[$0] as? [String: Any])?["codec"] is String
            }
            video = key.flatMap { videoContainer[$0] as? [String: Any] } ?? [:]
        }
        let codec = (video["codec"] as? String ?? "").lowercased()
        let audioCodec = audio.first(where: { $0.key == defaultAudioKey })?.codec.lowercased() ?? ""
        func number(_ value: Any?) -> Double? {
            let parsed: Double?
            if let n = value as? NSNumber { parsed = n.doubleValue }
            else if let s = value as? String {
                let parts = s.split(separator: "/")
                if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0 { parsed = a / b }
                else { parsed = Double(s) }
            } else { parsed = nil }
            guard let parsed, parsed.isFinite, parsed > 0, parsed < 100_000 else { return nil }
            return parsed
        }
        let width = number(video["width"])
        let height = number(video["height"])
        let fpsValue = video["fps"] ?? video["frame_rate"]
        let fps = number(fpsValue)
        let ext = ((unrestricted["filename"] as? String ?? download.lastPathComponent) as NSString).pathExtension.lowercased()
        let type = ext == "mkv" ? "video/x-matroska" : "video/mp4"
        let dimensionsOK = width.map { $0 > 0 && $0 <= 1920 } == true && height.map { $0 > 0 && $0 <= 1080 } == true
        let fpsOK = fps.map { $0 <= 60 } ?? (fpsValue == nil)
        let compatible = ["h264", "avc", "avc1"].contains(codec) && audio.count == 1 && audioCodec.contains("aac") && ["mkv", "mp4", "m4v"].contains(ext) && dimensionsOK && fpsOK
        let resolution = width.flatMap { w in height.map { h in "\(Int(w))×\(Int(h))" } }
        let description = (["Originale", codec.isEmpty ? nil : codec.uppercased(), resolution].compactMap { $0 }).joined(separator: " · ")
        let duration = number(media["duration"] ?? details["duration"] ?? video["duration"]) ?? 0
        return RDPreparedMedia(audio: audio, subtitles: tracks(details["subtitles"]), defaultAudioKey: defaultAudioKey, directURL: download, directContentType: type, directCompatible: compatible, videoDescription: description, duration: duration, variants: apple)
    }

    private func api(_ path: String, form: [String: String]? = nil) async throws -> [String: Any] {
        guard apiKey.range(of: #"^[A-Za-z0-9_-]{20,150}$"#, options: .regularExpression) != nil,
              path.range(of: #"^[A-Za-z0-9/_-]+$"#, options: .regularExpression) != nil,
              let url = URL(string: "https://api.real-debrid.com/rest/1.0/" + path) else {
            throw RDResolverError.invalidConfiguration
        }
        try await RDRequestGate.shared.enter(account)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let form = form {
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var encoded = URLComponents()
            encoded.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
            // application/x-www-form-urlencoded treats a literal plus as a space.
            request.httpBody = encoded.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RDResolverError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let object = data.count <= 100_000 ? (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] : nil
            let code = (object?["error_code"] as? NSNumber)?.intValue
            if http.statusCode == 429 || code == 34 || code == 5 {
                let wait = min(3600,max(60,Int(http.value(forHTTPHeaderField:"Retry-After") ?? "") ?? 60))
                await RDRequestGate.shared.block(account,seconds:wait)
                throw RDResolverError.rateLimited(wait)
            }
            let stage = path.hasPrefix("torrents/add") ? "aggiunta torrent" : path.hasPrefix("torrents/select") ? "selezione file" : path.hasPrefix("torrents/info") ? "stato torrent" : path.hasPrefix("unrestrict/") ? "collegamento video" : path.hasPrefix("streaming/mediaInfos") ? "lettura tracce" : "conversione"
            throw RDResolverError.apiFailure(status:http.statusCode,code:code,stage:stage)
        }
        if http.statusCode == 204 { return [:] }
        guard data.count <= 2_000_000,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RDResolverError.invalidResponse
        }
        return object
    }

    private func tracks(_ value: Any?) -> [RDTrack] {
        guard let dictionary = value as? [String: Any] else { return [] }
        return dictionary.keys.sorted().filter {
            $0.range(of: #"^[a-zA-Z]{2,3}[0-9]{1,3}$"#, options: .regularExpression) != nil && dictionary[$0] is [String: Any]
        }.prefix(64).compactMap { key in
            guard let track = dictionary[key] as? [String: Any] else { return nil }
            let language = String((track["lang_iso"] as? String ?? "und").lowercased().prefix(8))
            let label = String((track["lang"] as? String ?? track["lang_iso"] as? String ?? "Sconosciuta").prefix(100))
            let codec = String((track["codec"] as? String ?? track["type"] as? String ?? "").prefix(30))
            return RDTrack(key: key, language: language, label: label, codec: codec)
        }
    }

    private func validID(_ id: String) -> Bool {
        id.range(of: #"^[A-Za-z0-9_-]{1,80}$"#, options: .regularExpression) != nil
    }

    private func basename(_ name: String) -> String {
        name.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init)?.precomposedStringWithCanonicalMapping.lowercased() ?? ""
    }

    private func isRealDebridLink(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, url.port == nil else { return false }
        return host.range(of: #"^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+download\.real-debrid\.com$"#, options: .regularExpression) != nil ||
               (host == "real-debrid.com" && url.path.hasPrefix("/d/"))
    }
}
