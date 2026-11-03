import Foundation

@main struct PlaybackDiagnosticsTests {
    @MainActor static func main() throws {
        var now = Date(timeIntervalSince1970:1_000_000)
        let log = DiagnosticRecorder(retention:600,limit:3,clock:{now})
        log.record(.source,["phase":"start","url":"https://secret.example/key","code":"https://secret.example/key"])
        let clean = log.report()
        precondition(!clean.contains("secret.example") && !clean.contains("url="))
        precondition(clean.contains("phase=start"))
        let privateError=NSError(domain:"private-provider-token",code:34,userInfo:[NSLocalizedDescriptionKey:"https://secret.example/token"])
        let fields=PlaybackDiagnostics.errorFields(privateError,phase:"audio_activate")
        precondition(fields["domain"]=="other" && fields["code"]=="34")
        precondition(!fields.values.contains(where:{$0.contains("secret") || $0.contains("token")}))
        let structured=DiagnosticRecorder(clock:{now})
        structured.record(.command,["phase":"cast_abort","request":"12","action":"pause","generation":"ABC123","code":"1"])
        structured.record(.snapshot,["phase":"energy","battery":"72.5","thermal":"0","power":"1","lowPower":"false"])
        precondition(structured.report().contains("request=12") && structured.report().contains("battery=72.5"))
        var shortNow=now
        let short=DiagnosticRecorder(clock:{shortNow})
        short.record(.app,["phase":"old_marker"])
        precondition(short.report().contains("ultimi 2 minuti"))
        shortNow=shortNow.addingTimeInterval(121)
        precondition(!short.report().contains("old_marker"),"Default diagnostics must expire after two minutes")
        log.changed("cast",event:.cast,["status":"playing"])
        log.changed("cast",event:.cast,["status":"playing"])
        precondition(log.report().components(separatedBy:"status=playing").count == 2)
        log.record(.seek,["target":"120.000"]); log.record(.error,["code":"CB203"])
        precondition(!log.report().contains("phase=start"))
        now = now.addingTimeInterval(601)
        precondition(!log.report().contains("code=CB203"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = folder.appendingPathComponent("diagnostics.json")
        defer { try? FileManager.default.removeItem(at:folder) }
        let saved = DiagnosticRecorder(file:file,clock:{now})
        saved.record(.prepare,["mode":"ffmpegH264"]); saved.flush()
        let restored = DiagnosticRecorder(file:file,clock:{now})
        precondition(restored.report().contains("mode=ffmpegH264"))
        print("Diagnostics: redaction, deduplication, bounded history, expiry and restoration passed")
    }
}

