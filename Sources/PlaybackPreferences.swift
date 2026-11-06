import Foundation

enum PlaybackPreferences {
    static let appSettingKeys = ["cast.series.autoplay","cast.series.autoplayDelay","cast.series.matchSource","cast.series.specials","cast.series.webFallback","cast.series.autoReturn","cast.series.sourceAttempts","cast.preferred.audio","cast.preferred.subtitle","cast.preferred.subtitleSource"]
    static func resetAppSettings(defaults:UserDefaults = .standard) {
        for key in appSettingKeys { defaults.removeObject(forKey:key) }
    }
    static let autoplayDelays = [0,5,10,15]
    static func autoplayDelay(defaults:UserDefaults = .standard)->Int {
        guard let number=defaults.object(forKey:"cast.series.autoplayDelay") as? NSNumber else{return 0}
        let seconds=number.doubleValue
        return seconds.isFinite && autoplayDelays.contains(where:{Double($0)==seconds}) ? Int(seconds):0
    }
    static func sourceAttempts(defaults:UserDefaults = .standard)->Int {
        let n=(defaults.object(forKey:"cast.series.sourceAttempts") as? NSNumber)?.intValue ?? 3
        return (1...3).contains(n) ? n:3
    }
    static let controlSettingKeys=["cast.activity.enabled","cast.controls.seekStep"]
    static let seekSteps:[Double]=[10,15,30,60]
    static func seekStep(defaults:UserDefaults = .standard)->Double {
        let value=defaults.object(forKey:"cast.controls.seekStep") as? NSNumber
        let seconds=value?.doubleValue ?? 30
        return seconds.isFinite && seekSteps.contains(seconds) ? seconds:30
    }
    static func resetControls(defaults:UserDefaults = .standard) {
        for key in controlSettingKeys{defaults.removeObject(forKey:key)}
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
    static func partialSubtitle(_ label:String)->Bool {
        label.range(of:#"\b(forced|signs|songs)\b"#,options:[.regularExpression,.caseInsensitive]) != nil
    }
    static func subtitleDetail(_ track:RDTrack)->String? {
        let text=String(track.label.trimmingCharacters(in:.whitespacesAndNewlines).prefix(160))
        let code=language(track.language)
        let generic=[track.language,code,"und",Locale(identifier:"en").localizedString(forLanguageCode:code) ?? "",Locale(identifier:"it").localizedString(forLanguageCode:code) ?? ""]
        return text.isEmpty || generic.contains(where:{$0.caseInsensitiveCompare(text) == .orderedSame}) ? nil:text
    }
    static func subtitle(_ tracks:[RDTrack],external:Bool,handoff:String?,externalLanguage:String? = nil,defaults:UserDefaults = .standard) -> String {
        let raw = defaults.string(forKey:"cast.preferred.subtitle")
        let saved = raw == "auto" ? nil : raw
        if saved == "none" || (saved == nil && handoff == "off") { return "none" }
        let wanted = language(saved ?? handoff ?? "en")
        let rawSource=defaults.string(forKey:"cast.preferred.subtitleSource") ?? "internal"
        let source=["internal","external","externalOnly"].contains(rawSource) ? rawSource:"internal"
        let matchingExternal=external && wanted == language(externalLanguage ?? handoff ?? "en")
        if source != "internal",matchingExternal{return "external"}
        if source=="externalOnly"{return "none"}
        let candidates=tracks.filter{language($0.language)==wanted}
        let complete=candidates.first{!partialSubtitle($0.label)}
        if let track=complete ?? candidates.first{return track.key}
        return matchingExternal ? "external":"none"
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
    // Stremio Core Video accepts `name` as an alias and defaults a missing
    // title to empty; one untitled video must not reject the entire catalogue.
    // MIT attribution: ThirdPartyNotices/Stremio-Core.txt.
    enum CodingKeys:String,CodingKey {case id,title,name,season,episode,released}
    init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        id=try c.decode(String.self,forKey:.id)
        title=try c.decodeIfPresent(String.self,forKey:.title) ?? c.decodeIfPresent(String.self,forKey:.name) ?? ""
        season=try c.decodeIfPresent(Int.self,forKey:.season)
        episode=try c.decodeIfPresent(Int.self,forKey:.episode)
        released=try c.decodeIfPresent(String.self,forKey:.released)
    }
    var label:String { "S\(season ?? 0) E\(episode ?? 0)"+(title.isEmpty ? "":" · \(title)") }
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
        }.sorted {
            // Stremio Core VideoSortedVecAdapter places season zero last.
            if ($0.season==0) != ($1.season==0) {return $0.season != 0}
            return ($0.season!,$0.episode!) < ($1.season!,$1.episode!)
        }
    }
    static func target(_ videos:[SeriesEpisode],current:String,id:String)->SeriesEpisode? {
        guard id != current,let series=seriesID(current),seriesID(id)==series else{return nil}
        return videos.first{$0.id==id}
    }
    static func adjacent(_ videos:[SeriesEpisode],current:String,direction:Int) -> SeriesEpisode? {
        guard [-1,1].contains(direction),let index=videos.firstIndex(where:{$0.id==current}),
              videos.indices.contains(index+direction) else{return nil}
        return videos[index+direction]
    }
    /// Mirror Stremio's next_video boundary: normal seasons never autoplay
    /// into season-zero extras. Manual navigation remains available.
    static func autoplayNext(_ videos:[SeriesEpisode],current:String,at now:Date=Date()) -> SeriesEpisode? {
        guard let index=videos.firstIndex(where:{$0.id==current}),
              let next=adjacent(videos,current:current,direction:1),next.aired(at:now),
              next.season != 0 || videos[index].season == 0 else{return nil}
        return next
    }
    static func stremioURL(videoID:String,web:Bool) -> URL? {
        guard let series=seriesID(videoID) else{return nil}
        let base=web ? "https://web.stremio.com/#/detail/series/" : "stremio:///detail/series/"
        return URL(string:base+series+"/"+videoID)
    }
}

