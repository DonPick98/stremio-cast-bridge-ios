import Foundation

enum SubtitleError: LocalizedError {
    case unsupported, malformed, limit, network, noTrack, noService
    var errorDescription: String? {
        switch self {
        case .unsupported: return "Questo file non offre un indice sottotitoli testuali utilizzabile."
        case .malformed: return "L’indice dei sottotitoli non è valido."
        case .limit: return "Estrazione troppo lunga o troppo grande per questo file."
        case .network: return "Non riesco a leggere le parti necessarie del file."
        case .noTrack: return "Nessuna traccia testuale nella lingua richiesta."
        case .noService: return "Configura un servizio sottotitoli per usarli sulla TV."
        }
    }
}

/// Reads small, validated ranges on the phone's connection, never the whole movie.
actor SubtitleRangeReader {
    private let url: URL
    private let session = URLSession(configuration: .ephemeral)
    private var requested = 0
    private var calls = 0
    private let deadline = Date().addingTimeInterval(180)
    init(url: URL) throws {
        guard url.scheme == "https", url.host?.hasSuffix(".download.real-debrid.com") == true,
              url.user == nil, url.password == nil, url.port == nil else { throw SubtitleError.network }
        self.url = url
    }
    func close() { session.invalidateAndCancel() }
    func read(_ offset: Int, _ count: Int) async throws -> Data {
        try Task.checkCancellation()
        guard offset >= 0, offset < 1 << 50, count > 0, count <= 4_194_304 else { throw SubtitleError.limit }
        requested += count; calls += 1
        guard requested <= 32_000_000, calls <= 6000, Date() < deadline else { throw SubtitleError.limit }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("bytes=\(offset)-\(offset + count - 1)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 206,
              http.url?.host?.hasSuffix(".download.real-debrid.com") == true,
              let range = http.value(forHTTPHeaderField: "Content-Range"),
              range.hasPrefix("bytes \(offset)-\(offset + count - 1)/") else { throw SubtitleError.network }
        var data = Data(); data.reserveCapacity(count)
        for try await byte in bytes {
            if data.count >= count { throw SubtitleError.network }
            data.append(byte)
        }
        guard data.count == count else { throw SubtitleError.network }
        return data
    }
}

struct MkvSubtitleExtractor {
    typealias Reader = (Int, Int) async throws -> Data
    struct Element { let id: Int; let size: Int?; let data: Int; let header: Int }
    struct Track { let id: Int; let codec: String; let language: String; let name: String }
    struct Cue { let time: Int; let cluster: Int; let relative: Int; let duration: Int? }
    static func vint(_ b: [UInt8], _ p: Int, id: Bool = false) throws -> (Int?, Int) {
        guard p >= 0, p < b.count, b[p] != 0 else { throw SubtitleError.malformed }
        var mask: UInt8 = 128; var n = 1
        while b[p] & mask == 0 { mask >>= 1; n += 1 }
        guard n <= (id ? 4 : 8), p + n <= b.count else { throw SubtitleError.malformed }
        var value = UInt64(id ? b[p] : b[p] & (mask - 1))
        for j in 1..<n { value = value << 8 | UInt64(b[p+j]) }
        if !id && value == (UInt64(1) << (7*n)) - 1 { return (nil, n) }
        guard value < 1 << 50 else { throw SubtitleError.limit }
        return (Int(value), n)
    }
    static func header(_ b: [UInt8], _ p: Int = 0) throws -> Element {
        let (id,n) = try vint(b,p,id:true), (size,m) = try vint(b,p+n)
        guard let id else { throw SubtitleError.malformed }
        return Element(id:id,size:size,data:p+n+m,header:n+m)
    }
    static func children(_ b: [UInt8], _ start: Int = 0, _ end: Int? = nil) throws -> [Element] {
        let end = end ?? b.count
        guard start >= 0, end <= b.count, start <= end else { throw SubtitleError.malformed }
        var out: [Element] = []; var p = start
        while p < end {
            let h = try header(b,p)
            guard let size = h.size, size <= end-h.data else { throw SubtitleError.malformed }
            out.append(h); p = h.data + size
        }
        return out
    }
    static func number(_ b: [UInt8], _ e: Element?) throws -> Int {
        guard let e, let size = e.size, size <= 8, e.data+size <= b.count else { throw SubtitleError.malformed }
        var value: UInt64 = 0
        for j in e.data..<e.data+size { value = value << 8 | UInt64(b[j]) }
        guard value < 1 << 50 else { throw SubtitleError.limit }
        return Int(value)
    }
    static func string(_ b: [UInt8], _ e: Element?) -> String {
        guard let e, let size = e.size, e.data+size <= b.count else { return "" }
        return String(decoding:b[e.data..<e.data+size],as:UTF8.self)
    }
    static func element(_ read: Reader, _ at: Int, _ id: Int) async throws -> [UInt8] {
        let h = try header(Array(try await read(at,16)))
        guard h.id == id, let size = h.size, size > 0, size <= 4_194_304 else { throw SubtitleError.unsupported }
        return Array(try await read(at+h.header,size))
    }
    static func many(_ read: @escaping Reader, _ ranges: [(Int,Int)]) async throws -> [[UInt8]] {
        var result = Array(repeating:[UInt8](),count:ranges.count)
        for base in stride(from:0,to:ranges.count,by:8) {
            let end = min(base+8,ranges.count)
            try await withThrowingTaskGroup(of:(Int,[UInt8]).self) { group in
                for i in base..<end { let r = ranges[i]; group.addTask { (i,Array(try await read(r.0,r.1))) } }
                for try await (i,bytes) in group { result[i] = bytes }
            }
        }
        return result
    }
    /// Best effort for indexed text tracks. Does not scan/download video clusters.
    /// Cues are optional in MKV: a successful extraction cannot prove cue completeness.
    static func extract(read: @escaping Reader, language: String) async throws -> String {
        let first = Array(try await read(0,65536)), eb = try header(first)
        guard eb.id == 0x1a45dfa3, let ebSize = eb.size else { throw SubtitleError.unsupported }
        let seg = try header(first,eb.header+ebSize)
        guard seg.id == 0x18538067 else { throw SubtitleError.unsupported }
        let base = eb.header+ebSize+seg.header
        var locations: [Int:Int] = [:]; var p = base
        while p < first.count {
            let h = try header(first,p)
            guard let size = h.size, h.data+size <= first.count else { break }
            if h.id == 0x114d9b74 {
                for s in try children(first,h.data,h.data+size) where s.id == 0x4dbb {
                    let c = try children(first,s.data,s.data+s.size!)
                    let id = try number(first,c.first{$0.id == 0x53ab}), off = try number(first,c.first{$0.id == 0x53ac})
                    locations[id] = base+off
                }
            }
            if [0x1549a966,0x1654ae6b,0x1c53bb6b].contains(h.id) { locations[h.id] = p }
            if h.id == 0x1f43b675 { break }; p = h.data+size
        }
        guard let tracksAt = locations[0x1654ae6b], let cuesAt = locations[0x1c53bb6b] else { throw SubtitleError.unsupported }
        var scale = 1_000_000
        if let at = locations[0x1549a966] {
            let b = try await element(read,at,0x1549a966), c = try children(b)
            if let e = c.first(where:{$0.id == 0x2ad7b1}) { scale = try number(b,e) }
        }
        guard scale > 0, scale <= 1_000_000_000 else { throw SubtitleError.malformed }
        let t = try await element(read,tracksAt,0x1654ae6b)
        var tracks: [Track] = []
        for e in try children(t) where e.id == 0xae {
            let c = try children(t,e.data,e.data+e.size!)
            guard try number(t,c.first{$0.id == 0x83}) == 17 else { continue }
            let codec = string(t,c.first{$0.id == 0x86})
            guard ["S_TEXT/UTF8","S_TEXT/ASS","S_TEXT/SSA"].contains(codec), !c.contains(where:{$0.id == 0x6d80}) else { continue }
            let lang = string(t,c.first{$0.id == 0x22b59d})
            tracks.append(Track(id:try number(t,c.first{$0.id == 0xd7}),codec:codec,language:lang.isEmpty ? string(t,c.first{$0.id == 0x22b59c}) : lang,name:string(t,c.first{$0.id == 0x536e})))
        }
        let aliases = language == "it" ? ["it","ita"] : ["en","eng"]
        guard let track = tracks.first(where:{ aliases.contains($0.language.lowercased().components(separatedBy:"-")[0]) }) else { throw SubtitleError.noTrack }
        let b = try await element(read,cuesAt,0x1c53bb6b)
        var cues: [Cue] = []
        for e in try children(b) where e.id == 0xbb {
            let c = try children(b,e.data,e.data+e.size!), time = try number(b,c.first{$0.id == 0xb3})
            for q in c where q.id == 0xb7 {
                let z = try children(b,q.data,q.data+q.size!)
                if try number(b,z.first{$0.id == 0xf7}) != track.id { continue }
                guard let relative = z.first(where:{$0.id == 0xf0}) else { throw SubtitleError.unsupported }
                let d = try z.first(where:{$0.id == 0xb2}).map{try number(b,$0)}
                cues.append(Cue(time:time,cluster:base+(try number(b,z.first{$0.id == 0xf1})),relative:try number(b,relative),duration:d))
            }
        }
        guard !cues.isEmpty else { throw SubtitleError.unsupported }
        guard cues.count <= 1800 else { throw SubtitleError.limit }
        cues.sort{$0.time < $1.time}
        let offsets = Array(Set(cues.map(\.cluster)))
        let clusterHeads = try await many(read,offsets.map{($0,16)})
        var headers: [Int:Element] = [:]
        for (i,at) in offsets.enumerated() { let h = try header(clusterHeads[i]); guard h.id == 0x1f43b675 else { throw SubtitleError.malformed }; headers[at] = h }
        let positions = cues.map{$0.cluster+headers[$0.cluster]!.header+$0.relative}
        let heads = try await many(read,positions.map{($0,16)}).map{try header($0)}
        for h in heads { guard [0xa0,0xa3].contains(h.id), let n = h.size, n > 0, n <= 262144 else { throw SubtitleError.unsupported } }
        let packets = try await many(read,heads.enumerated().map{(positions[$0.offset]+$0.element.header,$0.element.size!)})
        var output = "WEBVTT\n\n"
        for (i,cue) in cues.enumerated() {
            let packet = packets[i]; var block = packet; var duration = cue.duration
            if heads[i].id == 0xa0 {
                let c = try children(packet)
                guard let e = c.first(where:{$0.id == 0xa1}) else { throw SubtitleError.malformed }
                block = Array(packet[e.data..<e.data+e.size!])
                if let d = c.first(where:{$0.id == 0x9b}) { duration = try number(packet,d) }
            }
            let (id,n) = try vint(block,0)
            guard id == track.id, block.count >= n+3, block[n+2]&6 == 0, let duration, duration > 0 else { throw SubtitleError.unsupported }
            let text = try clean(String(decoding:block.dropFirst(n+3),as:UTF8.self),codec:track.codec)
            if !text.isEmpty { output += "\(stamp(Double(cue.time)*Double(scale)/1e9)) --> \(stamp(Double(cue.time+duration)*Double(scale)/1e9))\n\(text)\n\n" }
            guard output.utf8.count <= 1_000_000 else { throw SubtitleError.limit }
        }
        guard output.contains("-->") else { throw SubtitleError.noTrack }
        return output
    }
    static func clean(_ value: String, codec: String) throws -> String {
        var text = value
        if codec != "S_TEXT/UTF8" {
            let fields = text.split(separator:",",maxSplits:8,omittingEmptySubsequences:false)
            guard fields.count == 9 else { throw SubtitleError.malformed }
            text = String(fields[8]).replacingOccurrences(of:#"\{[^}]*\}"#,with:"",options:.regularExpression).replacingOccurrences(of:"\\N",with:"\n").replacingOccurrences(of:"\\n",with:"\n").replacingOccurrences(of:"\\h",with:" ")
        }
        return text.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\r",with:"").replacingOccurrences(of:"\n\n+",with:"\n",options:.regularExpression)
    }
    static func stamp(_ seconds: Double) -> String {
        let ms = Int(max(0,seconds*1000).rounded())
        return String(format:"%02d:%02d:%02d.%03d",ms/3600000,(ms/60000)%60,(ms/1000)%60,ms%1000)
    }
}
