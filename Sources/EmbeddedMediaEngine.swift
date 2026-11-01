import Foundation
import MobileVLCKit
import AVFAudio
import UIKit
import Darwin

enum EmbeddedMediaError: LocalizedError {
    case metadata, address, encoder, timeout
    var errorDescription: String? {
        switch self {
        case .metadata: return "Il motore integrato non riesce a leggere le tracce di questa sorgente."
        case .address: return "L’iPhone deve essere sulla stessa rete locale del Chromecast."
        case .encoder: return "Il motore integrato non è riuscito a convertire questo formato."
        case .timeout: return "Il motore integrato non ha preparato il flusso entro il tempo previsto."
        }
    }
}

@MainActor final class EmbeddedMediaEngine: NSObject, VLCMediaPlayerDelegate {
    enum VideoMode: Equatable { case copy, hardwareH264, softwareVP8 }
    static func modes(requiresVideo:Bool,fallbackLevel:Int = 0) -> [VideoMode] {
        fallbackLevel >= 2 ? [.softwareVP8] : (requiresVideo || fallbackLevel == 1) ? [.hardwareH264,.softwareVP8] : [.copy,.hardwareH264,.softwareVP8]
    }
    private var player: VLCMediaPlayer?
    private var initialResume: Task<Void,Never>?
    private var audioRepair: AudioRepairPipe?
    private var proxy: LocalStreamProxy?
    private var backgroundPlayer: VLCMediaPlayer?
    private var observers: [NSObjectProtocol] = []
    private(set) var streamURL: URL?
    private(set) var captionURLs: [Int:URL] = [:]
    private(set) var contentType = "video/mp4"
    private(set) var offset: Double = 0
    private(set) var running = false
    private var startedStream = false
    var onFailure: (() -> Void)?

