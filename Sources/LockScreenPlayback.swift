import Foundation
import ActivityKit
import MediaPlayer
import UIKit
import AVFAudio
import MobileVLCKit
import BackgroundTasks

/// Finite UIKit assertion. Expiration always ends the assertion immediately;
/// cancellation work may finish asynchronously without risking a watchdog kill.
@MainActor final class CastBackgroundLease {
    private var identifier:UIBackgroundTaskIdentifier = .invalid
    private var expired=false
    var valid:Bool {identifier != .invalid}
    init(name:String,onExpiration:@escaping @MainActor ()->Void = {}) {
        let id=UIApplication.shared.beginBackgroundTask(withName:name) { [weak self] in
            guard let self else{return}
            self.expired=true;self.end()
            PlaybackDiagnostics.record(.app,["phase":"background_work_expired","kind":name])
            onExpiration()
        }
        if expired {if id != .invalid {UIApplication.shared.endBackgroundTask(id)}}
        else {identifier=id}
    }
    func end() {
        let id=identifier;identifier = .invalid
        if id != .invalid {UIApplication.shared.endBackgroundTask(id)}
    }
}

/// A user-started, finite video delivery job. iOS 26+ owns the execution
/// assertion; audio ownership alone is not a hardware-encoder assertion.
/// No GPU entitlement is requested by the sideload build. VideoToolbox can
/// still invalidate its own session and must retain the bounded recovery path.
@MainActor final class CastBackgroundProcessing {
    private var state=BackgroundPlaybackWork()
    private var identifier:String?
    private var baseIdentifier:String?
    private var task:BGTask?
    private var onExpiration:(()->Void)?
    private var registered=false
    private var available=false
    private var attempted=false
    private var lastProgressAt:TimeInterval?
    var active:Bool {state.active}
    func register() {
        guard !registered else{return};registered=true
        guard #available(iOS 26.0,*),let bundle=Bundle.main.bundleIdentifier else{return}
        let id=bundle+".caststream"
        let permitted=Bundle.main.object(forInfoDictionaryKey:"BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        guard permitted.contains(where:{$0==id || ($0.hasSuffix(".*") && id.hasPrefix(String($0.dropLast())))}) else {
            PlaybackDiagnostics.record(.app,["phase":"continued_unavailable","code":"bundle_mismatch"]);return
        }
        baseIdentifier=id
        available=true
    }
    func begin(duration:Double,position:Double,onExpiration:@escaping ()->Void) {
        if state.active {rebase(duration:duration,position:position);return}
        guard !state.active,!attempted else{return}
        // No deferred queue or automatic resubmission after system cancellation.
        guard #available(iOS 26.0,*),UIApplication.shared.applicationState == .active else{return}
        register();attempted=true
        guard available,let base=baseIdentifier,state.begin(duration:duration,position:position) else{return}
        let id=base+"."+UUID().uuidString
        identifier=id;self.onExpiration=onExpiration
        let accepted=BGTaskScheduler.shared.register(forTaskWithIdentifier:id,using:.main) { [weak self] delivered in
            Task { @MainActor [weak self] in
                guard let self,let continued=delivered as? BGContinuedProcessingTask,
                      self.identifier==id,self.state.active,self.task==nil else {delivered.setTaskCompleted(success:false);return}
                self.task=continued
                continued.expirationHandler={ [weak self,weak continued] in
                    Task { @MainActor [weak self,weak continued] in
                        guard let self,let continued,self.task === continued else{return}
                        let handler=self.onExpiration
                        self.recordSnapshot(phase:"continued_expired")
                        self.finish(success:false)
                        handler?()
                    }
                }
                self.applyProgress()
                PlaybackDiagnostics.record(.app,["phase":"continued_active"])
            }
        }
        guard accepted else {
            state.finish();self.onExpiration=nil
            PlaybackDiagnostics.record(.app,["phase":"continued_unavailable","code":"registration"]);return
        }
        let request=BGContinuedProcessingTaskRequest(identifier:id,title:"Trasmissione al Chromecast",subtitle:"Preparazione e invio del video")
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
            PlaybackDiagnostics.record(.app,["phase":"continued_submitted"])
        } catch {
            state.finish();self.onExpiration=nil
            let e=error as NSError
            PlaybackDiagnostics.record(.app,["phase":"continued_unavailable","code":String(e.code)])
        }
    }
    func update(position:Double?) {
        let before=state.completed
        state.update(position:position)
        if state.completed>before {lastProgressAt=ProcessInfo.processInfo.systemUptime}
        applyProgress()
    }
    func rebase(duration:Double,position:Double) {
        state.rebase(duration:duration,position:position);applyProgress()
        recordSnapshot(phase:"continued_rebase")
    }
    func recordSnapshot(phase:String="continued_progress") {
        guard state.active else{return}
        PlaybackDiagnostics.record(.app,["phase":phase,"completed":String(state.completed),"total":String(state.total),
            "seconds":lastProgressAt.map{PlaybackDiagnostics.number(max(0,ProcessInfo.processInfo.systemUptime-$0))} ?? "unknown"])
    }
    private func applyProgress() {
        guard #available(iOS 26.0,*),let task=task as? BGContinuedProcessingTask else{return}
        task.progress.totalUnitCount=state.total
        task.progress.completedUnitCount=state.completed
    }
    func finish(success:Bool=false) {
        let current=task;task=nil;onExpiration=nil;state.finish();lastProgressAt=nil
        if let identifier {BGTaskScheduler.shared.cancel(taskRequestWithIdentifier:identifier)}
        identifier=nil
        current?.expirationHandler=nil;current?.setTaskCompleted(success:success)
        // A new source or explicit retry may make a new foreground request.
        attempted=false
    }
}

