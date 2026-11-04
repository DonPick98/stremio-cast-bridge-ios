import Foundation
import MobileVLCKit
import AVFAudio
import UIKit
import Darwin

enum EmbeddedMediaError: LocalizedError {
    case metadata, address, encoder, output, timeout
    var errorDescription: String? {
        switch self {
        case .metadata: return "Il motore integrato non riesce a leggere le tracce di questa sorgente."
        case .address: return "L’iPhone deve essere sulla stessa rete locale del Chromecast."
        case .encoder: return "Non riesco a preparare il video di questa sorgente (CB203)."
        case .output: return "Il flusso generato non è riproducibile (CB204)."
        case .timeout: return "Il motore integrato non ha preparato il flusso entro il tempo previsto."
        }
    }
}

@MainActor final class EmbeddedMediaEngine: NSObject, VLCMediaPlayerDelegate {
    enum VideoMode: Equatable { case copy, ffmpegH264, hardwareH264, softwareVP8 }
    static func modes(requiresVideo:Bool,fallbackLevel:Int = 0,video:VideoFormat? = nil,burn:Bool = false,bitmap:Bool = false) -> [VideoMode] {
        if burn,bitmap,fallbackLevel < 2 { return [.ffmpegH264,.hardwareH264,.softwareVP8] }
        let legacy = ["mp4v","mpeg4","divx","xvid","dx50","fmp4","mpgv","wmv2"].contains(video?.codec.lowercased() ?? "")
        // The pinned LGPL FFmpeg build lacks a working software AV1 decoder
        // on this platform; VLC's bundled decoder handles this source instead.
        if ["av01","av1"].contains(video?.codec.lowercased() ?? ""){
            return fallbackLevel >= 2 ? [.softwareVP8]:[.hardwareH264,.softwareVP8]
        }
        // Keep the packet-copy path first for compatible video. When conversion
        // is needed, FFmpeg preserves the source timestamps/frame cadence and
        // drains the encoder before ending the output. VLC remains a fallback.
        if !burn && fallbackLevel < 2 {
            if legacy || requiresVideo || fallbackLevel == 1 { return [.ffmpegH264,.hardwareH264,.softwareVP8] }
            return [.copy,.ffmpegH264,.hardwareH264,.softwareVP8]
        }
        return fallbackLevel >= 2 ? [.softwareVP8] : (requiresVideo || fallbackLevel == 1) ? [.hardwareH264,.softwareVP8] : [.copy,.hardwareH264,.softwareVP8]
    }
    private var player: VLCMediaPlayer?
    private var outputChannel: MediaOutputChannel?
    private var producerEnded = false
    private var audioRepair: AudioRepairPipe?
    private var rewindInput:RewindableInputStream?
    private var proxy: LocalStreamProxy?
    private let audioOwner = "engine-" + UUID().uuidString
    private var observers: [NSObjectProtocol] = []
    private(set) var streamURL: URL?
    private(set) var captionURLs: [Int:URL] = [:]
    private(set) var captionWindow = SubtitleWindow(center:0)
    func captionID(kind:Int,delay:Double) -> Int? {
        guard let id = captionWindow.identifier(kind:kind,delay:delay), captionURLs[id] != nil else { return nil }; return id
    }
    func setBurnedSubtitleDelay(_ delay:Double) {
        player?.currentVideoSubTitleDelay = Int(SubtitleWindow.normalized(delay)*1_000_000)
    }
    private(set) var contentType = "video/mp4"
    private(set) var offset: Double = 0
    private(set) var running = false
    private(set) var failed = false
    private(set) var usesBitmapOverlay = false
    private(set) var diagnosticMode = VideoMode.copy
    var backendExitCode:Int64? {audioRepair?.exitCode}
    private var startedStream = false
    private var directRemux = false
    private var producerMonitor: Task<Void,Never>?
    private var producerDrain: Task<Void,Never>?
    var onFailure: ((Bool) -> Void)?

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
        let format = VideoFormat(codec:codec(video),width:w,height:h,frameRate:fps,bitrate:(video[VLCMediaTracksInformationBitrate] as? NSNumber)?.intValue ?? 0,profile:profile,level:level)
        let videoSafe = !format.requiresConversion && w > 0 && h > 0 && fps > 0
        let firstAudio = tracks.first(where:{$0[VLCMediaTracksInformationType] as? String == VLCMediaTracksInformationTypeAudio}) ?? [:]
        let channels = (firstAudio[VLCMediaTracksInformationAudioChannelsNumber] as? NSNumber)?.intValue ?? 0
        let audioSafe = audio.count == 1 && ["aac","mp3"].contains(audio[0].codec) && channels > 0 && channels <= 2
        let lang = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "en"
        let aliases = lang == "it" ? ["it","ita"] : lang == "en" ? ["en","eng"] : [lang]
        let selected = audio.first(where:{aliases.contains($0.language.lowercased())}) ?? audio[0]
        let type = ["mp4","m4v","mov"].contains(url.pathExtension.lowercased()) ? "video/mp4" : "video/x-matroska"
        let direct = type == "video/mp4" && videoSafe && profile > 0 && audioSafe
        let duration = Double(media.length.intValue)/1000
        return RDPreparedMedia.native(audio:audio,subtitles:readTracks(VLCMediaTracksInformationTypeText),defaultAudio:selected.key,url:url,contentType:type,direct:direct,videoConversion:format.requiresConversion,description:"\(codec(video).uppercased()) · \(format.label)",duration:duration,video:format)
    }

    static func outputChain(videoMode:VideoMode,copyAudio:Bool = false,burn:Bool = false,video:VideoFormat? = nil,access:String,target:String) -> String {
        let webm = videoMode == .softwareVP8
        var conversion = webm ? "acodec=vorb,ab=192,channels=2" : copyAudio ? "" : "acodec=mp4a,ab=192,channels=2"
        func append(_ value: String) { conversion += (conversion.isEmpty ? "" : ",") + value }
        switch videoMode {
        case .copy: break
        case .ffmpegH264, .hardwareH264: append("vcodec=h264,venc=avcodec{codec=h264_videotoolbox},vb=\(video?.conversionBitrate ?? 10000),maxwidth=1920,maxheight=1080")
        case .softwareVP8: append("vcodec=VP80,venc=vpx{deadline=1,cpu-used=8,threads=4},vb=\(video?.conversionBitrate ?? 6000),maxwidth=1920,maxheight=1080")
        }
        if videoMode != .copy, let rate = video?.conversionFrameRate { append("fps=\(Int(rate))") }
        else if videoMode == .hardwareH264,let rate=video?.vlcFrameRate {append("fps=\(rate)")}
        if burn { append("soverlay") }
        let mux = webm ? "avformat{mux=webm,options={live=1},reset-ts}" : "avformat{mux=mp4,options={movflags=frag_keyframe+empty_moov+default_base_moof},reset-ts}"
        let processing = conversion.isEmpty ? "" : "transcode{\(conversion)}:"
        return "#\(processing)std{access=\(access),mux=\(mux),dst=\(target)}"
    }
    func start(input:URL, deviceIP:String, start:Double, videoMode:VideoMode, audioID:Int?, subtitleID:Int?, style:SubtitleAppearance, copyAudio:Bool = false, repairAudio:Bool = false, audioIndex:Int = 0, subtitleIndex:Int? = nil, captions:[Int:String] = [:], subtitleDelay:Double = 0, video:VideoFormat? = nil, selfTest:Bool = false,bitmapSubtitle:Bool = false,audioCodec:String = "") async throws -> URL {
        guard selfTest || CastWire.localIPv4(deviceIP) else { throw EmbeddedMediaError.address }
        diagnosticMode = videoMode
        offset = start.isFinite ? max(0,start) : 0
        PlaybackDiagnostics.record(.producer,["phase":"start","mode":String(describing:videoMode),"offset":PlaybackDiagnostics.number(offset),"burn":String(subtitleID != nil),"copyAudio":String(copyAudio)])
        let localIP = selfTest ? "127.0.0.1" : try Self.localAddress(to:deviceIP)
        let port = try Self.freeLoopbackPort()
        contentType = videoMode == .softwareVP8 ? "video/webm" : "video/mp4"
        captionWindow = SubtitleWindow(center:subtitleDelay)
        var rebased:[Int:Data] = [:]
        for (kind,text) in captions {
            for variant in captionWindow.variants(kind:kind) { rebased[variant.id] = try WebVTTTimeline.rebased(text,offset:offset,delay:variant.delay) }
        }
        let bridge = LocalStreamProxy(localIP:localIP,peer:selfTest ? "127.0.0.1" : deviceIP,producerPort:port,contentType:contentType,captions:rebased)
        proxy = bridge
        let url = try await bridge.start()
        let channel = try MediaOutputChannel(); outputChannel = channel
        try await channel.start(port:port,path:bridge.path,type:contentType)
        captionURLs = Dictionary(uniqueKeysWithValues:rebased.keys.map{($0,url.deletingLastPathComponent().appendingPathComponent("subtitle-\($0).vtt"))})
        try Task.checkCancellation()
        usesBitmapOverlay = videoMode == .ffmpegH264 && bitmapSubtitle && subtitleID != nil
        if ((videoMode == .copy || videoMode == .ffmpegH264) && subtitleID == nil) || usesBitmapOverlay {
            // VLC's H.264 packetizer can drop/reorder B frames on remux. FFmpeg
            // copies every original packet and normalizes the selected audio.
            directRemux = true; running = true; producerEnded = false
            observeLifecycle(); updateBackground()
            let repair = AudioRepairPipe(); audioRepair = repair
            _ = try await repair.start(input:input,position:offset,audioIndex:audioIndex,subtitleIndex:nil,outputFD:channel.writer,copyAudio:copyAudio,transcodeVideo:videoMode == .ffmpegH264 ? video : nil,bitmapSubtitleIndex:usesBitmapOverlay ? subtitleIndex:nil,subtitleDelay:subtitleDelay)
            producerMonitor = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, self.running else { return }
                    if repair.finished {
                        PlaybackDiagnostics.record(.producer,["phase":"finished","result":repair.failed ? "error" : "success"])
                        self.producerEnded = true; channel.endWriting()
                        if repair.failed { self.failProducer(allowVideoConversion:repair.exitCode != -32) }
                        return
                    }
                    try? await Task.sleep(nanoseconds:50_000_000)
                }
            }
            do { try await withTaskCancellationHandler(operation:{try await bridge.prepare()},onCancel:{bridge.stop()}) }
            catch { let failure:EmbeddedMediaError = repair.failed ? .encoder : .output; stop(); throw failure }
            try Task.checkCancellation()
            streamURL = url; startedStream = true
            return url
        }
        var producerInput = input
        // Decode overlays on the original GOP for the validated audio families.
        // Cast-incompatible audio (e.g. EAC3) still needs output conversion, but
        // does not itself require packet-copy normalization before decoding.
        // That normalization discards video preroll after a seek and delays the
        // first decodable picture until the next keyframe (e.g. +0.79 s).
        // Codecs that explicitly require repair (e.g. TrueHD) retain that path.
        let originalOverlay = subtitleID != nil && !repairAudio && (copyAudio || ["eac3","ec-3"].contains(audioCodec.lowercased()))
        let repairInput = !originalOverlay && (repairAudio || offset > 0 || subtitleID != nil)
        PlaybackDiagnostics.record(.producer,["phase":"input","kind":repairInput ? "normalized" : "original","audio":String(audioIndex),"subtitle":subtitleIndex.map{String($0)} ?? "none"])
        if repairInput {
            let repair = AudioRepairPipe(); audioRepair = repair
            producerInput = try await repair.start(input:input,position:offset,audioIndex:audioIndex,subtitleIndex:subtitleIndex)
        }
        let media:VLCMedia
        if repairInput && subtitleID != nil {
            let input = RewindableInputStream(url:producerInput); rewindInput = input
            media = VLCMedia(stream:input)
        } else { media = VLCMedia(url:producerInput) }
        // Older MPEG-4/DivX streams may not have an iOS hardware decoder.
        // This affects decoding only; H.264 encoding can still use VideoToolbox.
        if ["mp4v","mpeg4","divx","xvid","dx50","fmp4","mpgv","wmv2"].contains(video?.codec.lowercased() ?? "") { media.addOption(":avcodec-hw=none") }
        if repairInput {
            // VLC 3's avformat demux does not map FFmpeg SUBRIP/ASS subtitles
            // (it exposes them as undf). Preserve the Matroska subtitle codec,
            // private data and timestamps with VLC's native demux for overlays.
            media.addOption(subtitleID == nil ? ":demux=avformat" : ":demux=mkv")
            media.addOption(":stream-filter=cache_read")
        }
        // The engine is also callable without the app's preflight metadata.
        // Resolve cadence before configuring VLC rather than falling back to
        // its imprecise timestamp-derived encoder time base.
        let outputVideo:VideoFormat?
        if let video { outputVideo = video }
        else { outputVideo = try await Self.inspect(input).video }
        try Task.checkCancellation()
        let chain = Self.outputChain(videoMode:videoMode,copyAudio:copyAudio || repairInput,burn:subtitleID != nil,video:outputVideo,access:"fd",target:String(channel.writer))
        media.addOption(":sout=\(chain)")
        media.addOption(":no-sout-all")
        media.addOption(":no-sout-keep")
        media.addOption(":sout-mux-caching=4000")
        if !repairInput { media.addOption(":start-time=\(offset)"); media.addOption(":no-input-fast-seek") }
        media.addOption(":network-caching=1500")
        if let audioID, !repairInput { media.addOption(":audio-track-id=\(audioID)") }
        if let subtitleID {
            media.addOption(":sub-delay=\(Int(SubtitleWindow.normalized(subtitleDelay)*10))")
            media.addOption(repairInput ? ":sub-track=0" : ":sub-track-id=\(subtitleID)")
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
            NativeEngineValidation.log(player,to:folder.appendingPathComponent("gateway-\(String(describing:videoMode))-\(input.lastPathComponent).log"))
        }
