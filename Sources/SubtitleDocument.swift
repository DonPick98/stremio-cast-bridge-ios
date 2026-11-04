import Foundation

enum SubtitleDocument {
    static func normalize(_ data:Data) throws -> String {
        guard !data.isEmpty, data.count <= 1_048_576 else { throw StreamHeaderError.tooLarge }
        let text:String?
        if data.starts(with:[0xff,0xfe]) || data.starts(with:[0xfe,0xff]) { text = String(data:data,encoding:.utf16) }
        else { text = String(data:data,encoding:.utf8) ?? String(data:data,encoding:.windowsCP1252) ?? String(data:data,encoding:.isoLatin1) }
        guard var text else { throw StreamHeaderError.invalid }
        text = text.trimmingCharacters(in:.whitespacesAndNewlines.union(CharacterSet(charactersIn:"\u{feff}"))).replacingOccurrences(of:"\r\n",with:"\n").replacingOccurrences(of:"\r",with:"\n")
        text = text.replacingOccurrences(of:#"\n[\t ]*\n"#,with:"\n\n",options:.regularExpression)
        if text.hasPrefix("WEBVTT") { return try validated(text) }
        if text.contains("[Events]") { return try ass(text) }
        var cues:[String] = []
        let timing = try NSRegularExpression(pattern:#"^(\d{1,3}:\d{2}:\d{2})[,\.](\d{3})\s+-->\s+(\d{1,3}:\d{2}:\d{2})[,\.](\d{3})(.*)$"#)
        let lines = text.components(separatedBy:"\n")
        let positions = lines.indices.filter{lines[$0].contains("-->")}
        let indexed = positions.first.map{$0 > 0 && Int(lines[$0-1].trimmingCharacters(in:.whitespaces)) != nil} ?? false
        for (ordinal,i) in positions.enumerated() {
            let ns = lines[i].trimmingCharacters(in:.whitespaces) as NSString
            guard let m = timing.firstMatch(in:ns as String,range:NSRange(location:0,length:ns.length)) else { throw StreamHeaderError.invalid }
            let next = ordinal+1 < positions.count ? positions[ordinal+1] : lines.count
            var body = Array(lines[(i+1)..<next])
            while body.last?.trimmingCharacters(in:.whitespaces).isEmpty == true { body.removeLast() }
            // Tolerate missing blank separators without displaying the next cue
            // index. Preserve literal numbers in unindexed subtitle payloads.
            if indexed, next < lines.count, let last = body.last,
               let number = Int(last.trimmingCharacters(in:.whitespaces)),
               (body.count > 1 && body[body.count-2].trimmingCharacters(in:.whitespaces).isEmpty ||
                (i > 0 && Int(lines[i-1].trimmingCharacters(in:.whitespaces)).map{$0+1 == number} == true)) {
                body.removeLast()
            }
            while body.last?.trimmingCharacters(in:.whitespaces).isEmpty == true { body.removeLast() }
            guard !body.joined(separator:"\n").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw StreamHeaderError.invalid }
            func clock(_ index:Int) -> String { let p = ns.substring(with:m.range(at:index)).split(separator:":").map{Int($0) ?? 0}; return String(format:"%02d:%02d:%02d",p[0],p[1],p[2]) }
            let line = clock(1) + "." + ns.substring(with:m.range(at:2)) + " --> " + clock(3) + "." + ns.substring(with:m.range(at:4)) + ns.substring(with:m.range(at:5))
            cues.append(line+"\n"+body.joined(separator:"\n"))
        }
        guard !cues.isEmpty else { throw StreamHeaderError.invalid }
        let result = "WEBVTT\n\n"+cues.joined(separator:"\n\n")+"\n\n"
        return try validated(result)
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
        for line in text.components(separatedBy:"\n") {
            if line.hasPrefix("[") { events = line.trimmingCharacters(in:.whitespaces) == "[Events]"; continue }
            guard events else { continue }
            if line.hasPrefix("Format:") { fields = String(line.dropFirst(7)).components(separatedBy:",").map{$0.trimmingCharacters(in:.whitespaces)} }
            if line.hasPrefix("Dialogue:"), let start = fields.firstIndex(of:"Start"), let end = fields.firstIndex(of:"End"), let body = fields.firstIndex(of:"Text") {
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

