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
        var fields = ["Layer","Start","End","Style","Name","MarginL","MarginR","MarginV","Effect","Text"]
        var result = "WEBVTT\n\n", events = false, count = 0
        func stamp(_ value:String) throws -> String {
            let parts = value.trimmingCharacters(in:.whitespaces).split(separator:":")
            guard parts.count == 3, let h = Int(parts[0]), let m = Int(parts[1]), let s = Double(parts[2]), h >= 0, h < 10000, (0..<60).contains(m), s >= 0, s < 60 else { throw StreamHeaderError.invalid }
            let ms = Int((s*1000).rounded())
            return String(format:"%02d:%02d:%02d.%03d",h,m,ms/1000,ms%1000)
        }
        for raw in text.components(separatedBy:"\n") {
            let line=raw.trimmingCharacters(in:.whitespaces)
            if line.hasPrefix("[") { events = line.caseInsensitiveCompare("[Events]") == .orderedSame; continue }
            guard events else { continue }
            if line.lowercased().hasPrefix("format:") { fields = String(line.dropFirst(7)).components(separatedBy:",").map{$0.trimmingCharacters(in:.whitespaces)} }
            if line.lowercased().hasPrefix("dialogue:"), let start = fields.firstIndex(where:{$0.caseInsensitiveCompare("Start") == .orderedSame}), let end = fields.firstIndex(where:{$0.caseInsensitiveCompare("End") == .orderedSame}), let body = fields.firstIndex(where:{$0.caseInsensitiveCompare("Text") == .orderedSame}) {
                let values = line.dropFirst(9).split(separator:",",maxSplits:fields.count-1,omittingEmptySubsequences:false).map(String.init)
                guard values.count == fields.count, body == fields.count-1 else { throw StreamHeaderError.invalid }
                let caption = values[body].replacingOccurrences(of:#"\{[^}]*\}"#,with:"",options:.regularExpression).replacingOccurrences(of:"\\N",with:"\n").replacingOccurrences(of:"\\n",with:"\n").replacingOccurrences(of:"\\h",with:" ")
                result += try stamp(values[start])+" --> "+stamp(values[end])+"\n"+caption+"\n\n"; count += 1
            }
        }
        guard count > 0 else { throw StreamHeaderError.invalid }
        return try validated(result)
    }
}