struct AutoplayRetryPlan {
    static func permits(status:Int)->Bool { ![401,403,429,451].contains(status) }
    private let ids:[String]
    private var cursor=0
    var attempt:Int {cursor}
    var limit:Int {ids.count}
    init(_ candidates:[String],limit:Int=3) {
        var seen=Set<String>()
        ids=Array(candidates.filter{!$0.isEmpty && seen.insert($0).inserted}.prefix(max(1,min(3,limit))))
    }
    mutating func next()->String? {
        guard ids.indices.contains(cursor) else{return nil}
        defer{cursor+=1};return ids[cursor]
    }
}


/// Only build first-party Stremio destinations, never an arbitrary return URL.
enum StremioReturnLink {
    static func url(type:String?,id:String?,web:Bool)->URL {
        let root=web ? "https://web.stremio.com/":"stremio:///"
        guard let type,let id,id.count<=100 else{return URL(string:root)!}
        let path:String
        if type=="series",let series=SeriesNavigation.seriesID(id) {
            path="series/"+series+"/"+id
        } else if type=="movie",id.range(of:"^tt[0-9]+$",options:.regularExpression) != nil {
            path="movie/"+id
        } else {return URL(string:root)!}
        return URL(string:(web ? "https://web.stremio.com/#/detail/":"stremio:///detail/")+path)!
    }
}

/// Monotonic deadline: wall-clock changes and delayed wakes cannot extend the wait.
/// Controller owns cancellation and consumes the pending request before launching.
struct EpisodeAutoplayWait {
    let sourceID:String
    let targetID:String
    let deadline:TimeInterval
    init(sourceID:String,targetID:String,delay:Int,now:TimeInterval) {
        self.sourceID=sourceID;self.targetID=targetID
        deadline=now+Double(PlaybackPreferences.autoplayDelays.contains(delay) ? delay:0)
    }
    func remaining(at now:TimeInterval)->Int {
        guard now.isFinite,deadline.isFinite else{return 0}
        return Int(ceil(max(0,min(15,deadline-now))))
    }
    func matches(current:String,next:String?,enabled:Bool)->Bool {
        enabled && current==sourceID && next==targetID
    }
}

