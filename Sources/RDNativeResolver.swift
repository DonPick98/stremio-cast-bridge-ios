import Foundation
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
    case invalidConfiguration, invalidFile, fileNotIdentified, fileNotReady
    case unavailable, invalidResponse, invalidTrack, invalidStream, http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "La configurazione Real-Debrid non è valida."
        case .invalidFile: return "Il file selezionato non può essere identificato."
        case .fileNotIdentified: return "Non riesco a trovare esattamente il file scelto."
        case .fileNotReady: return "Real-Debrid sta ancora preparando il file. Riprova tra poco."
        case .unavailable: return "Il file non è disponibile su Real-Debrid."
        case .invalidResponse: return "Real-Debrid ha restituito una risposta non valida."
        case .invalidTrack: return "La traccia scelta non è disponibile."
        case .invalidStream: return "Il collegamento video ricevuto non è valido."
        case .http(let code): return "Real-Debrid ha risposto con errore \(code)."
        }
    }
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

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func prepare(torrentHash: String, filename: String, videoSize: Int64? = nil) async throws -> RDPreparedMedia {
        guard torrentHash.range(of: #"^[a-fA-F0-9]{40}$"#, options: .regularExpression) != nil,
              !filename.isEmpty, filename.count <= 500 else { throw RDResolverError.invalidFile }
        let added = try await api("torrents/addMagnet", form: ["magnet": "magnet:?xt=urn:btih:\(torrentHash)"])
        guard let id = added["id"] as? String, validID(id) else { throw RDResolverError.invalidResponse }
        let infoPath = "torrents/info/\(id)"
        var info = try await api(infoPath)
        let wanted = basename(filename)
        guard !wanted.isEmpty, let files = info["files"] as? [[String: Any]] else { throw RDResolverError.invalidResponse }
        var matches = files.filter { basename($0["path"] as? String ?? "") == wanted }
        if matches.count > 1, let videoSize = videoSize {
            matches = matches.filter { ($0["bytes"] as? NSNumber)?.int64Value == videoSize }
        }
        guard matches.count == 1, let targetID = (matches[0]["id"] as? NSNumber)?.intValue, targetID > 0 else {
            throw RDResolverError.fileNotIdentified
        }
        if (matches[0]["selected"] as? NSNumber)?.intValue != 1 {
            _ = try await api("torrents/selectFiles/\(id)", form: ["files": String(targetID)])
            info = try await api(infoPath)
        }
        for _ in 0..<10 {
            let status = info["status"] as? String ?? ""
            if status == "downloaded" { break }
            if ["magnet_error", "error", "virus", "dead"].contains(status) { throw RDResolverError.unavailable }
            try await Task.sleep(nanoseconds: 1_200_000_000)
            info = try await api(infoPath)
        }
        guard info["status"] as? String == "downloaded" else { throw RDResolverError.fileNotReady }
        guard let finalFiles = info["files"] as? [[String: Any]], let links = info["links"] as? [String] else {
            throw RDResolverError.invalidResponse
        }
        let selected = finalFiles.filter { ($0["selected"] as? NSNumber)?.intValue == 1 }
        guard selected.count == links.count,
              let index = selected.firstIndex(where: { ($0["id"] as? NSNumber)?.intValue == targetID }),
              let link = URL(string: links[index]) else { throw RDResolverError.invalidResponse }
        return try await prepare(directLink: link)
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
        guard (200..<300).contains(http.statusCode) else { throw RDResolverError.http(http.statusCode) }
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

