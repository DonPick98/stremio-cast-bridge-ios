import Foundation

enum SubtitleLanguage {
    static func code(_ value:String) -> String {
        let v = value.lowercased().split(separator:"-").first.map(String.init) ?? value.lowercased()
        return ["italian":"it","english":"en","french":"fr","german":"de","spanish":"es","ita":"it","eng":"en","fra":"fr","fre":"fr","spa":"es","deu":"de","ger":"de","jpn":"ja","por":"pt","zho":"zh","chi":"zh","rus":"ru","kor":"ko","nld":"nl","dut":"nl"][v] ?? v
    }
    static func name(_ value:String) -> String { Locale.current.localizedString(forLanguageCode:code(value))?.capitalized ?? value }
}

struct OnlineSubtitle:Decodable, Identifiable, Equatable {
    let id:String
    let url:URL
    let lang:String
    var label:String? = nil
    var subtitleFileName:String? = nil
    var movieReleaseName:String? = nil
    var releaseGroup:String? = nil
    var releaseFormat:String? = nil
    var fpsMilli:Int? = nil
    var provider:String? = nil
    var title:String { String((subtitleFileName ?? movieReleaseName ?? label ?? "Versione \(id)").prefix(300)) }
    var detail:String { String([movieReleaseName,releaseFormat,fpsMilli.map{String(format:"%.3f fps",Double($0)/1000)}].compactMap{$0}.filter{!$0.isEmpty}.joined(separator:" · ").prefix(400)) }
    static func safeURL(_ url:URL) -> URL? {
        var candidate = url
        if url.host == "127.0.0.1", url.port == 11470, url.path == "/subtitles.vtt",
           let raw = URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first(where:{$0.name == "from"})?.value, let inner = URL(string:raw) { candidate = inner }
        guard candidate.scheme == "https", candidate.host != nil, candidate.user == nil, candidate.password == nil else { return nil }
        return candidate
    }
    func score(filename:String?,fps:Double) -> Int {
        guard let filename else { return 0 }
        func words(_ text:String) -> Set<String> { Set(text.lowercased().components(separatedBy:CharacterSet.alphanumerics.inverted).filter{$0.count >= 3}) }
        let source = words(filename), release = words(title + " " + (movieReleaseName ?? ""))
        var score = source.intersection(release).count * 10
        func episode(_ text:String) -> [Int]? {
            let r = try! NSRegularExpression(pattern:#"(?i)(?:s(\d{1,2})e(\d{1,3})|\b(\d{1,2})x(\d{1,3})\b)"#)
            let ns = text as NSString
            guard let m = r.firstMatch(in:text,range:NSRange(location:0,length:ns.length)) else { return nil }
            let pair = m.range(at:1).location != NSNotFound ? [1,2] : [3,4]
            return pair.compactMap{Int(ns.substring(with:m.range(at:$0)))}
        }
        if let a = episode(filename), let b = episode(title) { score += a == b ? 100 : -1000 }
        if let fpsMilli, fps > 0, abs(Double(fpsMilli)/1000-fps) < 0.05 { score += 5 }
        return score
    }
}

enum SubtitleCatalogError:LocalizedError {
    case identity, response, http(Int), limited(Int)
    var errorDescription:String? {
        switch self {
        case .identity: return "Questo contenuto non ha un identificativo utilizzabile da OpenSubtitles."
        case .response: return "OpenSubtitles ha restituito un elenco non leggibile."
        case .http(let code): return "OpenSubtitles non è disponibile in questo momento (HTTP \(code))."
        case .limited(let seconds): return "OpenSubtitles limita le richieste. Riprova tra \(seconds) secondi."
        }
    }
}

enum SubtitleCatalog {
    static func sourceURL(_ subtitles:[OnlineSubtitle],language:String,fallback:URL?,fallbackLanguage:String?) -> URL? {
        let wanted=SubtitleLanguage.code(language)
        guard !["none","off","und", ""].contains(wanted) else{return nil}
        for subtitle in subtitles where SubtitleLanguage.code(subtitle.lang)==wanted {
            if let url=OnlineSubtitle.safeURL(subtitle.url){return url}
        }
        guard let fallback,SubtitleLanguage.code(fallbackLanguage ?? "en")==wanted else{return nil}
        return OnlineSubtitle.safeURL(fallback)
    }
    static func requestURL(type:String,id:String,filename:String?,size:Int64?,hash:String?) throws -> URL {
        guard ["movie","series"].contains(type), id.range(of:#"^tt[0-9]+(?::[0-9]+:[0-9]+)?$"#,options:.regularExpression) != nil else { throw SubtitleCatalogError.identity }
        var extra:[URLQueryItem] = []
        if let hash, hash.range(of:#"^[0-9a-fA-F]{16}$"#,options:.regularExpression) != nil { extra.append(URLQueryItem(name:"videoHash",value:hash.lowercased())) }
        if let size, size > 0 { extra.append(URLQueryItem(name:"videoSize",value:String(size))) }
        if let filename, !filename.isEmpty { extra.append(URLQueryItem(name:"filename",value:String(filename.prefix(500)))) }
        var query = URLComponents(); query.queryItems = extra
        let base = URL(string:"https://opensubtitles-v3.strem.io")!.appendingPathComponent("subtitles").appendingPathComponent(type).appendingPathComponent(id)
        if extra.isEmpty { return base.appendingPathExtension("json") }
        // Add-on extra arguments occupy one path segment, not the URL query.
        return base.appendingPathComponent((query.percentEncodedQuery ?? "") + ".json")
    }
    static func decode(_ data:Data,filename:String?,fps:Double) throws -> [OnlineSubtitle] {
        struct Response:Decodable { let subtitles:[OnlineSubtitle] }
        guard data.count <= 2_097_152, let response = try? JSONDecoder().decode(Response.self,from:data) else { throw SubtitleCatalogError.response }
        var seen:Set<String> = []
        return response.subtitles.prefix(500).filter { OnlineSubtitle.safeURL($0.url) != nil && seen.insert($0.id+"|"+$0.lang).inserted }
            .enumerated().sorted { let a = $0.element.score(filename:filename,fps:fps), b = $1.element.score(filename:filename,fps:fps); return a == b ? $0.offset < $1.offset : a > b }.map(\.element)
    }
    static func search(type:String,id:String,filename:String?,size:Int64?,hash:String?,fps:Double) async throws -> [OnlineSubtitle] {
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 15
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        let session = URLSession(configuration:config); defer { session.invalidateAndCancel() }
        let url = try requestURL(type:type,id:id,filename:filename,size:size,hash:hash)
        let (bytes,response) = try await session.bytes(from:url)
        guard let http = response as? HTTPURLResponse else { throw SubtitleCatalogError.response }
        if http.statusCode == 429 { throw SubtitleCatalogError.limited(min(3600,max(1,Int(http.value(forHTTPHeaderField:"Retry-After") ?? "60") ?? 60))) }
        guard http.statusCode == 200 else { throw SubtitleCatalogError.http(http.statusCode) }
        var data = Data()
        for try await byte in bytes { guard data.count < 2_097_152 else { throw SubtitleCatalogError.response }; data.append(byte) }
        return try decode(data,filename:filename,fps:fps)
    }
    static func hash(first:Data,last:Data,size:Int64) -> String? {
        guard first.count == 65536, last.count == 65536, size >= 131072 else { return nil }
        var value = UInt64(size)
        for data in [first,last] {
            let b = [UInt8](data)
            for i in stride(from:0,to:b.count,by:8) { var word:UInt64 = 0; for j in 0..<8 { word |= UInt64(b[i+j]) << (8*j) }; value = value &+ word }
        }
        return String(format:"%016llx",value)
    }
}

struct SubtitleWindow {
    let center:Double
    static func normalized(_ value:Double) -> Double { value.isFinite ? (min(300,max(-300,value))*2).rounded()/2 : 0 }
    init(center:Double) { self.center = Self.normalized(center) }
    func identifier(kind:Int,delay:Double) -> Int? {
        let delta = Int(((Self.normalized(delay)-center)*2).rounded())
        guard abs(delta) <= 10 else { return nil }
        return delta == 0 ? kind : kind*10000 + delta+10
    }
    func variants(kind:Int) -> [(id:Int,delay:Double)] {
        (-10...10).compactMap { step in
            let delay = center+Double(step)/2
            guard (-300.0...300.0).contains(delay), let id = identifier(kind:kind,delay:delay) else { return nil }
            return (id,delay)
        }
    }
    static func kind(_ id:Int) -> Int { id < 10000 ? id : id/10000 }
}
