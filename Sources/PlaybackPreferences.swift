import Foundation

enum PlaybackPreferences {
    static func language(_ value:String) -> String {
        let code = value.lowercased().split(separator:"-").first.map(String.init) ?? value.lowercased()
        return ["eng":"en","ita":"it","fra":"fr","fre":"fr","deu":"de","ger":"de","spa":"es","jpn":"ja","kor":"ko","por":"pt","zho":"zh","chi":"zh","rus":"ru","ukr":"uk","ara":"ar","heb":"he","hin":"hi","pol":"pl","nld":"nl","dut":"nl","tur":"tr" ][code] ?? code
    }
    static func audio(_ tracks:[RDTrack],fallback:String,defaults:UserDefaults = .standard) -> String {
        guard let wanted = defaults.string(forKey:"cast.preferred.audio") else { return fallback }
        return tracks.first(where:{language($0.language) == wanted})?.key ?? fallback
    }
    static func remember(audio:RDTrack?,subtitle:String?,defaults:UserDefaults = .standard) {
        if let audio, language(audio.language) != "und" { defaults.set(language(audio.language),forKey:"cast.preferred.audio") }
        if let subtitle, language(subtitle) != "und" { defaults.set(subtitle == "none" ? "none" : language(subtitle),forKey:"cast.preferred.subtitle") }
    }
    static func subtitle(_ tracks:[RDTrack],external:Bool,handoff:String?,defaults:UserDefaults = .standard) -> String {
        let saved = defaults.string(forKey:"cast.preferred.subtitle")
        if saved == "none" || (saved == nil && handoff == "off") { return "none" }
        let wanted = language(saved ?? handoff ?? "en")
        if external && wanted == language(handoff ?? "en") { return "external" }
        if let track = tracks.first(where:{language($0.language) == wanted}) { return track.key }
        return external && wanted == language(handoff ?? "en") ? "external" : "none"
    }
}

enum MediaDisplayTitle {
    static func clean(_ value:String) -> String {
        var text = value.replacingOccurrences(of:#"\.(mkv|mp4|m4v|avi|webm|mov|ts)$"#,with:"",options:[.regularExpression,.caseInsensitive])
        text = text.replacingOccurrences(of:#"^\[[^\]]+\]\s*"#,with:"",options:.regularExpression)
        let episode = try? NSRegularExpression(pattern:#"(?i)\bS(\d{1,2})E(\d{1,3})\b"#)
        let range = NSRange(text.startIndex...,in:text)
        var suffix = ""
        if let match = episode?.firstMatch(in:text,range:range), let whole = Range(match.range,in:text),
           let season = Range(match.range(at:1),in:text), let number = Range(match.range(at:2),in:text) {
            suffix = " · S\(Int(text[season]) ?? 1) E\(Int(text[number]) ?? 1)"
            text = String(text[..<whole.lowerBound])
        }
        text = text.replacingOccurrences(of:#"(?i)[. _-](2160p|1080p|720p|480p|WEB[. _-]?DL|WEBRip|BluRay|BDRemux|BRRip|HDR10|HEVC|x26[45]|H[.]?26[45])\b.*$"#,with:"",options:.regularExpression)
        text = text.replacingOccurrences(of:"[._]+",with:" ",options:.regularExpression).trimmingCharacters(in:CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn:"-")))
        text = text.replacingOccurrences(of:"\\s+",with:" ",options:.regularExpression)
        return text.isEmpty ? "Video da Stremio" : text+suffix
    }
}
