import Foundation
import Darwin
import MobileVLCKit
import AVFAudio

@MainActor final class CaptionProcess {
    enum Kind { case ffmpeg,probe }
    private var handle:UnsafeMutableRawPointer?
    private let kind:Kind
    private static let initialized:Void = { ffmpeg_kit_initialize(); Darwin.signal(SIGPIPE,SIG_IGN) }()
    init(_ args:[String],kind:Kind = .ffmpeg) throws {
        _ = Self.initialized; self.kind = kind
        let strings = args.map{strdup($0)!}; defer { strings.forEach{free($0)} }
        var pointers = strings.map{UnsafePointer<CChar>($0) as UnsafePointer<CChar>?}
        handle = pointers.withUnsafeMutableBufferPointer { p in
            kind == .ffmpeg ? ffmpeg_kit_create_session_from_argv(Int32(args.count),p.baseAddress) : media_information_create_session_from_argv(Int32(args.count),p.baseAddress)
        }
        guard let handle else { throw CaptionFailure.process }
        if kind == .ffmpeg { ffmpeg_kit_session_execute_async(handle) }
        else { media_information_session_execute_async(handle,10000) }
    }
    var finished:Bool { guard let handle else { return true }; return [2,3].contains(Int(ffmpeg_kit_session_get_state(handle))) }
    var successful:Bool { guard let handle else { return false }; return finished && ffmpeg_kit_session_get_return_code(handle) == 0 }
    func information() throws -> Data {
        guard let handle, successful, let info = media_information_session_get_media_information(handle) else { throw CaptionFailure.probe }
        defer { ffmpeg_kit_handle_release(info) }
        guard let pointer = media_information_get_all_properties_json(info) else { throw CaptionFailure.probe }
        defer { ffmpeg_kit_free(pointer) }
        let count = strnlen(pointer,2_097_153); guard count <= 2_097_152 else { throw CaptionFailure.limit }
        return Data(bytes:pointer,count:count)
    }
    func wait(seconds:Double) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !finished {
            try Task.checkCancellation(); guard Date() < deadline else { throw CaptionFailure.timeout }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        guard successful else { throw CaptionFailure.process }
    }
    func stop(keeping object:AnyObject? = nil,afterRelease:(@Sendable ()->Void)? = nil) {
        guard let handle else { return }; self.handle = nil
        if kind == .ffmpeg { ffmpeg_kit_session_cancel(handle) }
        else { ffprobe_kit_cancel_session(ffmpeg_kit_session_get_session_id(handle)) }
        DispatchQueue.global(qos:.utility).async { ffmpeg_kit_handle_release(handle); withExtendedLifetime(object){};afterRelease?() }
    }
}

