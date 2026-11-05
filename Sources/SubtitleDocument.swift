/*
Adapted SRT cursor/boundary handling and case-insensitive ASS field matching
from dioKaratzas/swift-subtitle-kit at 728d62dac9fbda7fabd299eed3673ce36c85c267.
Original sources: SRTAdapter.swift and SSACommon.swift. Encoding autodetection
adapts SwiftSubtitles String+decoding.swift at 485c6f1fc71235041198a8bb893fa22f807451a6.
Copyright (c) 2025 Darren Ford.
Swift 5 port and bounds
are maintained by Cast Bridge; upstream is not a compatibility guarantee.

MIT License

Copyright (c) 2026 Dionysis Karatzas

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

// ASS event parsing also adapts Subtitle Edit (Nikolaj Olsson, MIT).
// Full notice: Docs/SubtitleEdit-LICENSE; upstream revision is recorded below.
import Foundation

enum SubtitleDocument {
    static func normalize(_ data:Data) throws -> String {
        guard !data.isEmpty, data.count <= 1_048_576 else { throw StreamHeaderError.tooLarge }
        guard var text=decode(data) else{throw StreamHeaderError.invalid}
        text = text.trimmingCharacters(in:.whitespacesAndNewlines.union(CharacterSet(charactersIn:"\u{feff}"))).replacingOccurrences(of:"\r\n",with:"\n").replacingOccurrences(of:"\r",with:"\n")
        text = text.replacingOccurrences(of:#"\n[\t ]*\n"#,with:"\n\n",options:.regularExpression)
        if text.hasPrefix("WEBVTT") { return try validated(text) }
        if text.range(of:"[Events]",options:.caseInsensitive) != nil { return try ass(text) }
        return try srt(text)
    }
    // NSString autodetection adapted from SwiftSubtitles String+decoding.swift,
    // 485c6f1fc71235041198a8bb893fa22f807451a6, Darren Ford (MIT).
    // BOM priority is explicit: UTF32LE also begins with UTF16LE's FF FE bytes.
    private static func decode(_ data:Data)->String? {
        if data.starts(with:[0xff,0xfe,0x00,0x00]) || data.starts(with:[0x00,0x00,0xfe,0xff]) {return String(data:data,encoding:.utf32)}
        if data.starts(with:[0xff,0xfe]) || data.starts(with:[0xfe,0xff]) {return String(data:data,encoding:.utf16)}
        if let text=String(data:data,encoding:.utf8),!text.contains("\0"){return text}
        // NSString detection may classify BOM-less UTF16 as a byte encoding.
        // Try explicit byte order only when NUL bytes and a decoded subtitle
        // marker agree. The complete parser still validates every cue below.
        if data.count.isMultiple(of:2),data.contains(0) {
            for encoding in [String.Encoding.utf16LittleEndian,.utf16BigEndian] {
                if let text=String(data:data,encoding:encoding),!text.contains("\0"),
                   text.contains("-->") || text.range(of:"[Events]",options:.caseInsensitive) != nil{return text}
            }
        }
        #if canImport(ObjectiveC)
        var decoded:NSString? = nil
        var lossy:ObjCBool=false
        let encoding=NSString.stringEncoding(for:data,encodingOptions:[.allowLossyKey:false],convertedString:&decoded,usedLossyConversion:&lossy)
        if encoding>0,!lossy.boolValue,let decoded,!String(decoded).contains("\0"){return String(decoded)}
        #endif
        for encoding in [String.Encoding.windowsCP1252,.isoLatin1] {
            if let text=String(data:data,encoding:encoding),!text.contains("\0"){return text}
        }
        return nil
    }
    // Adapted from SubtitleKit SRTAdapter.swift, revision
    // 728d62dac9fbda7fabd299eed3673ce36c85c267, Dionysis Karatzas (MIT).
    // Swift 5/Foundation port: bounded clocks, decimal padding, preserve numeric
    // payloads in unindexed files, omit empty cues and serialize standard WebVTT.
    private static func srt(_ text:String) throws -> String {
        let lines=text.components(separatedBy:"\n")
        let timestamp=try NSRegularExpression(pattern:#"^\s*(\d{1,4}):(\d{1,2}):(\d{1,2})(?:[.,](\d{1,3}))?\s*$"#)
        func clock(_ value:String) throws -> Int {
            let ns=value as NSString
            guard let match=timestamp.firstMatch(in:value,range:NSRange(location:0,length:ns.length)),
                  let h=Int(ns.substring(with:match.range(at:1))),h<10000,
                  let m=Int(ns.substring(with:match.range(at:2))),m<60,
                  let seconds=Int(ns.substring(with:match.range(at:3))),seconds<60 else{throw StreamHeaderError.invalid}
            let digits=match.range(at:4).location==NSNotFound ? "":ns.substring(with:match.range(at:4))
            let fraction=Int(digits+String(repeating:"0",count:3-digits.count)) ?? 0
            return ((h*60+m)*60+seconds)*1000+fraction
        }
        func timing(_ line:String) throws -> (Int,Int,String) {
            let parts=line.components(separatedBy:"-->")
            guard parts.count==2 else{throw StreamHeaderError.invalid}
            let end=parts[1].trimmingCharacters(in:.whitespaces).split(maxSplits:1,whereSeparator:{$0==" " || $0=="\t"})
            guard let value=end.first else{throw StreamHeaderError.invalid}
            let first=try clock(parts[0]),last=try clock(String(value))
            guard last>first else{throw StreamHeaderError.invalid}
            return (first,last,end.count>1 ? " "+String(end[1]):"")
        }
        func stamp(_ n:Int)->String {String(format:"%02d:%02d:%02d.%03d",n/3_600_000,(n/60_000)%60,(n/1000)%60,n%1000)}
        func isTiming(_ line:String)->Bool {(try? timing(line)) != nil}
        var cursor=0
        var cues:[String]=[]
        var indexed=false
        while cursor<lines.count {
            while cursor<lines.count,lines[cursor].trimmingCharacters(in:.whitespaces).isEmpty{cursor+=1}
            guard cursor<lines.count else{break}
            var timingIndex=cursor
            if cursor+1<lines.count,Int(lines[cursor].trimmingCharacters(in:.whitespaces)) != nil,isTiming(lines[cursor+1]) {
                indexed=true;timingIndex=cursor+1
            }
            let (start,end,settings)=try timing(lines[timingIndex])
            var body:[String]=[],next=timingIndex+1
            while next<lines.count {
                if lines[next].trimmingCharacters(in:.whitespaces).isEmpty{next+=1;break}
                if isTiming(lines[next]){break}
                if indexed,next+1<lines.count,Int(lines[next].trimmingCharacters(in:.whitespaces)) != nil,isTiming(lines[next+1]){break}
                body.append(lines[next]);next+=1
            }
            if !body.joined(separator:"\n").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                cues.append(stamp(start)+" --> "+stamp(end)+settings+"\n"+body.joined(separator:"\n"))
            }
            cursor=next
        }
        guard !cues.isEmpty else{throw StreamHeaderError.invalid}
        return try validated("WEBVTT\n\n"+cues.joined(separator:"\n\n")+"\n\n")
    }
    /// Complete downloads/extractions must contain a usable cue. Windowed
    /// streaming documents may be empty and use CaptionDocument instead.
    private static func validated(_ text:String) throws -> String {
        let blocks = text.components(separatedBy:"\n\n")
        guard let header = blocks.first?.components(separatedBy:"\n").first,
              header == "WEBVTT" || header.hasPrefix("WEBVTT ") || header.hasPrefix("WEBVTT\t"),
              !header.contains("-->") else { throw StreamHeaderError.invalid }
        _ = try WebVTTTimeline.rebased(text,offset:0)
        var usable = false
        for block in blocks.dropFirst() {
            let lines = block.components(separatedBy:"\n")
            guard let first = lines.first, !first.isEmpty else { continue }
            if first == "NOTE" || first.hasPrefix("NOTE ") || first.hasPrefix("NOTE\t") || first == "STYLE" || first == "REGION" { continue }
            let timing = first.contains("-->") ? 0 : 1
            guard lines.indices.contains(timing), lines[timing].contains("-->"),
                  lines.dropFirst(timing+1).allSatisfy({!$0.contains("-->")}) else { throw StreamHeaderError.invalid }
            if !lines.dropFirst(timing+1).joined(separator:"\n").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { usable = true }
        }
        guard usable else { throw StreamHeaderError.invalid }
        return text
    }
    private static func ass(_ text:String) throws -> String {
        try convertASS(text).text
    }
    /// Native extraction keeps the original ASS events instead of passing
    /// through FFmpeg's WebVTT encoder (which can emit invalid empty cues and
    /// blank paragraphs). Counts are safe for diagnostics; never log event text.
    static func embeddedASS(_ data:Data) throws -> (text:String,events:Int,skipped:Int) {
        guard !data.isEmpty,data.count<=1_048_576,let text=decode(data) else{throw StreamHeaderError.invalid}
        return try convertASS(text.replacingOccurrences(of:"\r\n",with:"\n").replacingOccurrences(of:"\r",with:"\n"))
    }
    // Event-section, case-insensitive Format and per-event error isolation are
    // adapted from Subtitle Edit SubStationAlpha.LoadSubtitle, MIT, revision
    // 540ade3229bcdfb64493abb0b0309cb8dd483a1c. Swift bounded text-only port:
    // omit comments/drawings/zero durations, preserve overlapping dialogue,
    // sort by start stably, escape literal text before serializing WebVTT.
    private static func convertASS(_ text:String) throws -> (text:String,events:Int,skipped:Int) {
        var fields=["layer","start","end","style","name","marginl","marginr","marginv","effect","text"]
        var events=false,seen=0,skipped=0
        var cues:[(start:Int,end:Int,body:String,order:Int)]=[]
        func clock(_ value:String)->Int? {
            let p=value.trimmingCharacters(in:.whitespaces).split(separator:":",omittingEmptySubsequences:false)
            guard p.count==3,let h=Int(p[0]),let m=Int(p[1]),let seconds=Double(p[2]),
                  h>=0,h<10000,(0..<60).contains(m),seconds.isFinite,seconds>=0,seconds<60 else{return nil}
            return (h*3600+m*60)*1000+Int((seconds*1000).rounded())
        }
        func stamp(_ n:Int)->String {String(format:"%02d:%02d:%02d.%03d",n/3_600_000,(n/60_000)%60,(n/1000)%60,n%1000)}
        // Interpret drawing switches before removing tags, otherwise vector
        // coordinates become visible dialogue. Transform tags do not execute
        // drawing switches: only top-level \pN and \r reset drawing state.
        func body(_ source:String)->String {
            var output="",drawing=false,index=source.startIndex
            while index<source.endIndex {
                if source[index]=="{",let close=source[index...].firstIndex(of:"}") {
                    let tag=String(source[source.index(after:index)..<close])
                    var depth=0,top=""
                    for c in tag {if c=="("{depth+=1};if depth==0{top.append(c)};if c==")"{depth=max(0,depth-1)}}
                    let pattern=#"\\(?:p([0-9]+)(?=\s|\\|$)|r[^\\]*)"#
                    if let regex=try? NSRegularExpression(pattern:pattern) {
                        let ns=top as NSString
                        for match in regex.matches(in:top,range:NSRange(location:0,length:ns.length)) {
                            drawing=match.range(at:1).location != NSNotFound && (Int(ns.substring(with:match.range(at:1))) ?? 0)>0
                        }
                    }
                    index=source.index(after:close);continue
                }
                if !drawing{output.append(source[index])}
                index=source.index(after:index)
            }
            output=output.replacingOccurrences(of:"\\N",with:"\n").replacingOccurrences(of:"\\n",with:"\n").replacingOccurrences(of:"\\h",with:" ")
            // A blank line terminates a WebVTT cue. ASS can contain several \N
            // separators in one event; retain the nonempty lines as one cue.
            output=output.components(separatedBy:"\n").map{$0.trimmingCharacters(in:.whitespaces)}.filter{!$0.isEmpty}.joined(separator:"\n")
            return output.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;")
        }
        for raw in text.components(separatedBy:"\n") {
            let line=raw.trimmingCharacters(in:.whitespacesAndNewlines),lower=line.lowercased()
            if line.hasPrefix("["){events=lower=="[events]";continue}
            if lower.hasPrefix("dialogue:") || lower.hasPrefix("dialog:"){events=true}
            guard events else{continue}
            if lower.hasPrefix("format:") {
                fields=String(line.dropFirst(7)).components(separatedBy:",").map{$0.trimmingCharacters(in:.whitespaces).lowercased()};continue
            }
            guard lower.hasPrefix("dialogue:") || lower.hasPrefix("dialog:") else{continue}
            seen+=1
            guard fields.count<=32,let start=fields.firstIndex(of:"start"),let end=fields.firstIndex(of:"end"),let textIndex=fields.firstIndex(of:"text"),textIndex==fields.count-1,
                  let colon=line.firstIndex(of:":") else{skipped+=1;continue}
            let values=line[line.index(after:colon)...].split(separator:",",maxSplits:fields.count-1,omittingEmptySubsequences:false).map(String.init)
            guard values.count==fields.count,let first=clock(values[start]),let last=clock(values[end]),last>first else{skipped+=1;continue}
            let caption=body(values[textIndex]);guard !caption.isEmpty else{skipped+=1;continue}
            cues.append((first,last,caption,seen))
        }
        guard !cues.isEmpty else{throw StreamHeaderError.invalid}
        cues.sort{$0.start==$1.start ? $0.order<$1.order:$0.start<$1.start}
        let result="WEBVTT\n\n"+cues.map{stamp($0.start)+" --> "+stamp($0.end)+"\n"+$0.body}.joined(separator:"\n\n")+"\n\n"
        guard result.utf8.count<=1_048_576 else{throw StreamHeaderError.tooLarge}
        return (try validated(result),seen,skipped)
    }
}
