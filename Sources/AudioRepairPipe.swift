import Foundation
import Darwin

struct CaptionBurnDocument {
    let text:String
    let fonts:[CaptionFontData]
    let appearance:SubtitleAppearance
    let delay:Double
}

/// Copies video packets and selects/normalizes audio. fMP4 goes directly to
/// the bounded output socket; video conversion receives Matroska over loopback.
@MainActor final class AudioRepairPipe {
    private static let initialized: Void = {
        ffmpeg_kit_initialize()
        ffmpeg_kit_config_set_log_level(-8)
        ffmpeg_kit_set_session_history_size(1)
        Darwin.signal(SIGPIPE,SIG_IGN)
    }()
    static func required(_ codec:String) -> Bool { ["trhd","truehd","mlp"].contains(codec.lowercased()) }
    private var diagnosticPhase="normalize"
    private var handle: UnsafeMutableRawPointer?
    private var renderDirectory:URL?
    // Read synchronously on MainActor, while this instance still owns session.
    // No raw backend output or media identifiers enter the diagnostic report.
    func productionMetrics()->[String:String]? {
        guard let handle else{return nil}
        let count=ffmpeg_kit_session_get_statistics_count(handle)
        guard count>0,let stats=ffmpeg_kit_session_get_statistics_at(handle,count-1) else{return nil}
        defer{ffmpeg_kit_handle_release(stats)}
        let frames=ffmpeg_kit_statistics_get_video_frame_number(stats)
        let fps=ffmpeg_kit_statistics_get_video_fps(stats)
        let bytes=ffmpeg_kit_statistics_get_size(stats)
        let media=ffmpeg_kit_statistics_get_time(stats)/1000
        let wall=ffmpeg_kit_statistics_get_time_elapsed(stats)/1000
        let speed=ffmpeg_kit_statistics_get_speed(stats)
        let duplicate=ffmpeg_kit_statistics_get_dup_frames(stats),dropped=ffmpeg_kit_statistics_get_drop_frames(stats)
        guard frames>=0,bytes>=0,duplicate>=0,dropped>=0,
              [fps,media,wall,speed].allSatisfy({$0.isFinite && $0>=0}) else{return nil}
        return ["phase":diagnosticPhase,"frames":String(frames),"fps":PlaybackDiagnostics.number(fps),"bytes":String(bytes),
                "mediaSeconds":PlaybackDiagnostics.number(media),"wallSeconds":PlaybackDiagnostics.number(wall),
                "speed":PlaybackDiagnostics.number(speed),"duplicate":String(duplicate),"dropped":String(dropped)]
    }
    private var monitor: Task<Void,Never>?
    private(set) var url: URL?
    private(set) var failed = false
    private(set) var finished = false
    private(set) var exitCode:Int64?
#if CAST_ENGINE_TESTING
    private(set) var testingStopCompleted = true
    var testingOutput: URL?
    var testingRenderDirectory:URL? {renderDirectory}
    var testingASSInput:URL?
    var testingVideoToolboxDecoder=false
    var testingDuration:Double?
    private var diagnostics: URL?
    private func record(_ handle:UnsafeMutableRawPointer) {
        guard let diagnostics else { return }
        var text = "state=\(ffmpeg_kit_session_get_state(handle)) code=\(ffmpeg_kit_session_get_return_code(handle))\n"
        for pointer in [ffmpeg_kit_session_get_output(handle),session_get_debug_log(handle)] {
            if let pointer { text += String(cString:pointer)+"\n"; ffmpeg_kit_free(pointer) }
        }
        try? text.write(to:diagnostics,atomically:true,encoding:.utf8)
    }
#endif

