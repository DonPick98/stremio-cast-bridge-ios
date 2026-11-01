import Foundation
import Darwin

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
