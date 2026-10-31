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

