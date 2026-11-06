import Foundation

/// Local, bounded breadcrumbs. Callers pass codes and measurements, never URLs,
/// titles, server responses, credentials or raw third-party error descriptions.
@MainActor final class DiagnosticRecorder {
    enum Event:String, Codable { case app, cast, source, metadata, prepare, producer, load, tracks, seek, command, recovery, error, snapshot }
    struct Entry:Codable {
        let time:Date
        let event:Event
        let fields:[String:String]
    }
    private let retention:TimeInterval
    private let limit:Int
    private let clock:() -> Date
    private let file:URL?
    private var entries:[Entry] = []
    private var flushTask:Task<Void,Never>?
    private var dirty=false
    private let flushDelayNanoseconds:UInt64
    private(set) var persistenceWrites=0
    private var changes:[String:String] = [:]
    private static let allowed:Set<String> = ["phase","kind","mode","codec","audio","subtitle","width","height","fps","position","reported","raw","duration","paused","local","connected","generation","code","status","attempt","bytes","seconds","result","burn","copyAudio","offset","target","foreground","tracks","idle","owned","pending","version","build","domain","request","action","confirmed","battery","thermal","lowPower","power","rate","upstreamWait","downstreamWait","session","previousSession","channels","requestGeneration","frames","mediaSeconds","wallSeconds","speed","duplicate","dropped","writes","completed","total"]

    init(retention:TimeInterval = 120,limit:Int = 400,file:URL? = nil,flushDelayNanoseconds:UInt64=2_000_000_000,clock:@escaping () -> Date = Date.init) {
        self.retention = retention; self.limit = limit; self.file = file; self.clock = clock
        self.flushDelayNanoseconds=flushDelayNanoseconds
        if let file, let size = try? file.resourceValues(forKeys:[.fileSizeKey]).fileSize, size <= 262144,
           let data = try? Data(contentsOf:file), let saved = try? JSONDecoder().decode([Entry].self,from:data) {
            entries = saved.map { Entry(time:$0.time,event:$0.event,fields:Self.safe($0.fields)) }
        }
        prune()
    }
    private static func safe(_ fields:[String:String]) -> [String:String] {
        fields.reduce(into:[:]) { result,pair in
            guard allowed.contains(pair.key) else { return }
            let value = String(pair.value.prefix(100))
            // Strict allow-list also blocks embedded URL queries and paths.
            guard !value.lowercased().contains("http"), value.range(of:"^[A-Za-z0-9_. +:-]{1,100}$",options:.regularExpression) != nil else { return }
            result[pair.key] = value
        }
    }
    private func prune() {
        let now = clock(),before=entries.count
        entries.removeAll { now.timeIntervalSince($0.time) > retention || $0.time > now.addingTimeInterval(1) }
        if entries.count > limit { entries.removeFirst(entries.count-limit) }
        if before != entries.count {dirty=true}
    }
    func record(_ event:Event,_ fields:[String:String] = [:]) {
        entries.append(Entry(time:clock(),event:event,fields:Self.safe(fields)));dirty=true; prune()
        // Keep failure/recovery evidence durable immediately. Ordinary bursts
        // share one write; lifecycle/report callers explicitly force a flush.
        if event == .error || event == .recovery || fields["result"] == "error" ||
           (event == .app && ["memory_warning","audio_interruption","audio_reset"].contains(fields["phase"] ?? "")) ||
           (event == .producer && fields["phase"] == "ffmpeg_exit" && fields["code"] != "0") {flush();return}
        guard file != nil, flushTask == nil else { return }
        let delay=flushDelayNanoseconds
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds:delay)
            guard !Task.isCancelled, let self else { return }
            self.flushTask = nil; self.flush()
        }
    }
    func changed(_ key:String,event:Event,_ fields:[String:String]) {
        let safe = Self.safe(fields), signature = safe.sorted{$0.key < $1.key}.map{"\($0.key)=\($0.value)"}.joined(separator:" ")
        guard changes[key] != signature else { return }
        changes[key] = signature; record(event,safe)
    }
    func flush() {
        flushTask?.cancel();flushTask=nil
        prune()
        guard dirty,let file,let data=try? JSONEncoder().encode(entries) else{return}
        do {
            try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
            try data.write(to:file,options:.atomic)
            dirty=false;persistenceWrites+=1
        } catch { /* Retain dirty data for the next explicit or scheduled flush. */ }
    }
    func report() -> String {
        prune(); flush()
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
        let version = Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "dev"
        return "Cast Bridge \(version) (\(build)) - diagnostica locale, ultimi \(max(1,Int(retention/60))) minuti\nSistema: \(ProcessInfo.processInfo.operatingSystemVersionString)\nNessun invio automatico. Link, credenziali e titoli esclusi.\n\n" + entries.map {
            formatter.string(from:$0.time) + " " + $0.event.rawValue + " " + $0.fields.sorted{$0.key < $1.key}.map{"\($0.key)=\($0.value)"}.joined(separator:" ")
        }.joined(separator:"\n")
    }
}

@MainActor enum PlaybackDiagnostics {
    static let shared = DiagnosticRecorder(file:FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask).first?.appendingPathComponent("CastBridge/playback-diagnostics.json"))
    static func record(_ event:DiagnosticRecorder.Event,_ fields:[String:String] = [:]) { shared.record(event,fields) }
    static func number(_ value:Double) -> String { value.isFinite ? String(format:"%.3f",locale:Locale(identifier:"en_US_POSIX"),value) : "unknown" }
    static func errorFields(_ error:Error,phase:String) -> [String:String] {
        let error = error as NSError
        // Never log localizedDescription, userInfo or arbitrary vendor domains.
        let known = ["NSURLErrorDomain","NSOSStatusErrorDomain","AVFoundationErrorDomain","NSCocoaErrorDomain","com.google.cast.GCKError"]
        return ["phase":phase,"domain":known.contains(error.domain) ? error.domain:"other","code":String(error.code)]
    }
}


