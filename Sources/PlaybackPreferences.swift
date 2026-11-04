import Foundation

enum PlaybackPreferences {
    static let skipIntervals = [10,15,30,60]
    static func skipInterval(defaults:UserDefaults = .standard) -> Int {
        let value=defaults.integer(forKey:"cast.player.skipSeconds")
        return skipIntervals.contains(value) ? value:30
    }
    static let appSettingKeys = ["cast.series.autoplay","cast.series.matchSource","cast.series.specials","cast.series.webFallback","cast.preferred.audio","cast.preferred.subtitle","cast.player.skipSeconds"]
    static func resetAppSettings(defaults:UserDefaults = .standard) {
        for key in appSettingKeys { defaults.removeObject(forKey:key) }
    }
    static func language(_ value:String) -> String {
        let code = value.lowercased().split(separator:"-").first.map(String.init) ?? value.lowercased()
        return ["eng":"en","ita":"it","fra":"fr","fre":"fr","deu":"de","ger":"de","spa":"es","jpn":"ja","kor":"ko","por":"pt","zho":"zh","chi":"zh","rus":"ru","ukr":"uk","ara":"ar","heb":"he","hin":"hi","pol":"pl","nld":"nl","dut":"nl","tur":"tr" ][code] ?? code
    }
    static func audio(_ tracks:[RDTrack],fallback:String,defaults:UserDefaults = .standard) -> String {
        guard let wanted = defaults.string(forKey:"cast.preferred.audio"), wanted != "auto" else { return fallback }
        return tracks.first(where:{language($0.language) == wanted})?.key ?? fallback
    }
    static func remember(audio:RDTrack?,subtitle:String?,defaults:UserDefaults = .standard) {
        if let audio, language(audio.language) != "und" { defaults.set(language(audio.language),forKey:"cast.preferred.audio") }
        if let subtitle, language(subtitle) != "und" { defaults.set(subtitle == "none" ? "none" : language(subtitle),forKey:"cast.preferred.subtitle") }
    }
    static func subtitlesRequested(handoff:String?,defaults:UserDefaults = .standard) -> Bool {
        let saved=defaults.string(forKey:"cast.preferred.subtitle")
        if saved=="none" {return false}
        if saved==nil || saved=="auto" {return handoff != "off"}
        return true
    }
    static func subtitleLanguage(handoff:String?,defaults:UserDefaults = .standard) -> String {
        let saved=defaults.string(forKey:"cast.preferred.subtitle")
        if let saved, !["auto","none"].contains(saved) {return language(saved)}
        return language(handoff=="off" ? "en":handoff ?? "en")
    }
    static func subtitle(_ tracks:[RDTrack],external:Bool,handoff:String?,externalLanguage:String? = nil,defaults:UserDefaults = .standard) -> String {
        let raw = defaults.string(forKey:"cast.preferred.subtitle")
        let saved = raw == "auto" ? nil : raw
        if saved == "none" || (saved == nil && handoff == "off") { return "none" }
        let wanted = language(saved ?? handoff ?? "en")
        if let track = tracks.first(where:{language($0.language) == wanted}) { return track.key }
        return external && wanted == language(externalLanguage ?? handoff ?? "en") ? "external" : "none"
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



struct SeriesEpisode: Decodable, Identifiable, Equatable {
    let id:String
    let title:String
    let season:Int?
    let episode:Int?
    let released:String?
    var label:String { "S\(season ?? 0) E\(episode ?? 0) · \(title)" }
    func aired(at now:Date = Date()) -> Bool {
        guard let released else { return false }
        let iso=ISO8601DateFormatter()
        iso.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        let date=iso.date(from:released) ?? ISO8601DateFormatter().date(from:released)
        return date.map{$0 <= now} ?? false
    }
}
enum SeriesNavigation {
    static func seriesID(_ videoID:String) -> String? {
        let parts=videoID.split(separator:":",omittingEmptySubsequences:false)
        guard parts.count==3,parts[0].range(of:#"^tt[0-9]+$"#,options:.regularExpression) != nil,
              let season=Int(parts[1]),season>=0,let episode=Int(parts[2]),episode>=0 else{return nil}
        return String(parts[0])
    }
    static func ordered(_ videos:[SeriesEpisode],series:String,includeSpecials:Bool) -> [SeriesEpisode] {
        var seen=Set<String>()
        return videos.filter {
            guard seriesID($0.id)==series,let season=$0.season,let episode=$0.episode,
                  season>=0,episode>=0,(includeSpecials || season>0),
                  $0.id=="\(series):\(season):\(episode)" else{return false}
            return seen.insert($0.id).inserted
        }.sorted { ($0.season!,$0.episode!) < ($1.season!,$1.episode!) }
    }
    static func adjacent(_ videos:[SeriesEpisode],current:String,direction:Int) -> SeriesEpisode? {
        guard [-1,1].contains(direction),let index=videos.firstIndex(where:{$0.id==current}),
              videos.indices.contains(index+direction) else{return nil}
        return videos[index+direction]
    }
    static func stremioURL(videoID:String,web:Bool) -> URL? {
        guard let series=seriesID(videoID) else{return nil}
        let base=web ? "https://web.stremio.com/#/detail/series/" : "stremio:///detail/series/"
        return URL(string:base+series+"/"+videoID)
    }
}
