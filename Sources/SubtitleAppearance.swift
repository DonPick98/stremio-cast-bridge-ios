import Foundation

struct SubtitleAppearance: Codable, Equatable {
    var scale: Double = 1.1
    var color: String = "white"
    var background: Double = 0.35
    var outline: Bool = true
    var font: String = "sans"
    static let key = "cast.subtitle.appearance"
    var normalized: Self {
        var copy = self
        copy.scale = scale.isFinite ? min(2,max(0.6,scale)) : 1.1
        copy.background = background.isFinite ? min(1,max(0,background)) : 0.35
        if !["white","yellow","cyan","green"].contains(color) { copy.color = "white" }
        if !["sans","serif","mono"].contains(font) { copy.font = "sans" }
        return copy
    }
    static func load(defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey:key), let value = try? JSONDecoder().decode(Self.self,from:data) else { return Self() }
        return value.normalized
    }
    func save(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(normalized) { defaults.set(data,forKey:Self.key) }
    }
}

enum SourceFileSize {
    static func label(bytes: Int64?, description: String) -> String? {
        if let bytes, bytes > 0 {
            let formatter = ByteCountFormatter(); formatter.countStyle = .file
            formatter.allowedUnits = [.useKB,.useMB,.useGB,.useTB]
            return formatter.string(fromByteCount:bytes)
        }
        // Provider descriptions often give file size followed by batch size.
        // Only the first size is shown, preserving the provider's unit.
        let batchPattern = #"(?i)(\d+(?:[.,]\d+)?)\s*/\s*\d+(?:[.,]\d+)?\s*(KiB|MiB|GiB|TiB|KB|MB|GB|TB)\b"#
        if let regex = try? NSRegularExpression(pattern:batchPattern), let match = regex.firstMatch(in:description,range:NSRange(description.startIndex...,in:description)),
           let number = Range(match.range(at:1),in:description), let unit = Range(match.range(at:2),in:description) {
            return String(description[number]) + " " + String(description[unit]).uppercased()
        }
        let pattern = #"(?i)(\d+(?:[.,]\d+)?)\s*(KiB|MiB|GiB|TiB|KB|MB|GB|TB)\b"#
        guard let regex = try? NSRegularExpression(pattern:pattern),
              let match = regex.firstMatch(in:description,range:NSRange(description.startIndex...,in:description)),
              let range = Range(match.range,in:description) else { return nil }
        return String(description[range]).uppercased()
    }
}



/// Ranks available sources without hiding any or guessing missing metadata.
enum SourcePreferences {
    static let keys=["cast.sources.order","cast.sources.resolution"]
    static func reset(defaults:UserDefaults = .standard){keys.forEach{defaults.removeObject(forKey:$0)}}
    static func resolution(_ text:String)->Int? {
        guard let regex=try? NSRegularExpression(pattern:"(?i)(?<![A-Za-z0-9])(480|720|1080|1440|2160|4320)p(?![A-Za-z0-9])") else{return nil}
        let ns=text as NSString
        let heights=Set(regex.matches(in:text,range:NSRange(location:0,length:ns.length)).compactMap{Int(ns.substring(with:$0.range(at:1)))})
        return heights.count==1 ? heights.first:nil
    }
    static func ordered<T>(_ values:[T],defaults:UserDefaults = .standard,metadata:(T)->(resolution:Int?,bytes:Int64?))->[T] {
        let raw=defaults.integer(forKey:"cast.sources.resolution")
        let preferred=[720,1080,2160].contains(raw) ? raw:0
        let rawOrder=defaults.string(forKey:"cast.sources.order") ?? "addon"
        let order=["small","large"].contains(rawOrder) ? rawOrder:"addon"
        if preferred==0 && order=="addon"{return values}
        let ranked=values.enumerated().map{index,value in
            let item=metadata(value),height=item.resolution
            let tier=preferred==0 ? 0:height.map{$0<=preferred ? 0:2} ?? 1
            let heightKey=preferred==0 ? 0:height.map{$0<=preferred ? -$0:$0} ?? 0
            let bytes=item.bytes.flatMap{$0>0 ? $0:nil}
            let missing=order=="addon" ? 0:bytes==nil ? 1:0
            let sizeKey:Int64=order=="addon" ? 0:order=="large" ? -(bytes ?? 0):bytes ?? 0
            return (value:value,key:(tier,heightKey,missing,sizeKey,index))
        }
        return ranked.sorted{$0.key<$1.key}.map(\.value)
    }
}