/// One audio session/helper for all local producers and caption workers.
/// Owners are reference-counted by identity so a replaced engine cannot stop
/// the background support already acquired by its successor.
@MainActor final class CastAudioSession {
    static let shared = CastAudioSession()
    private var owners = Set<String>()
    private var helper:VLCMediaPlayer?
    private var interrupted = false
    private var transitionTask:CastBackgroundLease?
    private var transitionExpired=false
    private var observers:[NSObjectProtocol] = []
    var isPlaying:Bool { helper?.isPlaying == true }
    private init() {
        let center = NotificationCenter.default
        for name in [UIApplication.willResignActiveNotification,UIApplication.didEnterBackgroundNotification,UIApplication.didBecomeActiveNotification] {
            observers.append(center.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else{return}
                    if name == UIApplication.didBecomeActiveNotification {self.transitionExpired=false}
                    if !self.owners.isEmpty {self.beginTransition()}
                    self.activate(cause:"lifecycle")
                }
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
        if inserted || !isPlaying { beginTransition();activate(cause:"acquire") }
    }
    func release(_ owner:String) {
        guard owners.remove(owner) != nil else {return}
        if !owners.isEmpty {
            if owner == "now_playing" {activate(cause:"release")}
            return
        }
        endTransition();transitionExpired=false
        helper?.stop(); helper = nil
        do { try AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation) }
        catch { PlaybackDiagnostics.record(.error,PlaybackDiagnostics.errorFields(error,phase:"audio_deactivate")) }
        PlaybackDiagnostics.record(.app,["phase":"audio_idle"])
    }
    private func beginTransition() {
        guard transitionTask == nil,!transitionExpired else{return}
        transitionTask=CastBackgroundLease(name:"Cast service transition") { [weak self] in
            guard let self else{return}
            self.transitionExpired=true;self.endTransition()
            PlaybackDiagnostics.record(.app,["phase":"background_lease_expired"])
        }
        PlaybackDiagnostics.record(.app,["phase":"background_lease","result":transitionTask?.valid == true ? "acquired":"unavailable"])
    }
    private func endTransition() {
        transitionTask?.end();transitionTask=nil
    }
    private func activate(cause:String) {
        guard !owners.isEmpty, !interrupted else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            // Apple's Now Playing eligibility requires a non-mixable session.
            // Preparation-only workers keep mixing; the media card owns this
            // choice independently of which engine currently supplies bytes.
            let options:AVAudioSession.CategoryOptions=owners.contains("now_playing") ? []:[.mixWithOthers]
            if session.category != .playback || session.mode != .moviePlayback || session.categoryOptions != options {
                try session.setCategory(.playback,mode:.moviePlayback,options:options)
            }
            try session.setActive(true)
            if helper == nil {
                let player = VLCMediaPlayer(options:["--demux=rawaud"])
                player.media = VLCMedia(path:"/dev/zero"); helper = player
            }
            if !isPlaying { helper?.play() }
            PlaybackDiagnostics.shared.changed("audio_session",event:.app,["phase":"audio_active","kind":cause,"tracks":String(owners.count),"mode":session.categoryOptions.contains(.mixWithOthers) ? "mixed":"primary"])
        } catch { PlaybackDiagnostics.record(.error,PlaybackDiagnostics.errorFields(error,phase:"audio_activate")) }
    }
}

