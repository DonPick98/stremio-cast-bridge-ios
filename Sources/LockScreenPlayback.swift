import Foundation
import MediaPlayer
import UIKit
import AVFAudio
import MobileVLCKit

/// The system media card provides the draggable Lock Screen/Control Center
/// scrubber. It is the only playback surface on the Lock Screen.
@MainActor final class LockScreenPlayback {
    var handler: ((String) async -> Bool)?
    private(set) var active = false
    private var local = false
    private var helper: VLCMediaPlayer?
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
        let target = command.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.active else { return }
                _ = await self.handler?(action)
            }
            return .success
        }
        targets.append((command,target))
    }
    func update(title:String,device:String,position:Double,duration:Double,playing:Bool,loading:Bool,local:Bool) {
        active = true; self.local = local
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
    func clear() {
        active = false; seekTask?.cancel(); seekTask = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        for (command,_) in targets { command.isEnabled = false }
        helper?.stop(); helper = nil
    }
    private func updateBackground() {
        guard active, !local else { helper?.stop(); helper = nil; return }
        if helper?.isPlaying == true { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback,mode:.moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        if helper == nil { let player = VLCMediaPlayer(options:["--demux=rawaud"]); player.media = VLCMedia(path:"/dev/zero"); helper = player }
        if helper?.isPlaying != true { helper?.play() }
    }
}