#endif
        self.player = player
        running = true; producerEnded = false
        observeLifecycle()
#if CAST_ENGINE_TESTING
        NativeEngineValidation.trace("native audio session start")
#endif
        updateBackground()
#if CAST_ENGINE_TESTING
        NativeEngineValidation.trace("native producer start on socket")
#endif
        player.delegate = self; player.media = media; player.play()
        producerMonitor = Task { [weak self,weak player] in
            while !Task.isCancelled {
                guard let self, let player, self.player === player else { return }
                if self.realState(player) == 6 { self.finishProducer(player); return }
                if self.realState(player) == 7 {
                    PlaybackDiagnostics.record(.error,["phase":"vlc","code":"state7"])
                    if self.streamURL == nil { self.proxy?.stop() } else { self.failProducer(allowVideoConversion:true) }
                    return
                }
                try? await Task.sleep(nanoseconds:100_000_000)
            }
        }
        for _ in 0..<1400 {
            try Task.checkCancellation()
            if player.state == .error || audioRepair?.failed == true { stop(); throw EmbeddedMediaError.encoder }
            do {
                try await withTaskCancellationHandler(operation:{try await bridge.prepare()},onCancel:{bridge.stop()})
                // VLC's fd output has already duplicated this descriptor before
                // writing the validated header. Let that duplicate own EOF.
                channel.endWriting()
                updateBackground()
                streamURL = url; startedStream = true
                return url
            } catch LocalStreamError.upstream { try Task.checkCancellation() }
            catch {
                PlaybackDiagnostics.record(.error,["phase":"output_readiness","kind":String(describing:type(of:error)),"code":(error as? LocalStreamError).map{String(describing:$0)} ?? String((error as NSError).code),"status":realState(player).map{String($0)} ?? "unknown"])
                stop(); throw EmbeddedMediaError.output
            }
            try await Task.sleep(nanoseconds:5_000_000)
        }
        stop(); throw EmbeddedMediaError.timeout
    }
    func stop() {
        PlaybackDiagnostics.record(.producer,["phase":"stop"])
        running = false; startedStream = false; onFailure = nil; producerEnded = true
        producerMonitor?.cancel(); producerMonitor = nil
        producerDrain?.cancel(); producerDrain = nil
        let channel = outputChannel; outputChannel = nil
        channel?.stop()
        CastAudioSession.shared.release(audioOwner)
        for observer in observers { NotificationCenter.default.removeObserver(observer) }; observers = []
        proxy?.stop(); proxy = nil; streamURL = nil
        rewindInput?.close(); rewindInput = nil
#if CAST_ENGINE_TESTING
        testingStoppedRepair = audioRepair
#endif
        audioRepair?.stop(); audioRepair = nil
        let old = player; player = nil; old?.delegate = nil
        if let old {
#if CAST_ENGINE_TESTING
            testingVideoStopped = false
#endif
            DispatchQueue.global(qos:.utility).async { [weak self] in
                old.stop()
                withExtendedLifetime(channel) {}
#if CAST_ENGINE_TESTING
                Task { @MainActor [weak self] in self?.testingVideoStopped = true }
#endif
            }
        }
    }
    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        guard let origin = aNotification.object as? VLCMediaPlayer else { return }
        let state = origin.state
        Task { @MainActor [weak self, weak origin] in
            guard let self, let origin, self.player === origin else { return }
            if state == .ended || self.realState(origin) == 6 { self.finishProducer(origin) }
            else if self.running && state == .error {
                if self.streamURL == nil { self.proxy?.stop() } else { self.failProducer(allowVideoConversion:true) }
            }
        }
    }
    func setReceiverPaused(_ paused: Bool) {
        guard running else { return }
        if directRemux { proxy?.setPaused(paused); return }
        guard !producerEnded, let player else { return }
        if paused { player.pause() }
        // Pause is asynchronous and may still be queued under backpressure.
        // Always enqueue PLAYING, even if isPlaying has not changed yet.
        else { player.play() }
    }
    private func failProducer(allowVideoConversion:Bool) {
        guard !failed else { return }
        failed = true; running = false
        onFailure?(allowVideoConversion)
    }
    private func finishProducer(_ origin:VLCMediaPlayer) {
        guard !producerEnded, player === origin else { return }
        producerEnded = true; producerMonitor?.cancel(); producerMonitor = nil
        // VLC announces END_S before deleting decoders and flushing the muxer
        // (src/input/input.c, End). stop() here can cancel the final write while
        // the receiver is applying backpressure. Keep the player alive and let
        // its output duplicate close naturally after the trailer is delivered.
        // Explicit user stop/cancellation still tears down the channel promptly.
        let channel = outputChannel
        producerDrain = Task { [weak self, weak origin] in
            guard let channel, await channel.waitForDrain(), !Task.isCancelled,
                  let self, let origin, self.player === origin else { return }
            self.player = nil
            DispatchQueue.global(qos:.utility).async { origin.stop(); channel.endWriting() }
        }
    }
    private typealias StateFunction = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias PlayerPointer = @convention(c) (AnyObject,Selector) -> UnsafeMutableRawPointer?
    private static let stateFunction: StateFunction? = {
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern:-2),"libvlc_media_player_get_state") else { return nil }
        return unsafeBitCast(pointer,to:StateFunction.self)
    }()
    // VLCKit's public state cache can be overwritten by ES-added notifications.
    // The pinned library exposes this pointer; fall back safely if unavailable.
    private func realState(_ player:VLCMediaPlayer) -> Int32? {
        let selector = NSSelectorFromString("libVLCMediaPlayer")
        guard let function = Self.stateFunction, player.responds(to:selector), let method = player.method(for:selector),
              let pointer = unsafeBitCast(method,to:PlayerPointer.self)(player,selector) else { return nil }
        return function(pointer)
    }
    private func observeLifecycle() {
        // CastAudioSession owns lifecycle and audio interruption observers.
    }
    private func updateBackground() {
        guard running else { return }
        CastAudioSession.shared.acquire(audioOwner)
    }
    func refreshBackground() { updateBackground() }
    func productionMetrics()->[String:String]? { audioRepair?.productionMetrics() }
    func transferMetrics() async -> LocalTransferMetrics? { await proxy?.transferMetrics() }
#if CAST_ENGINE_TESTING
    private var testingVideoStopped = true
    private var testingStoppedRepair: AudioRepairPipe?
    var testingStopCompleted: Bool { testingVideoStopped && (testingStoppedRepair?.testingStopCompleted ?? true) }
    func testingDeliveredBytes() async -> Int { await proxy?.testingDeliveredBytes() ?? 0 }
    func testingPauseDrained() async -> Bool { await proxy?.testingPauseDrained() ?? false }
    var testingBackgroundHelperPlaying: Bool { CastAudioSession.shared.isPlaying }
    var testingProducerPlaying: Bool { player?.isPlaying == true }
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
    static func localAddress(to peer:String) throws -> String {
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