/// The system media card provides the draggable Lock Screen/Control Center
/// scrubber. It is the only playback surface on the Lock Screen.
@MainActor final class LockScreenPlayback {
    private var appliedSeekStep=PlaybackPreferences.seekStep()
    var handler: ((String) async -> Bool)?
    private(set) var active = false
    private var observers: [NSObjectProtocol] = []
    private var targets: [(MPRemoteCommand,Any)] = []
    private var seekTask: Task<Void,Never>?
    private var artwork: MPMediaItemArtwork?
    private var publishPolicy=SystemMediaPublishPolicy()
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
        for name in [UIApplication.willResignActiveNotification,UIApplication.didEnterBackgroundNotification,UIApplication.didBecomeActiveNotification,AVAudioSession.interruptionNotification,AVAudioSession.routeChangeNotification,AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in
                self?.publishPolicy.reset();self?.updateBackground()
            } })
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
        active = true
        // Activate the eligible audio session before publishing metadata.
        updateBackground()
        let step=PlaybackPreferences.seekStep()
        if step != appliedSeekStep {
            appliedSeekStep=step
            let jump=NSNumber(value:step)
            MPRemoteCommandCenter.shared().skipBackwardCommand.preferredIntervals=[jump]
            MPRemoteCommandCenter.shared().skipForwardCommand.preferredIntervals=[jump]
        }
        let position=max(0,position.isFinite ? position:0)
        let duration=max(0,duration.isFinite ? duration:0)
        guard publishPolicy.accept(title:title,device:device,position:position,duration:duration,playing:playing,loading:loading,local:local,step:step,foreground:UIApplication.shared.applicationState == .active,now:Date()) else{return}
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
        PlaybackDiagnostics.shared.changed("now_playing",event:.app,["phase":"now_playing_publish","local":String(local),"mode":AVAudioSession.sharedInstance().categoryOptions.contains(.mixWithOthers) ? "mixed":"primary"])
        for (command,_) in targets { command.isEnabled = true }
        MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled = duration.isFinite && duration > 0
    }
    func refreshNextUpdate(){publishPolicy.reset()}
    func clear(reason:String = "clear") {
        PlaybackDiagnostics.record(.app,["phase":"now_playing_clear","kind":reason])
        active = false;publishPolicy.reset(); seekTask?.cancel(); seekTask = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        for (command,_) in targets { command.isEnabled = false }
        CastAudioSession.shared.release("now_playing")
    }
    private func updateBackground() {
        guard active else { CastAudioSession.shared.release("now_playing"); return }
        CastAudioSession.shared.acquire("now_playing")
    }
}


/// Retire only our old playback activities when upgrading. The independent
/// BGContinuedProcessingTask progress UI belongs to iOS and is not dismissed.
@MainActor enum LegacyPlaybackActivities {
    static func retire() {
        for activity in Activity<CastActivityAttributes>.activities {
            Task {
                if #available(iOS 16.2,*) {await activity.end(nil,dismissalPolicy:.immediate)}
                else {await activity.end(dismissalPolicy:.immediate)}
            }
        }
    }
}