    static func inspect(_ url: URL) async throws -> RDPreparedMedia {
        let media = VLCMedia(url:url)
        guard media.parse(options:VLCMediaParsingOptions(rawValue:url.isFileURL ? 0 : 1),timeout:15_000) == 0 else { throw EmbeddedMediaError.metadata }
        defer { media.parseStop() }
        for _ in 0..<170 {
            try Task.checkCancellation()
            if media.parsedStatus == .done { break }
            if media.parsedStatus == .failed || media.parsedStatus == .skipped || media.parsedStatus == .timeout { throw EmbeddedMediaError.metadata }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        guard media.parsedStatus == .done else { throw EmbeddedMediaError.metadata }
        let tracks = media.tracksInformation as? [[String:Any]] ?? []
        func codec(_ track: [String:Any]) -> String {
            let code = (track[VLCMediaTracksInformationCodec] as? NSNumber)?.uint32Value ?? 0
            return String(bytes:(0..<4).map { UInt8((code >> ($0*8)) & 255) },encoding:.ascii)?.trimmingCharacters(in:.whitespaces) ?? ""
        }
        func readTracks(_ type: String) -> [RDTrack] {
            tracks.filter { $0[VLCMediaTracksInformationType] as? String == type }.compactMap { track in
                guard let id = (track[VLCMediaTracksInformationId] as? NSNumber)?.intValue, id >= 0 else { return nil }
                let language = track[VLCMediaTracksInformationLanguage] as? String ?? "und"
                let rawCodec = codec(track)
                let friendly = ["a52":"ac3","mp4a":"aac","eac3":"eac3","dts":"dts"][rawCodec] ?? rawCodec
                return RDTrack(key:"vlc_\(id)",language:language,label:track[VLCMediaTracksInformationDescription] as? String ?? language,codec:friendly,channels:(track[VLCMediaTracksInformationAudioChannelsNumber] as? NSNumber)?.intValue)
            }
        }
        let audio = readTracks(VLCMediaTracksInformationTypeAudio)
        guard !audio.isEmpty, let video = tracks.first(where:{$0[VLCMediaTracksInformationType] as? String == VLCMediaTracksInformationTypeVideo}) else { throw EmbeddedMediaError.metadata }
        let w = (video[VLCMediaTracksInformationVideoWidth] as? NSNumber)?.intValue ?? 0
        let h = (video[VLCMediaTracksInformationVideoHeight] as? NSNumber)?.intValue ?? 0
        let rate = (video[VLCMediaTracksInformationFrameRate] as? NSNumber)?.doubleValue ?? 0
        let base = (video[VLCMediaTracksInformationFrameRateDenominator] as? NSNumber)?.doubleValue ?? 1
        let fps = base > 0 ? rate/base : 0
        let rawProfile = (video[VLCMediaTracksInformationCodecProfile] as? NSNumber)?.intValue ?? 0
        let profile = rawProfile >= 0 ? rawProfile & 255 : 0
        let level = (video[VLCMediaTracksInformationCodecLevel] as? NSNumber)?.intValue ?? 0
        let videoSafe = codec(video) == "h264" && profile <= 100 && (level == 0 || level <= 42) && w > 0 && h > 0 && w <= 1920 && h <= 1080 && fps > 0 && (fps <= 30 || (h <= 720 && fps <= 60))
        let firstAudio = tracks.first(where:{$0[VLCMediaTracksInformationType] as? String == VLCMediaTracksInformationTypeAudio}) ?? [:]
        let channels = (firstAudio[VLCMediaTracksInformationAudioChannelsNumber] as? NSNumber)?.intValue ?? 0
        let audioSafe = audio.count == 1 && ["aac","mp3"].contains(audio[0].codec) && channels > 0 && channels <= 2
        let lang = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "en"
        let aliases = lang == "it" ? ["it","ita"] : lang == "en" ? ["en","eng"] : [lang]
        let selected = audio.first(where:{aliases.contains($0.language.lowercased())}) ?? audio[0]
        let type = ["mp4","m4v","mov"].contains(url.pathExtension.lowercased()) ? "video/mp4" : "video/x-matroska"
        let direct = type == "video/mp4" && videoSafe && profile > 0 && audioSafe
        let duration = Double(media.length.intValue)/1000
        return RDPreparedMedia.native(audio:audio,subtitles:readTracks(VLCMediaTracksInformationTypeText),defaultAudio:selected.key,url:url,contentType:type,direct:direct,videoConversion:!videoSafe,description:"\(codec(video).uppercased()) · \(w)×\(h)",duration:duration)
    }

    static func outputChain(videoMode:VideoMode,copyAudio:Bool = false,burn:Bool = false,access:String,target:String) -> String {
        let webm = videoMode == .softwareVP8
        var conversion = webm ? "acodec=vorb,ab=192,channels=2" : copyAudio ? "" : "acodec=mp4a,ab=192,channels=2"
        func append(_ value: String) { conversion += (conversion.isEmpty ? "" : ",") + value }
        switch videoMode {
        case .copy: break
        case .hardwareH264: append("vcodec=h264,venc=avcodec{codec=h264_videotoolbox},vb=6000,maxwidth=1920,maxheight=1080,fps=30")
        case .softwareVP8: append("vcodec=VP80,venc=vpx{deadline=1,cpu-used=8,threads=4},vb=5000,maxwidth=1920,maxheight=1080,fps=30")
        }
        if burn { append("soverlay") }
        let mux = webm ? "avformat{mux=webm,options={live=1},reset-ts}" : "avformat{mux=mp4,options={movflags=frag_keyframe+empty_moov+default_base_moof},reset-ts}"
        let processing = conversion.isEmpty ? "" : "transcode{\(conversion)}:"
        return "#\(processing)std{access=\(access),mux=\(mux),dst=\(target)}"
    }
    func start(input:URL, deviceIP:String, start:Double, videoMode:VideoMode, audioID:Int?, subtitleID:Int?, style:SubtitleAppearance, copyAudio:Bool = false, repairAudio:Bool = false, audioIndex:Int = 0, subtitleIndex:Int? = nil, captions:[Int:String] = [:], selfTest:Bool = false) async throws -> URL {
        guard selfTest || CastWire.localIPv4(deviceIP) else { throw EmbeddedMediaError.address }
        offset = start.isFinite ? max(0,start) : 0
        let localIP = selfTest ? "127.0.0.1" : try Self.localAddress(to:deviceIP)
        let port = try Self.freeLoopbackPort()
        contentType = videoMode == .softwareVP8 ? "video/webm" : "video/mp4"
        let rebased = try captions.mapValues { try WebVTTTimeline.rebased($0,offset:offset) }
        let bridge = LocalStreamProxy(localIP:localIP,peer:selfTest ? "127.0.0.1" : deviceIP,producerPort:port,contentType:contentType,captions:rebased)
        proxy = bridge
        let url = try await bridge.start()
        captionURLs = Dictionary(uniqueKeysWithValues:rebased.keys.map{($0,url.deletingLastPathComponent().appendingPathComponent("subtitle-\($0).vtt"))})
        try Task.checkCancellation()
        var producerInput = input
        if repairAudio {
            let repair = AudioRepairPipe(); audioRepair = repair
            producerInput = try await repair.start(input:input,position:offset,audioIndex:audioIndex,subtitleIndex:subtitleIndex)
        }
        let media = VLCMedia(url:producerInput)
        if repairAudio { media.addOption(":demux=avformat"); media.addOption(":stream-filter=cache_read") }
        let chain = Self.outputChain(videoMode:videoMode,copyAudio:copyAudio || repairAudio,burn:subtitleID != nil,access:"http",target:"127.0.0.1:\(port)\(bridge.path)")
        media.addOption(":sout=\(chain)")
        media.addOption(":no-sout-all")
        media.addOption(":sout-keep")
        media.addOption(":start-paused")
        media.addOption(":sout-mux-caching=4000")
        if !repairAudio { media.addOption(":start-time=\(offset)") }
        // Start paused without pre-reading a full GOP before HTTP joins.
        // The mux and receiver still maintain their playback buffers.
        media.addOption(":network-caching=0")
        media.addOption(":file-caching=0")
        if let audioID, !repairAudio { media.addOption(":audio-track-id=\(audioID)") }
        if let subtitleID {
            media.addOption(repairAudio ? ":sub-track=0" : ":sub-track-id=\(subtitleID)")
            let font = style.font == "serif" ? "Georgia" : style.font == "mono" ? "Courier New" : "Arial"
            media.addOption(":freetype-font=\(font)")
            media.addOption(":freetype-rel-fontsize=\(Int(18/style.scale))")
            let color = ["white":0xffffff,"yellow":0xffff00,"cyan":0x00ffff,"green":0x00ff00][style.color] ?? 0xffffff
            media.addOption(":freetype-color=\(color)")
            media.addOption(":freetype-background-opacity=\(Int(style.background*255))")
            media.addOption(":freetype-outline-thickness=\(style.outline ? 2 : 0)")
        } else { media.addOption(":no-spu"); media.addOption(":no-sout-spu") }
        let player = VLCMediaPlayer(options:["--quiet","--no-video-title-show"])
#if CAST_ENGINE_TESTING
        if selfTest {
            let folder = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
            NativeEngineValidation.log(player,to:folder.appendingPathComponent("gateway-\(String(describing:videoMode)).log"))
        }
#endif
        self.player = player
        running = true
        observeLifecycle()
#if CAST_ENGINE_TESTING
        NativeEngineValidation.trace("native audio session start")
#endif
        updateBackground()
#if CAST_ENGINE_TESTING
        NativeEngineValidation.trace("native producer start paused")
#endif
        player.delegate = self; player.media = media; player.play()
        for _ in 0..<1400 {
            try Task.checkCancellation()
            if player.state == .error || audioRepair?.failed == true { stop(); throw EmbeddedMediaError.encoder }
            do {
                try await withTaskCancellationHandler(operation:{try await bridge.prepare(onHeaders:{ [weak self, weak player] in
                    Task { @MainActor in
                        guard let self, let player else { return }
#if CAST_ENGINE_TESTING
                        NativeEngineValidation.trace("native reader connected")
#endif
                        self.initialResume?.cancel()
                        self.initialResume = Task {
                            for _ in 0..<200 {
                                guard !Task.isCancelled, self.running else { return }
                                if player.state == .error { return }
                                // VLCKit's cached state can be overwritten by
                                // ES-added/buffering events while input is paused.
                                // PLAY is idempotent; retry until initialization
                                // arrives instead of waiting on that cached state.
                                player.play()
                                try? await Task.sleep(nanoseconds:250_000_000)
                            }
                        }
                    }
                })},onCancel:{bridge.stop()})
                initialResume?.cancel(); initialResume = nil
                updateBackground()
                streamURL = url; startedStream = true
                return url
            } catch LocalStreamError.upstream { try Task.checkCancellation() }
            catch { stop(); throw EmbeddedMediaError.encoder }
            try await Task.sleep(nanoseconds:5_000_000)
        }
        stop(); throw EmbeddedMediaError.timeout
    }
    func stop() {
        running = false; startedStream = false; onFailure = nil
        initialResume?.cancel(); initialResume = nil
        backgroundPlayer?.stop(); backgroundPlayer = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }; observers = []
        proxy?.stop(); proxy = nil; streamURL = nil
        audioRepair?.stop(); audioRepair = nil
        let old = player; player = nil; old?.delegate = nil
        if let old {
#if CAST_ENGINE_TESTING
            testingStopCompleted = false
#endif
            DispatchQueue.global(qos:.utility).async { [weak self] in
                old.stop()
#if CAST_ENGINE_TESTING
                Task { @MainActor [weak self] in self?.testingStopCompleted = true }
#endif
            }
        }
    }
    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor [weak self] in
            guard let self, let player = self.player else { return }
            if player.state == .ended || (self.startedStream && player.state == .stopped) { self.proxy?.producerDidEnd() }
            else if self.running && player.state == .error { self.onFailure?() }
        }
    }
    func setReceiverPaused(_ paused: Bool) {
        guard running, let player else { return }
        if paused && (player.state == .playing || player.state == .buffering) { player.pause() }
        else if !paused && player.state == .paused { player.play() }
    }
    private func observeLifecycle() {
        for name in [UIApplication.willResignActiveNotification,UIApplication.didEnterBackgroundNotification,UIApplication.didBecomeActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                Task { @MainActor in self?.updateBackground() }
            })
        }
    }
    private func updateBackground() {
        guard running else { return }
        do {
            // Same remote-playback mechanism used by the official VLC iOS app.
            // Its lifetime is restricted to an active local Cast pipeline.
            if AVAudioSession.sharedInstance().category != .playback || AVAudioSession.sharedInstance().mode != .moviePlayback {
                try? AVAudioSession.sharedInstance().setCategory(.playback,mode:.moviePlayback)
            }
            try? AVAudioSession.sharedInstance().setActive(true)
            if backgroundPlayer == nil {
                let helper = VLCMediaPlayer(options:["--demux=rawaud"])
#if CAST_ENGINE_TESTING
                let folder = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
                NativeEngineValidation.log(helper,to:folder.appendingPathComponent("gateway-background-helper.log"))
#endif
                helper.media = VLCMedia(path:"/dev/zero"); backgroundPlayer = helper
            }
            if backgroundPlayer?.isPlaying != true { backgroundPlayer?.play() }
        }
    }
    func refreshBackground() { updateBackground() }