    func start(input:URL,position:Double,audioIndex:Int,subtitleIndex:Int?,outputFD:Int32? = nil,copyAudio:Bool = false,transcodeVideo:VideoFormat? = nil,bitmapSubtitleIndex:Int? = nil,subtitleDelay:Double = 0,textCaption:CaptionBurnDocument? = nil) async throws -> URL {
        _ = Self.initialized
        diagnosticPhase=outputFD==nil ? "normalize":transcodeVideo==nil ? "remux":"encode"
        guard input.isFileURL || (input.scheme == "https" && input.user == nil && input.password == nil),
              audioIndex >= 0, position.isFinite, position >= 0 else { throw EmbeddedMediaError.encoder }
        let port = try EmbeddedMediaEngine.freeLoopbackPort()
        let path = outputFD.map { URL(string:"pipe:\($0)")! } ?? URL(string:"http://127.0.0.1:\(port)/\(UUID().uuidString).mkv")!
#if CAST_ENGINE_TESTING
        let selectedPath = testingOutput ?? path
        let folder = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        diagnostics = folder.appendingPathComponent("repair-\(UUID().uuidString).log")
        ffmpeg_kit_config_set_log_level(16)
#else
        let selectedPath = path
#endif
        var useHTTP = true
#if CAST_ENGINE_TESTING
        useHTTP = testingOutput == nil
#endif
        if outputFD != nil { useHTTP = false }
        url = selectedPath
        var textFilter:String?
        if let caption=textCaption {
            guard transcodeVideo != nil,bitmapSubtitleIndex == nil,caption.delay.isFinite,abs(caption.delay)<=300,
                  caption.text.utf8.count<=1_048_576,caption.text.hasPrefix("WEBVTT"),caption.fonts.count<=8,
                  caption.fonts.reduce(0,{$0+$1.data.count})<=12_582_912 else{throw EmbeddedMediaError.encoder}
            let directory=FileManager.default.temporaryDirectory.appendingPathComponent("CastCaptionRender-"+UUID().uuidString)
            renderDirectory=directory
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let file=directory.appendingPathComponent("document.vtt")
            try Data(caption.text.utf8).write(to:file,options:.atomic)
            for (i,font) in caption.fonts.enumerated() {
                guard ["ttf","otf","woff","woff2"].contains(font.kind),font.data.count<=2_097_152 else{throw EmbeddedMediaError.encoder}
                try font.data.write(to:directory.appendingPathComponent("font-\(i).\(font.kind)"),options:.atomic)
            }
            // Both paths are generated inside the sandbox, not provider input.
            guard file.path.range(of:"^[A-Za-z0-9/_. -]+$",options:.regularExpression) != nil else{throw EmbeddedMediaError.encoder}
            let style=caption.appearance.normalized
            let font=style.font=="serif" ? "Georgia":style.font=="mono" ? "Courier New":"Arial"
            let color=["white":"FFFFFF","yellow":"00FFFF","cyan":"FFFF00","green":"00FF00"][style.color] ?? "FFFFFF"
            let background=String(format:"%02X000000",Int((1-style.background)*255))
            let settings="FontName=\(font),FontSize=\(18*style.scale),PrimaryColour=&H00\(color),BackColour=&H\(background),BorderStyle=\(style.background>0 ? 3:1),Outline=\(style.outline ? 1.5:0),Shadow=0"
            textFilter="setpts=PTS+\(position-caption.delay)/TB,subtitles=filename='\(file.path)':fontsdir='\(directory.path)':force_style='\(settings)',setpts=PTS-STARTPTS"
        }
        var args = ["-hide_banner","-nostdin","-loglevel","quiet","-y"]
#if CAST_ENGINE_TESTING
        args[3] = "error"
#endif
        if position > 0 { args += ["-ss",String(position)] }
        if !input.isFileURL { args += ["-rw_timeout","15000000","-tls_verify","1"] }
#if CAST_ENGINE_TESTING
        // Controlled experiment only. Shipping builds keep the validated
        // decoding route until device energy and frame gates are satisfied.
        if testingVideoToolboxDecoder {args += ["-hwaccel","videotoolbox"]}
#endif
        args += ["-i",input.isFileURL ? input.path : input.absoluteString]
#if CAST_ENGINE_TESTING
        if let testingDuration,testingDuration.isFinite,testingDuration>0,testingDuration<=10 {
            args += ["-t",String(testingDuration)]
        }
#endif
        // Input seeking retains video packets from the preceding keyframe.
        // Discard negative preroll before rebasing, or an audio change can
        // replay seconds before the requested point and shift its timeline.
        if position > 0 { args += ["-ss","0"] }
        let scale="scale=w=min(1920\\,iw):h=min(1080\\,ih):force_original_aspect_ratio=decrease:force_divisible_by=2"
        if let bitmapSubtitleIndex {
            guard bitmapSubtitleIndex>=0,transcodeVideo != nil,subtitleDelay.isFinite,abs(subtitleDelay)<=300 else { throw EmbeddedMediaError.encoder }
            args += ["-filter_complex","[0:s:\(bitmapSubtitleIndex)]setpts=PTS+\(subtitleDelay)/TB[caption];[0:v:0][caption]overlay=eof_action=pass:repeatlast=0,\(scale)[picture]","-map","[picture]","-map","0:a:\(audioIndex)"]
        } else { args += ["-map","0:v:0","-map","0:a:\(audioIndex)"] }
        if let subtitleIndex { args += ["-map","0:s:\(subtitleIndex)","-c:s","copy"] }
        else { args += ["-sn"] }
        args += ["-dn"]
#if CAST_ENGINE_TESTING
        if let ass=testingASSInput,ass.isFileURL {
            // Only a local synthetic input is permitted. This is not a remote
            // subtitle-fetch implementation and cannot be enabled in release.
            let file=ass.path.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:":",with:"\\:").replacingOccurrences(of:"'",with:"'\\''")
            let filter="setpts=PTS+\(position)/TB,subtitles=filename='\(file)':si=0,setpts=PTS-STARTPTS,\(scale)"
            args += ["-vf",filter]
        }
#endif
        if let textFilter {args += ["-vf",textFilter+","+scale]}
        if let video = transcodeVideo {
            // Software decode legacy MPEG-4 ASP, then encode a Cast-compatible
            // H.264 stream directly. Do not force 30 fps or upscale SD sources.
            args += ["-c:v","h264_videotoolbox","-allow_sw","1","-realtime","1","-pix_fmt","yuv420p",
                     "-profile:v","high","-level:v","4.1","-b:v",String(video.conversionBitrate * 1000),
                     "-fps_mode",video.conversionFrameRate == nil ? "passthrough":"cfr","-g",String(video.conversionKeyframeInterval)]
            var needsScale=bitmapSubtitleIndex == nil && textFilter == nil
#if CAST_ENGINE_TESTING
            if testingASSInput != nil {needsScale=false}
#endif
            if needsScale { args += ["-vf",scale] }
            if let rate = video.conversionFrameRate { args += ["-r",String(rate)] }
        } else { args += ["-c:v","copy"] }
        if copyAudio { args += ["-c:a","copy"] }
        else { args += ["-c:a","aac","-b:a","192k","-ac","2"] }
        args += ["-max_muxing_queue_size","2048","-avoid_negative_ts","make_zero"]
        if outputFD != nil { args += ["-f","mp4","-movflags","frag_keyframe+empty_moov+default_base_moof","-flush_packets","1"] }
        else { args += ["-f","matroska","-live","1","-cluster_time_limit","500","-flush_packets","1"] }
        if useHTTP { args += ["-listen","1"] }
        args += [outputFD.map { "pipe:\($0)" } ?? (useHTTP ? selectedPath.absoluteString : selectedPath.path)]
        let copies = args.map { strdup($0)! }
        defer { copies.forEach { free($0) } }
        var pointers = copies.map { UnsafePointer<CChar>($0) as UnsafePointer<CChar>? }
        handle = pointers.withUnsafeMutableBufferPointer { ffmpeg_kit_create_session_from_argv(Int32(args.count),$0.baseAddress) }
        guard let handle else { stop(); throw EmbeddedMediaError.encoder }
#if CAST_ENGINE_TESTING
        session_enable_debug_log(handle)
#endif
        ffmpeg_kit_session_execute_async(handle)
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let h = self.handle else { return }
                let state = ffmpeg_kit_session_get_state(h)
                if state == 2 || state == 3 {
                    self.exitCode = ffmpeg_kit_session_get_return_code(h)
                    self.failed = state == 3 || self.exitCode != 0
                    self.finished = true
                    PlaybackDiagnostics.record(.producer,["phase":"ffmpeg_exit","status":String(state),"code":String(ffmpeg_kit_session_get_return_code(h))])
#if CAST_ENGINE_TESTING
                    self.record(h)
#endif
                    return
                }
                try? await Task.sleep(nanoseconds:100_000_000)
            }
        }
        if useHTTP {
            // Inspect the bind state without accepting the single HTTP client.
            // VLC then opens the connection and waits for streamed headers.
            for _ in 0..<150 {
                try Task.checkCancellation()
                if failed { throw EmbeddedMediaError.encoder }
                if Self.listening(port) { return selectedPath }
                try await Task.sleep(nanoseconds:100_000_000)
            }
            throw EmbeddedMediaError.timeout
        }
        return selectedPath
    }
    private static func listening(_ port:UInt16) -> Bool {
        let fd = Darwin.socket(AF_INET,SOCK_STREAM,0); guard fd >= 0 else { return false }; defer { Darwin.close(fd) }
        var addr = sockaddr_in(); addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); addr.sin_family = sa_family_t(AF_INET); addr.sin_port = port.bigEndian
        inet_pton(AF_INET,"127.0.0.1",&addr.sin_addr)
        let result = withUnsafePointer(to:&addr) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { Darwin.bind(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        return result != 0 && errno == EADDRINUSE
    }
    func stop() {
        let directory=renderDirectory;renderDirectory=nil
        monitor?.cancel(); monitor = nil
        if let handle {
#if CAST_ENGINE_TESTING
            record(handle)
            testingStopCompleted = false
#endif
            ffmpeg_kit_session_cancel(handle)
            // The backend can wait for its worker to exit when releasing the
            // last handle. Never block the player/UI during a seek or stop.
            DispatchQueue.global(qos:.utility).async { [weak self] in
                ffmpeg_kit_handle_release(handle)
                if let directory {try? FileManager.default.removeItem(at:directory)}
#if CAST_ENGINE_TESTING
                Task { @MainActor [weak self] in self?.testingStopCompleted = true }
#endif
            }
        }
        if handle == nil,let directory {try? FileManager.default.removeItem(at:directory)}
        handle = nil; url = nil
    }
}


