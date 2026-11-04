import Foundation

enum SubtitleFetchError:LocalizedError {
    case http(Int),format,limit
    var errorDescription:String? {
        switch self {
        case .http(let status):return "La sorgente sottotitoli ha risposto con HTTP \(status). Prova un’altra versione o riprova più tardi."
        case .format:return "Il file ricevuto non contiene sottotitoli SRT, ASS o WebVTT leggibili."
        case .limit:return "Il file sottotitoli supera il limite supportato di 1 MiB."
        }
    }
}

enum WebVTTTimeline {
    static func rebased(_ text:String, offset:Double, delay:Double = 0) throws -> Data {
        let source = text.hasPrefix("\u{feff}") ? String(text.dropFirst()) : text
        guard source.utf8.count <= 1_048_576, source.trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("WEBVTT"), offset.isFinite, offset >= 0, delay.isFinite, abs(delay) <= 300 else { throw StreamHeaderError.invalid }
        let origin = offset-delay
        let normalized = source.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"\r\n",with:"\n").replacingOccurrences(of:"\r",with:"\n")
        let pattern = #"^(\d{2,}:\d{2}:\d{2}\.\d{3}|\d{2}:\d{2}\.\d{3})\s+-->\s+(\d{2,}:\d{2}:\d{2}\.\d{3}|\d{2}:\d{2}\.\d{3})(.*)$"#
        let regex = try NSRegularExpression(pattern:pattern)
        let inline = try NSRegularExpression(pattern:#"<(\d{2,}:\d{2}:\d{2}\.\d{3}|\d{2}:\d{2}\.\d{3})>"#)
        var output: [String] = []
        for block in normalized.components(separatedBy:"\n\n") {
            var lines = block.components(separatedBy:"\n").filter{!$0.hasPrefix("X-TIMESTAMP-MAP")}
            if let first = lines.first, first == "NOTE" || first.hasPrefix("NOTE ") || first.hasPrefix("NOTE\t") || first == "STYLE" || first == "REGION" {
                output.append(lines.joined(separator:"\n")); continue
            }
            guard let i = lines.firstIndex(where:{$0.contains("-->")}) else { if !lines.joined(separator:"\n").isEmpty { output.append(lines.joined(separator:"\n")) }; continue }
            let line = lines[i] as NSString
            guard let match = regex.firstMatch(in:lines[i],range:NSRange(location:0,length:line.length)),
                  let start = seconds(line.substring(with:match.range(at:1))), let end = seconds(line.substring(with:match.range(at:2))), end > start else { throw StreamHeaderError.invalid }
            if end <= origin { continue }
            lines[i] = time(max(0,start-origin)) + " --> " + time(end-origin) + line.substring(with:match.range(at:3))
            if i+1 < lines.count {
                for j in (i+1)..<lines.count {
                    let original = lines[j] as NSString
                    let matches = inline.matches(in:lines[j],range:NSRange(location:0,length:original.length))
                    let changed = NSMutableString(string:lines[j])
                    for tag in matches.reversed() {
                        if let t = seconds(original.substring(with:tag.range(at:1))) { changed.replaceCharacters(in:tag.range,with:t <= origin ? "" : "<\(time(t-origin))>") }
                    }
                    lines[j] = changed as String
                }
            }
            output.append(lines.joined(separator:"\n"))
        }
        if output.isEmpty { output = ["WEBVTT"] }
        return Data((output.joined(separator:"\n\n")+"\n\n").utf8)
    }
    private static func seconds(_ text:String) -> Double? {
        let parts = text.split(separator:":").compactMap{Double($0)}
        guard parts.count == 2 || parts.count == 3, parts.allSatisfy({$0.isFinite && $0 >= 0}), parts[0] < 10_000, let second = parts.last, second < 60, parts[parts.count-2] < 60 else { return nil }
        return parts.count == 3 ? parts[0]*3600+parts[1]*60+second : parts[0]*60+second
    }
    private static func time(_ seconds:Double) -> String {
        let n = Int((seconds*1000).rounded())
        return String(format:"%02d:%02d:%02d.%03d",n/3_600_000,(n/60_000)%60,(n/1000)%60,n%1000)
    }
    static func fetch(_ url:URL,configuration:URLSessionConfiguration = .ephemeral) async throws -> String {
        guard url.scheme == "https", url.user == nil, url.password == nil else { throw StreamHeaderError.invalid }
        let config = configuration
        config.timeoutIntervalForRequest = 8; config.timeoutIntervalForResource = 10
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        let session = URLSession(configuration:config,delegate:CaptionRedirectGuard(),delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        let (bytes,response) = try await session.bytes(from:url)
        guard let http=response as? HTTPURLResponse else { throw StreamHeaderError.network }
        guard http.statusCode == 200 else { throw SubtitleFetchError.http(http.statusCode) }
        var data = Data()
        for try await byte in bytes { guard data.count < 1_048_576 else { throw SubtitleFetchError.limit }; data.append(byte) }
        do { return try SubtitleDocument.normalize(data) }
        catch { throw SubtitleFetchError.format }
    }
}
private final class CaptionRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session:URLSession, task:URLSessionTask, willPerformHTTPRedirection response:HTTPURLResponse, newRequest request:URLRequest, completionHandler:@escaping (URLRequest?)->Void) {
        guard let url = request.url, url.scheme == "https", url.user == nil, url.password == nil else { completionHandler(nil); return }
        completionHandler(request)
    }
}


