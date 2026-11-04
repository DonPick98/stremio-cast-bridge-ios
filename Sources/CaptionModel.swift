import Foundation
import CryptoKit

/// Complete documents only; filenames contain digests, never source URLs or titles.
/// Access dates implement LRU across launches. No cache entry is trusted after expiry.
final class CaptionDocumentCache {
    private let directory:URL
    private let budget:Int, countLimit:Int, lifetime:TimeInterval
    private let clock:()->Date
    init(directory:URL = FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("CastBridge/CompleteCaptions-v1"),budget:Int = 12_582_912,countLimit:Int = 24,lifetime:TimeInterval = 604800,clock:@escaping ()->Date = Date.init){
        self.directory=directory;self.budget=budget;self.countLimit=countLimit;self.lifetime=lifetime;self.clock=clock
        try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        var excluded=directory;var values=URLResourceValues();values.isExcludedFromBackup=true;try? excluded.setResourceValues(values)
        prune()
    }
    static func key(input:URL,track:String)->String{
        SHA256.hash(data:Data((input.absoluteString+"\n"+track).utf8)).map{String(format:"%02x",$0)}.joined()
    }
    private func file(_ key:String)->URL?{
        guard key.count==64,key.allSatisfy({$0.isHexDigit}) else{return nil}
        return directory.appendingPathComponent(key+".vtt")
    }
    func get(_ key:String)->String?{
        guard let file=file(key),let values=try? file.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey]),
              let size=values.fileSize,size<=1_048_576,let date=values.contentModificationDate,clock().timeIntervalSince(date)<=lifetime,
              let data=try? Data(contentsOf:file) else{return nil}
        guard let text=String(data:data,encoding:.utf8),text.hasPrefix("WEBVTT"),
              let complete=try? SubtitleDocument.normalize(data) else{try? FileManager.default.removeItem(at:file);return nil}
        try? FileManager.default.setAttributes([.modificationDate:clock()],ofItemAtPath:file.path)
        return complete
    }
    func put(_ text:String,key:String){
        guard let file=file(key),text.hasPrefix("WEBVTT"),text.utf8.count<=min(budget,1_048_576),
              (try? SubtitleDocument.normalize(Data(text.utf8))) != nil else{return}
        do{try Data(text.utf8).write(to:file,options:.atomic);try FileManager.default.setAttributes([.modificationDate:clock()],ofItemAtPath:file.path)}catch{return}
        prune()
    }
    func diskBytes()->Int {
        let files=(try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.fileSizeKey,.isRegularFileKey])) ?? []
        return files.filter{$0.pathExtension=="vtt"}.reduce(0){sum,file in
            guard let values=try? file.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey]),values.isRegularFile==true else{return sum}
            return sum+max(0,values.fileSize ?? 0)
        }
    }
    @discardableResult func clear()->Bool {
        let files:[URL]
        do {files=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.isRegularFileKey])}
        catch{return false}
        var success=true
        for file in files where file.pathExtension=="vtt" && file.deletingPathExtension().lastPathComponent.count==64 && file.deletingPathExtension().lastPathComponent.allSatisfy({$0.isHexDigit}) {
            guard (try? file.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile)==true else{continue}
            do {try FileManager.default.removeItem(at:file)}catch{success=false}
        }
        return success
    }
    private func prune(){
        let files=(try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.fileSizeKey,.contentModificationDateKey,.isRegularFileKey])) ?? []
        var entries:[(URL,Int,Date)]=[]
        for file in files where file.pathExtension=="vtt"{
            guard let values=try? file.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey,.isRegularFileKey]),values.isRegularFile==true else{continue}
            let date=values.contentModificationDate ?? .distantPast,size=values.fileSize ?? 0
            if clock().timeIntervalSince(date)>lifetime || size>1_048_576{try? FileManager.default.removeItem(at:file)}else{entries.append((file,size,date))}
        }
        entries.sort{$0.2<$1.2};var bytes=entries.reduce(0){$0+$1.1}
        while entries.count>countLimit || bytes>budget{
            let old=entries.removeFirst();bytes-=old.1;try? FileManager.default.removeItem(at:old.0)
        }
    }
}

enum DirectCaptionPolicy {
    static func needsMediaProxy(force:Bool,compatible:Bool,audioChanged:Bool,burn:Bool,textSelected:Bool,corsAllowed:Bool?)->Bool{
        force || !compatible || audioChanged || burn || (textSelected && corsAllowed == false)
    }
    // A wildcard is independent of receiver version/origin; otherwise be conservative.
    static func allows(response:HTTPURLResponse,preflight:Bool)->Bool{
        guard (200..<300).contains(response.statusCode),response.value(forHTTPHeaderField:"Access-Control-Allow-Origin")?.trimmingCharacters(in:.whitespacesAndNewlines)=="*" else{return false}
        if !preflight{return true}
        let methods=Set((response.value(forHTTPHeaderField:"Access-Control-Allow-Methods") ?? "").lowercased().split(separator:",").map{$0.trimmingCharacters(in:.whitespaces)})
        let headers=Set((response.value(forHTTPHeaderField:"Access-Control-Allow-Headers") ?? "").lowercased().split(separator:",").map{$0.trimmingCharacters(in:.whitespaces)})
        return (methods.contains("get") || methods.contains("*")) && (headers.contains("*") || Set(["range","content-type","accept-encoding"]).isSubset(of:headers))
    }
}

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
