import Foundation

enum CaptionFailure:Error { case input,probe,track,unsupported,limit,timeout,process,network,cancelled }
enum CaptionFormat:String,Codable { case vtt,ass }
struct CaptionTrack:Equatable {
    let index:Int
    let ordinal:Int
    let codec:String
    let language:String
    let title:String
    var isText:Bool { ["subrip","srt","ass","ssa","webvtt","mov_text","text","ttml"].contains(codec) }
    var isASS:Bool { ["ass","ssa"].contains(codec) }
}
struct CaptionFont:Equatable { let index:Int; let kind:String }
struct CaptionFontData {let data:Data;let kind:String}
struct CaptionCatalog {
    let tracks:[CaptionTrack]
    let fonts:[CaptionFont]
    static func parse(_ data:Data) throws -> Self {
        guard data.count <= 2_097_152, let doc = try JSONSerialization.jsonObject(with:data) as? [String:Any],
              let streams = doc["streams"] as? [[String:Any]], streams.count <= 256 else { throw CaptionFailure.probe }
        var tracks:[CaptionTrack] = [], fonts:[CaptionFont] = []
        for stream in streams {
            guard let index = stream["index"] as? Int, index >= 0 else { continue }
            let codec = (stream["codec_name"] as? String ?? "unknown").lowercased()
            let tags = stream["tags"] as? [String:String] ?? [:]
            if stream["codec_type"] as? String == "subtitle" {
                tracks.append(CaptionTrack(index:index,ordinal:tracks.count,codec:codec,language:tags["language"] ?? "und",title:String((tags["title"] ?? "").prefix(160))))
            } else if stream["codec_type"] as? String == "attachment", fonts.count < 8 {
                let ext = ((tags["filename"] ?? "") as NSString).pathExtension.lowercased()
                if ["ttf","otf","woff","woff2"].contains(ext) { fonts.append(CaptionFont(index:index,kind:ext)) }
            }
        }
        return Self(tracks:tracks,fonts:fonts)
    }
    func selected(ordinal:Int,vlcID:Int?,language:String,codec:String) throws -> CaptionTrack {
        // Stream indices and subtitle ordinals are different namespaces. Check
        // a VLC/global ID only when its codec and language agree with the probe.
        let expected = ["subt":"subrip","srt":"subrip","ssa":"ass","utf8":"subrip","tx3g":"mov_text","wvtt":"webvtt","stpp":"ttml"][codec.lowercased()] ?? codec.lowercased()
        func matches(_ t:CaptionTrack) -> Bool {
            let sameLanguage = PlaybackPreferences.language(t.language) == PlaybackPreferences.language(language) || language == "und" || t.language == "und"
            return sameLanguage && (t.codec == expected || (t.isASS && expected == "ass"))
        }
        if let vlcID, let exact = tracks.first(where:{$0.index == vlcID && matches($0)}) { return exact }
        guard tracks.indices.contains(ordinal), matches(tracks[ordinal]) else { throw CaptionFailure.track }
        return tracks[ordinal]
    }
}
struct CaptionWindow:Equatable {
    let start:Double
    let end:Double
    init(position:Double,duration:Double) {
        let position = position.isFinite ? max(0,position) : 0
        start = max(0,(position-15).rounded(.down))
        end = duration.isFinite && duration > 0 ? min(duration,start+90) : start+90
    }
    func covers(_ position:Double) -> Bool { position >= start && position < end-1 }
}
struct CaptionSnapshot {
    let data:Data
    let format:CaptionFormat
    let start:Double
    let coveredUntil:Double
    let sourceComplete:Bool
    let fonts:[CaptionFontData]
}
enum CaptionDocument {
    // FFmpeg owns parsing and conversion. Publish only completed writes; an
    // empty but covered interval is valid and must not be called a failure.
    static func completePrefix(_ data:Data,format:CaptionFormat) throws -> Data? {
        guard data.count <= 2_097_152 else { throw CaptionFailure.limit }
        guard let last = data.lastIndex(of:10) else { return nil }
        var bytes = data.prefix(through:last)
        guard let text = String(data:bytes,encoding:.utf8) else { return nil }
        if format == .ass { guard text.contains("[Events]"), text.contains("Format:") else { return nil }; return Data(bytes) }
        guard text.hasPrefix("WEBVTT") else { return nil }
        if text.trimmingCharacters(in:.whitespacesAndNewlines) == "WEBVTT"{return Data("WEBVTT\n\n".utf8)}
        if let boundary = text.range(of:"\n\n",options:.backwards) {
            bytes = Data(text[..<boundary.upperBound].utf8)[...]
            return Data(bytes)
        }
        return nil
    }
}
enum CaptionArguments {
    static func extraction(input:String,track:Int,format:CaptionFormat,window:CaptionWindow,file:String) -> [String] {
        var args = ["-hide_banner","-nostdin","-loglevel","error","-nostats","-y"]
        if window.start > 0 { args += ["-ss",String(window.start)] }
        // With copyts every output limit uses the original absolute clock.
        args += ["-copyts"]
        if input.hasPrefix("https:") { args += ["-rw_timeout","5000000","-tls_verify","1"] }
        args += ["-i",input,"-map","0:\(track)","-an","-vn","-dn","-c:s",format == .ass ? "ass" : "webvtt","-t",String(window.end),"-flush_packets","1","-f",format == .ass ? "ass" : "webvtt",file]
        // A bounded copy/discard output walks sparse subtitle intervals to their
        // end. Publish coverage only after the whole bounded job succeeds.
        args += ["-map","0:a:0","-vn","-sn","-dn","-c:a","copy","-t",String(window.end),"-f","null","/dev/null"]
        return args
    }
}