#if CAST_ENGINE_TESTING
    private(set) var testingStopCompleted = true
    var testingBackgroundHelperPlaying: Bool { backgroundPlayer?.isPlaying == true }
    var testingProducerState: String { player.map { String($0.state.rawValue) } ?? "nil" }
#endif
    static func freeLoopbackPort() throws -> UInt16 {
        let fd = Darwin.socket(AF_INET,SOCK_STREAM,0); guard fd >= 0 else { throw EmbeddedMediaError.address }; defer { Darwin.close(fd) }
        var addr = sockaddr_in(); addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); addr.sin_family = sa_family_t(AF_INET); addr.sin_port = 0
        inet_pton(AF_INET,"127.0.0.1",&addr.sin_addr)
        let result = withUnsafePointer(to:&addr) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { Darwin.bind(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard result == 0 else { throw EmbeddedMediaError.address }
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let status = withUnsafeMutablePointer(to:&addr) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { getsockname(fd,$0,&size) } }
        guard status == 0 else { throw EmbeddedMediaError.address }; return UInt16(bigEndian:addr.sin_port)
    }
    private static func localAddress(to peer:String) throws -> String {
        let fd = Darwin.socket(AF_INET,SOCK_DGRAM,0); guard fd >= 0 else { throw EmbeddedMediaError.address }; defer { Darwin.close(fd) }
        var addr = sockaddr_in(); addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); addr.sin_family = sa_family_t(AF_INET); addr.sin_port = UInt16(8009).bigEndian
        guard inet_pton(AF_INET,peer,&addr.sin_addr) == 1 else { throw EmbeddedMediaError.address }
        let result = withUnsafePointer(to:&addr) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard result == 0 else { throw EmbeddedMediaError.address }
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let status = withUnsafeMutablePointer(to:&addr) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { getsockname(fd,$0,&size) } }
        var buffer = [CChar](repeating:0,count:Int(INET_ADDRSTRLEN))
        guard status == 0, inet_ntop(AF_INET,&addr.sin_addr,&buffer,socklen_t(buffer.count)) != nil else { throw EmbeddedMediaError.address }
        let ip = String(cString:buffer); guard CastWire.localIPv4(ip) else { throw EmbeddedMediaError.address }; return ip
    }
}
