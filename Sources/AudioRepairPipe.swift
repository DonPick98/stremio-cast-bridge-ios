import Foundation
import Darwin

/// Replaces only the selected unsupported audio with AAC. Video and the
/// selected subtitle pass unchanged through a 0600 FIFO, never a movie file.
@MainActor final class AudioRepairPipe {
    private static let initialized: Void = {
        ffmpeg_kit_initialize()
        ffmpeg_kit_config_set_log_level(-8)
        ffmpeg_kit_set_session_history_size(1)
        Darwin.signal(SIGPIPE,SIG_IGN)
    }()
    static func required(_ codec:String) -> Bool { ["trhd","truehd","mlp"].contains(codec.lowercased()) }
    private var handle: UnsafeMutableRawPointer?
    private var keeper: Int32 = -1
    private var monitor: Task<Void,Never>?
    private(set) var url: URL?
    private(set) var failed = false

    func start(input:URL,position:Double,audioIndex:Int,subtitleIndex:Int?) throws -> URL {
        _ = Self.initialized
        guard input.isFileURL || (input.scheme == "https" && input.user == nil && input.password == nil),
              audioIndex >= 0, position.isFinite, position >= 0 else { throw EmbeddedMediaError.encoder }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("cast-audio-\(UUID().uuidString).mkv")
        guard mkfifo(path.path,mode_t(0o600)) == 0 else { throw EmbeddedMediaError.encoder }
        url = path
        keeper = Darwin.open(path.path,O_RDWR | O_NONBLOCK)
        guard keeper >= 0 else { stop(); throw EmbeddedMediaError.encoder }
        var args = ["-hide_banner","-nostdin","-loglevel","quiet","-y"]
        if position > 0 { args += ["-ss",String(position)] }
        if !input.isFileURL { args += ["-rw_timeout","15000000","-tls_verify","1"] }
        args += ["-i",input.isFileURL ? input.path : input.absoluteString,"-map","0:v:0","-map","0:a:\(audioIndex)"]
        if let subtitleIndex { args += ["-map","0:s:\(subtitleIndex)","-c:s","copy"] }
        else { args += ["-sn"] }
        args += ["-dn","-c:v","copy","-c:a","aac","-b:a","192k","-ac","2","-avoid_negative_ts","make_zero","-f","matroska","-live","1","-cluster_time_limit","500","-flush_packets","1",path.path]
        let copies = args.map { strdup($0)! }
        defer { copies.forEach { free($0) } }
        var pointers = copies.map { UnsafePointer<CChar>($0) as UnsafePointer<CChar>? }
        handle = pointers.withUnsafeMutableBufferPointer { ffmpeg_kit_create_session_from_argv(Int32(args.count),$0.baseAddress) }
        guard let handle else { stop(); throw EmbeddedMediaError.encoder }
        ffmpeg_kit_session_execute_async(handle)
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let h = self.handle else { return }
                let state = ffmpeg_kit_session_get_state(h)
                if state == 2 || state == 3 {
                    self.failed = state == 3 || ffmpeg_kit_session_get_return_code(h) != 0
                    self.closeKeeper(); return
                }
                try? await Task.sleep(nanoseconds:100_000_000)
            }
        }
        return path
    }
    private func closeKeeper() { if keeper >= 0 { Darwin.close(keeper); keeper = -1 } }
    func stop() {
        monitor?.cancel(); monitor = nil
        if let handle {
            ffmpeg_kit_session_cancel(handle)
            // The backend can wait for its worker to exit when releasing the
            // last handle. Never block the player/UI during a seek or stop.
            DispatchQueue.global(qos:.utility).async { ffmpeg_kit_handle_release(handle) }
        }
        handle = nil; closeKeeper()
        if let url { Darwin.unlink(url.path) }; url = nil
    }
}
