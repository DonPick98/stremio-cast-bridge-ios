import Foundation
import ActivityKit
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
    private var appliedSeekStep=PlaybackPreferences.seekStep()
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
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value:PlaybackPreferences.seekStep())]
        center.skipForwardCommand.preferredIntervals = [NSNumber(value:PlaybackPreferences.seekStep())]
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
        let step=PlaybackPreferences.seekStep()
        if step != appliedSeekStep {
            appliedSeekStep=step
            let jump=NSNumber(value:step)
            MPRemoteCommandCenter.shared().skipBackwardCommand.preferredIntervals=[jump]
            MPRemoteCommandCenter.shared().skipForwardCommand.preferredIntervals=[jump]
        }
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


/// A single local Live Activity, independent of Now Playing and audio ownership.
@MainActor final class CastLiveActivityManager {
    private var activity:Activity<CastActivityAttributes>?
    private var pending:CastActivityAttributes.ContentState?
    private var worker:Task<Void,Never>?
    private var generation=UUID()
    private var policy=LiveActivityUpdatePolicy()
    private var lastRequest=Date.distantPast
    init() {
        let existing=Activity<CastActivityAttributes>.activities
        activity=existing.first
        for extra in existing.dropFirst(){
            Task {
                if #available(iOS 16.2,*){await extra.end(nil,dismissalPolicy:.immediate)}
                else{await extra.end(dismissalPolicy:.immediate)}
            }
        }
        // An upgrade/relaunch must not dismiss the active card unconditionally.
        // Its stale date prevents an old snapshot from pretending to be current.
        if UserDefaults.standard.object(forKey:"cast.activity.enabled") as? Bool == false {end()}
    }
    func update(title:String,status:String,position:Double,duration:Double,playing:Bool,loading:Bool) {
        guard UserDefaults.standard.object(forKey:"cast.activity.enabled") as? Bool ?? true,
              ActivityAuthorizationInfo().areActivitiesEnabled else{end();return}
        let now=Date(),running=playing && !loading,step=PlaybackPreferences.seekStep()
        guard position.isFinite,duration.isFinite,position>=0,duration>=0 else{return}
        if activity==nil {
            guard UIApplication.shared.applicationState == .active,now.timeIntervalSince(lastRequest)>=60 else{return}
        }
        guard policy.accept(title:title,status:status,playing:running,position:position,duration:duration,step:step,now:now) else{return}
        pending=CastActivityAttributes.ContentState(status:status,playing:running,position:position,duration:duration,updatedAt:now,title:String(title.prefix(180)),skipSeconds:Int(step))
        guard worker==nil else{return}
        let token=generation
        worker=Task { [weak self] in
            guard let self else{return}
            defer{if self.generation==token{self.worker=nil}}
            while !Task.isCancelled,self.generation==token,let state=self.pending {
                self.pending=nil
                if self.activity==nil {
                    guard UIApplication.shared.applicationState == .active else{self.policy=LiveActivityUpdatePolicy();return}
                    self.lastRequest=Date()
                    do {
                        let attributes=CastActivityAttributes(title:state.title ?? "Cast Bridge")
                        if #available(iOS 16.2,*) {
                            self.activity=try Activity<CastActivityAttributes>.request(attributes:attributes,content:ActivityContent(state:state,staleDate:Date().addingTimeInterval(75)),pushType:nil)
                        } else {self.activity=try Activity<CastActivityAttributes>.request(attributes:attributes,contentState:state,pushType:nil)}
                    } catch {
                        self.policy=LiveActivityUpdatePolicy()
                        PlaybackDiagnostics.record(.error,PlaybackDiagnostics.errorFields(error,phase:"activity_start"));return
                    }
                }
                guard let current=self.activity else{return}
                if #available(iOS 16.2,*) {await current.update(ActivityContent(state:state,staleDate:Date().addingTimeInterval(75)))}
                else {await current.update(using:state)}
            }
        }
    }
    func end() {
        generation=UUID();worker?.cancel();worker=nil;pending=nil;policy=LiveActivityUpdatePolicy();lastRequest = .distantPast
        guard let current=activity else{return}
        activity=nil
        Task {
            if #available(iOS 16.2,*) {await current.end(nil,dismissalPolicy:.immediate)}
            else {await current.end(dismissalPolicy:.immediate)}
        }
    }
}