@MainActor final class CaptionExtractor {
    private var process:CaptionProcess?
    private var task:Task<Void,Never>?
    private var directory:URL?
    private var generation = UUID()
    static func catalog(_ input:URL) async throws -> CaptionCatalog {
        guard input.isFileURL || (input.scheme == "https" && input.user == nil && input.password == nil) else { throw CaptionFailure.input }
        var args = ["-v","quiet","-probesize","8388608","-analyzeduration","3000000","-print_format","json","-show_streams","-show_format"]
        if !input.isFileURL { args += ["-rw_timeout","5000000","-tls_verify","1"] }
        args += [input.isFileURL ? input.path : input.absoluteString]
        let process = try CaptionProcess(args,kind:.probe); defer { process.stop() }
        try await process.wait(seconds:12)
        return try CaptionCatalog.parse(process.information())
    }
    /// A standard Cast text track must be a complete document. Never serve a
    /// ninety-second extraction window as if it covered the whole movie.
    static func fullDocument(input:URL,track:CaptionTrack) async throws -> String {
        let result=try await fullDocuments(input:input,tracks:[track])
        guard let text=result[track.index] else{throw CaptionFailure.process};return text
    }
    /// One demux pass prepares the selected language and a few alternatives.
    /// Each output is complete and independently bounded; never publish partial files.
    static func fullDocuments(input:URL,tracks:[CaptionTrack],progress:((Double)->Void)? = nil) async throws -> [Int:String] {
        guard !tracks.isEmpty,tracks.count<=4,Set(tracks.map{$0.index}).count==tracks.count,tracks.allSatisfy({$0.isText}),input.isFileURL || (input.scheme == "https" && input.user == nil && input.password == nil) else{throw CaptionFailure.input}
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("CastFullCaption-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        var cleanupWithProcess=false
        defer{if !cleanupWithProcess{try? FileManager.default.removeItem(at:directory)}}
        let files=tracks.map{directory.appendingPathComponent("\($0.index).vtt")}
        var args=["-hide_banner","-nostdin","-loglevel","error","-nostats","-y","-copyts"]
        if !input.isFileURL{args += ["-rw_timeout","5000000","-tls_verify","1"]}
        args += ["-i",input.isFileURL ? input.path:input.absoluteString]
        for (track,file) in zip(tracks,files){args += ["-map","0:\(track.index)","-an","-vn","-dn","-c:s","webvtt","-fs","1048577","-f","webvtt",file.path]}
        let audioOwner="caption-"+UUID().uuidString
        CastAudioSession.shared.acquire(audioOwner)
        defer{CastAudioSession.shared.release(audioOwner)}
        let process=try CaptionProcess(args);cleanupWithProcess=true
        defer{process.stop(afterRelease:{try? FileManager.default.removeItem(at:directory)})}
        let started=Date(),deadline=Date().addingTimeInterval(120)
        var lastProgress = -1
        while !process.finished{
            try Task.checkCancellation()
            guard Date()<deadline else{throw CaptionFailure.timeout}
            if let size=try? files[0].resourceValues(forKeys:[.fileSizeKey]).fileSize,size>1_048_576{throw CaptionFailure.limit}
            let elapsed=Date().timeIntervalSince(started)
            if Int(elapsed) != lastProgress{lastProgress=Int(elapsed);progress?(elapsed)}
            try await Task.sleep(nanoseconds:100_000_000)
        }
        try Task.checkCancellation();guard process.successful else{throw CaptionFailure.process}
        var results:[Int:String]=[:]
        for (track,file) in zip(tracks,files){
            guard let size=try? file.resourceValues(forKeys:[.fileSizeKey]).fileSize,size<=1_048_576 else{
                if track.index==tracks[0].index{throw CaptionFailure.limit};continue
            }
            let data=try Data(contentsOf:file)
            // An empty optional track must not discard the selected document.
            if let text=try? SubtitleDocument.normalize(data+Data([10])){results[track.index]=text}
        }
        guard results[tracks[0].index] != nil else{throw CaptionFailure.process}
        return results
    }
    static func fonts(_ input:URL,catalog:CaptionCatalog) async throws -> [CaptionFontData] {
        guard !catalog.fonts.isEmpty else{return []}
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("CastFonts-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:directory)}
        var args=["-hide_banner","-nostdin","-loglevel","error","-y"]
        for font in catalog.fonts{args += ["-dump_attachment:\(font.index)",directory.appendingPathComponent("\(font.index).\(font.kind)").path]}
        if !input.isFileURL{args += ["-rw_timeout","5000000","-tls_verify","1"]}
        args += ["-i",input.isFileURL ? input.path:input.absoluteString,"-map","0:a:0","-vn","-sn","-dn","-c:a","copy","-frames:a","1","-f","null","/dev/null"]
        let process=try CaptionProcess(args);defer{process.stop()};try await process.wait(seconds:10)
        var result:[CaptionFontData]=[],total=0
        for font in catalog.fonts{
            let file=directory.appendingPathComponent("\(font.index).\(font.kind)")
            guard let size=try? file.resourceValues(forKeys:[.fileSizeKey]).fileSize,size>0,size<=2_097_152,total+size<=12_582_912 else{continue}
            let data=try Data(contentsOf:file);total+=data.count;result.append(CaptionFontData(data:data,kind:font.kind))
        }
        return result
    }
    func start(input:URL,track:CaptionTrack,format:CaptionFormat,position:Double,duration:Double,onUpdate:@escaping (CaptionSnapshot)->Void,onFailure:@escaping (CaptionFailure)->Void) throws {
        stop(); guard track.isText else { throw CaptionFailure.unsupported }
        guard input.isFileURL || (input.scheme == "https" && input.user == nil && input.password == nil) else { throw CaptionFailure.input }
        let token = UUID(); generation = token
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CastCaption-"+token.uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true); self.directory = directory
        let file = directory.appendingPathComponent("text."+format.rawValue), window = CaptionWindow(position:position,duration:duration)
        let process = try CaptionProcess(CaptionArguments.extraction(input:input.isFileURL ? input.path : input.absoluteString,track:track.index,format:format,window:window,file:file.path))
        self.process = process
        task = Task {
            let deadline = Date().addingTimeInterval(25)
            var previous = Data(), previousCoverage:Double = -1, published = false
            do {
                while !Task.isCancelled && generation == token {
                    if Date() >= deadline { throw CaptionFailure.timeout }
                    let done = process.finished
                    if done && !process.successful { throw CaptionFailure.process }
                    let coverage = done ? window.end : window.start
                    if let size = try? file.resourceValues(forKeys:[.fileSizeKey]).fileSize, size > 2_097_152 { throw CaptionFailure.limit }
                    if done, let bytes = try? Data(contentsOf:file), let body = try CaptionDocument.completePrefix(format == .vtt ? bytes+Data([10]):bytes,format:format),
                       coverage >= min(window.end,position+1), body != previous || coverage-previousCoverage >= 5 || done {
                        previous = body; previousCoverage = coverage; published = true
                        onUpdate(CaptionSnapshot(data:body,format:format,start:window.start,coveredUntil:coverage,sourceComplete:done && duration > 0 && window.end >= duration-0.05,fonts:[]))
                    }
                    if done { if !published { throw CaptionFailure.process }; break }
                    try await Task.sleep(nanoseconds:150_000_000)
                }
            } catch is CancellationError { } catch {
                if !Task.isCancelled && generation == token { onFailure(error as? CaptionFailure ?? .process) }
            }
            if generation == token { self.process?.stop(); self.process = nil }
        }
    }
    func stop() {
        generation = UUID(); task?.cancel(); task = nil
        let directory=self.directory;self.directory=nil
        if let process {process.stop(afterRelease:{if let directory{try? FileManager.default.removeItem(at:directory)}})}
        else if let directory{try? FileManager.default.removeItem(at:directory)}
        process = nil
    }
}

