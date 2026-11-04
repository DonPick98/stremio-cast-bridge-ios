import Foundation
import MediaPlayer
import UIKit
import AVFAudio
import MobileVLCKit

/// One audio session/helper for all local producers and caption workers.
/// Owners are reference-counted by identity so a replaced engine cannot stop
/// the background support already acquired by its successor.
@MainActor final class CastAudioSession {
    static let shared = CastAudioSession()
    private var owners = Set<String>()
    private var helper:VLCMediaPlayer?
    private var interrupted = false
    private var observers:[NSObjectProtocol] = []
    var isPlaying:Bool { helper?.isPlaying == true }
    private init() {
        let center = NotificationCenter.default
        for name in [UIApplication.didEnterBackgroundNotification,UIApplication.didBecomeActiveNotification] {
            observers.append(center.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                Task { @MainActor in self?.activate(cause:"lifecycle") }
            })
        }
        observers.append(center.addObserver(forName:AVAudioSession.interruptionNotification,object:nil,queue:.main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue ?? 0
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
            Task { @MainActor in
                guard let self else { return }
                self.interrupted = type == AVAudioSession.InterruptionType.began.rawValue
                PlaybackDiagnostics.record(.app,["phase":"audio_interruption","code":String(type),"status":String(options),"tracks":String(self.owners.count)])
                if !self.interrupted { self.activate(cause:"interruption_end") }
            }
        })
        for name in [AVAudioSession.routeChangeNotification,AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(center.addObserver(forName:name,object:nil,queue:.main) { [weak self] note in
                let reset = note.name == AVAudioSession.mediaServicesWereResetNotification
                let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue ?? 0
                Task { @MainActor in
                    guard let self else { return }
                    PlaybackDiagnostics.record(.app,["phase":reset ? "audio_reset":"audio_route","code":String(reason)])
                    if reset { self.helper?.stop(); self.helper = nil; self.interrupted = false }
                    self.activate(cause:reset ? "reset":"route")
                }
            })
        }
    }
    func acquire(_ owner:String) {
        let inserted = owners.insert(owner).inserted
        if inserted || !isPlaying { activate(cause:"acquire") }
    }
    func release(_ owner:String) {
        guard owners.remove(owner) != nil, owners.isEmpty else { return }
        helper?.stop(); helper = nil
        do { try AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation) }
        catch { PlaybackDiagnostics.record(.error,PlaybackDiagnostics.errorFields(error,phase:"audio_deactivate")) }
        PlaybackDiagnostics.record(.app,["phase":"audio_idle"])
    }
    private func activate(cause:String) {
        guard !owners.isEmpty, !interrupted else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            // The audible output is on the TV. Other iPhone apps may play
            // audio without intentionally interrupting this local Cast service.
            if session.category != .playback || session.mode != .moviePlayback || !session.categoryOptions.contains(.mixWithOthers) {
                try session.setCategory(.playback,mode:.moviePlayback,options:[.mixWithOthers])
            }
            try session.setActive(true)
            if helper == nil {
                let player = VLCMediaPlayer(options:["--demux=rawaud"])
                player.media = VLCMedia(path:"/dev/zero"); helper = player
            }
            if !isPlaying { helper?.play() }
            PlaybackDiagnostics.shared.changed("audio_session",event:.app,["phase":"audio_active","kind":cause,"tracks":String(owners.count)])
        } catch { PlaybackDiagnostics.record(.error,PlaybackDiagnostics.errorFields(error,phase:"audio_activate")) }
    }
}

/// The system media card provides the draggable Lock Screen/Control Center
/// scrubber. It is the only playback surface on the Lock Screen.
@MainActor final class LockScreenPlayback {
    var handler: ((String) async -> Bool)?
    private(set) var active = false
    private var local = false
    private var observers: [NSObjectProtocol] = []
    private var targets: [(MPRemoteCommand,Any)] = []
    private var seekTask: Task<Void,Never>?
    private var artwork: MPMediaItemArtwork?
    init() {
        let center = MPRemoteCommandCenter.shared()
        bind(center.playCommand,"play")
        bind(center.pauseCommand,"pause")
        bind(center.togglePlayPauseCommand,"toggle")
        bind(center.stopCommand,"stop")
        center.skipBackwardCommand.preferredIntervals = [30]
        center.skipForwardCommand.preferredIntervals = [30]
        bind(center.skipBackwardCommand,"back")
        bind(center.skipForwardCommand,"forward")
        let seek = center.changePlaybackPositionCommand
        let token = seek.addTarget { [weak self] event in
            guard let value = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime, value.isFinite, value >= 0 else { return .commandFailed }
            Task { @MainActor [weak self] in
                guard let self, self.active else { return }
                self.seekTask?.cancel()
                self.seekTask = Task {
                    try? await Task.sleep(nanoseconds:250_000_000)
                    guard !Task.isCancelled else { return }
                    _ = await self.handler?("seek:\(value)")
                }
            }
            return .success
        }
        targets.append((seek,token))
        for command in [center.nextTrackCommand,center.previousTrackCommand,center.changePlaybackRateCommand,center.changeRepeatModeCommand,center.changeShuffleModeCommand] { command.isEnabled = false }
        if let icon = UIImage(systemName:"play.tv.fill",withConfiguration:UIImage.SymbolConfiguration(pointSize:128,weight:.regular)) {
            artwork = MPMediaItemArtwork(boundsSize:icon.size) { _ in icon }
        }
        for name in [UIApplication.willResignActiveNotification,UIApplication.didEnterBackgroundNotification,UIApplication.didBecomeActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.updateBackground() } })
        }
        clear()
    }
    private func bind(_ command:MPRemoteCommand,_ action:String) {
        let target = command.addTarget { [weak self] event in
            let requested:String
            if action == "back" || action == "forward" {
                guard let skip=event as? MPSkipIntervalCommandEvent,
                      let value=CastWire.skipCommand(backward:action == "back",interval:skip.interval) else{return .commandFailed}
                requested=value
            } else {requested=action}
            Task { @MainActor [weak self] in
                guard let self, self.active else { return }
                _ = await self.handler?(requested)
            }
            return .success
        }
        targets.append((command,target))
    }
    func update(title:String,device:String,position:Double,duration:Double,playing:Bool,loading:Bool,local:Bool) {
        active = true; self.local = local
        let skip=NSNumber(value:PlaybackPreferences.skipInterval())
        MPRemoteCommandCenter.shared().skipBackwardCommand.preferredIntervals=[skip]
        MPRemoteCommandCenter.shared().skipForwardCommand.preferredIntervals=[skip]
        var info: [String:Any] = [
            MPMediaItemPropertyTitle:title,
            MPMediaItemPropertyArtist:device,
            MPNowPlayingInfoPropertyMediaType:MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream:false,
            MPNowPlayingInfoPropertyElapsedPlaybackTime:max(0,position.isFinite ? position : 0),
            MPNowPlayingInfoPropertyPlaybackRate:playing && !loading ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate:1.0
        ]
        if duration.isFinite && duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        for (command,_) in targets { command.isEnabled = true }
        MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled = duration.isFinite && duration > 0
        updateBackground()
    }
    func clear(reason:String = "clear") {
        PlaybackDiagnostics.record(.app,["phase":"now_playing_clear","kind":reason])
        active = false; seekTask?.cancel(); seekTask = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        for (command,_) in targets { command.isEnabled = false }
        CastAudioSession.shared.release("now_playing")
    }
    private func updateBackground() {
        guard active, !local else { CastAudioSession.shared.release("now_playing"); return }
        CastAudioSession.shared.acquire("now_playing")
    }
}
