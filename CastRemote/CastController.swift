import Foundation
import GoogleCast
import SwiftUI
import ActivityKit
import CryptoKit
import UIKit
import AVFAudio

@MainActor final class CastController: NSObject, ObservableObject, GCKRequestDelegate, GCKSessionManagerListener, GCKRemoteMediaClientListener {
    @Published private(set) var episodes:[SeriesEpisode]=[]
    @Published private(set) var episodeIssue:String?
    @Published private(set) var episodeBusy=false
    @Published private(set) var fallbackEpisode:SeriesEpisode?
    private var episodeTask:Task<Void,Never>?
    private var episodeRequest=UUID()
    private var requireEpisodeLanguage=false
    private struct EpisodeAutoplay {
        let content:String
        let target:SeriesEpisode
        let sources:[String:AddonStream]
        var plan:AutoplayRetryPlan
    }
    private var episodeAutoplay:EpisodeAutoplay?
    private var returnedEpisodes=Set<String>()
    private func returnToStremioAutomatically() {
        guard let target=fallbackEpisode,UIApplication.shared.applicationState == .active,
              UserDefaults.standard.object(forKey:"cast.series.autoReturn") as? Bool ?? true,
              returnedEpisodes.insert(target.id).inserted else{return}
        if returnedEpisodes.count>16{returnedEpisodes=[target.id]}
        openEpisodeInStremio()
    }
    @discardableResult private func advanceAutoplaySource(allowRetry:Bool=true)->Bool {
        guard var context=episodeAutoplay,context.content==currentEpisodeID,!hasLoaded else{return false}
        if allowRetry,let key=context.plan.next(),let source=context.sources[key] {
            episodeAutoplay=context
            choose(source,automaticEpisode:true)
            message="Provo una sorgente equivalente (\(context.plan.attempt)/\(context.plan.limit))…"
            PlaybackDiagnostics.record(.source,["phase":"autoplay_candidate","attempt":String(context.plan.attempt)])
            return true
        }
        resetPlayback();hasLoaded=false
        fallbackEpisode=context.target
        episodeIssue="Non riesco ad avviare una sorgente equivalente con le lingue richieste. Continua da Stremio o scegli un’altra sorgente."
        message="La puntata richiede una nuova sorgente."
        returnToStremioAutomatically();return true
    }
    private func autoplayMayRetry(_ error:Error)->Bool {
        if let rd=error as? RDResolverError {
            switch rd {
            case .rateLimited:return false
            case .http(let status):return AutoplayRetryPlan.permits(status:status)
            case .apiFailure(let status,_,_):return AutoplayRetryPlan.permits(status:status)
            default:break
            }
        }
        return true
    }

    var isSeries:Bool { handoff?.type=="series" }
    var currentEpisodeID:String { handoff?.id ?? "" }
    var orderedEpisodes:[SeriesEpisode] {
        guard let id=SeriesNavigation.seriesID(currentEpisodeID) else{return []}
        return SeriesNavigation.ordered(episodes,series:id,includeSpecials:UserDefaults.standard.bool(forKey:"cast.series.specials"))
    }
    func adjacentEpisode(_ direction:Int) -> SeriesEpisode? { SeriesNavigation.adjacent(orderedEpisodes,current:currentEpisodeID,direction:direction) }
    func refreshEpisodes() {
        episodeTask?.cancel();episodes=[];episodeIssue=nil
        guard isSeries,SeriesNavigation.seriesID(currentEpisodeID) != nil else{return}
        let id=currentEpisodeID
        episodeTask=Task { [weak self] in
            do {
                let videos=try await BridgeClient.shared.episodes(videoID:id)
                guard !Task.isCancelled,let self,self.currentEpisodeID==id else{return}
                self.episodes=videos
                if self.orderedEpisodes.isEmpty {self.episodeIssue="Nessun elenco episodi disponibile."}
            } catch {
                guard !Task.isCancelled,let self,self.currentEpisodeID==id else{return}
                self.episodeIssue="Elenco episodi non disponibile. Puoi riprovare."
            }
        }
    }
    func returnToStremio() {
        // This navigation does not reset or cancel the playing Cast session.
        openStremio(type:handoff?.type,id:handoff?.id)
    }
    private func openStremio(type:String?,id:String?) {
        let web=UserDefaults.standard.bool(forKey:"cast.series.webFallback")
        let url=StremioReturnLink.url(type:type,id:id,web:web)
        UIApplication.shared.open(url,options:[:]) { [weak self] success in
            guard !success else{return}
            Task { @MainActor [weak self] in
                if !web {
                    let fallback=StremioReturnLink.url(type:type,id:id,web:true)
                    UIApplication.shared.open(fallback,options:[:]) { [weak self] opened in
                        if !opened {Task { @MainActor [weak self] in self?.message="Non riesco ad aprire Stremio. Riprova dal pulsante."}}
                    }
                } else {self?.message="Non riesco ad aprire Stremio Web. Riprova dal pulsante."}
            }
        }
    }
    func openEpisodeInStremio() {
        if episodeAutoplay != nil && !hasLoaded {resetPlayback()}
        guard let target=fallbackEpisode else{return}
        openStremio(type:"series",id:target.id)
    }
    func moveEpisode(_ direction:Int,automatic:Bool=false) {
        guard !busy,!loading,!episodeBusy,let current=handoff,let target=adjacentEpisode(direction),
              !automatic || target.aired() else{return}
        let family=selectedSource?.behaviorHints?.bingeGroup
        let next=BridgeHandoff(version:current.version,status:current.status,provider:current.provider,type:current.type,id:target.id,selection:nil,subtitleLanguage:current.subtitleLanguage,externalSubtitleURL:nil)
        guard let config=configuration else{fallbackEpisode=target;episodeIssue="Configura le sorgenti oppure continua da Stremio.";if automatic{returnToStremioAutomatically()};return}
        episodeRequest=UUID();let token=episodeRequest
        episodeBusy=true;episodeIssue=nil;fallbackEpisode=nil
        if automatic{updateActivity(status:"Preparo la prossima puntata")}
        work=Task { [weak self] in
            let owner="episode-prepare-"+UUID().uuidString
            CastAudioSession.shared.acquire(owner)
            let background=CastBackgroundLease(name:"Choose next episode") { [weak self] in
                guard let self,self.episodeRequest==token else{return}
                self.work?.cancel();self.work=nil;self.episodeBusy=false
                self.episodeIssue="iOS ha interrotto la preparazione della puntata. Puoi riprovare."
            }
            defer {
                CastAudioSession.shared.release(owner)
                background.end()
            }
            do {
                let found=try await BridgeClient.shared.sources(next,manifest:config.manifest)
                try Task.checkCancellation()
                guard let self,self.episodeRequest==token,self.currentEpisodeID==current.id else{return}
                self.episodeBusy=false
                let matching=family.flatMap{group in group.isEmpty ? nil:found.first{$0.behaviorHints?.bingeGroup==group}}
                let useMatch=UserDefaults.standard.object(forKey:"cast.series.matchSource") as? Bool ?? true
                if automatic && useMatch && matching==nil {
                    self.fallbackEpisode=target;self.episodeIssue="Nessuna sorgente equivalente scelta automaticamente. Continua da Stremio o scegli l’episodio manualmente.";self.returnToStremioAutomatically();return
                }
                self.capturePosition();self.resetPlayback();self.clearSubtitleChoices()
                self.sourceResume=nil;self.handoff=next;self.sources=found;self.selectedSource=nil;self.prepared=nil
                self.sourceRevision=UUID();self.position=0;self.duration=0;self.hasLoaded=false;self.busy=false
                if useMatch,let matching {
                    if automatic {
                        let candidates=found.filter{$0.behaviorHints?.bingeGroup==family}
                        let ids=candidates.map{self.contentDigest($0.url+"|"+($0.torrentHash ?? "")+"|"+$0.identity)}
                        let lookup=Dictionary(zip(ids,candidates),uniquingKeysWith:{first,_ in first})
                        self.episodeAutoplay=EpisodeAutoplay(content:target.id,target:target,sources:lookup,plan:AutoplayRetryPlan(ids,limit:PlaybackPreferences.sourceAttempts()))
                        _ = self.advanceAutoplaySource()
                    } else {self.choose(matching);self.fallbackEpisode=target}
                }
                else {self.fallbackEpisode=target;self.message="\(target.label): scegli una sorgente."}
            } catch {
                guard !Task.isCancelled,let self,self.episodeRequest==token else{return}
                self.episodeBusy=false;self.fallbackEpisode=target
                self.episodeIssue="Non riesco a trovare la sorgente della puntata. La riproduzione corrente è conservata. Puoi continuare da Stremio."
                if automatic{self.returnToStremioAutomatically()}
            }
        }
    }
    @Published var showSetup = false
    @Published private(set) var sourceRevision = UUID()
    @Published var setupMessage = "Inserisci i tuoi collegamenti personali una sola volta."
    @Published var sources: [AddonStream] = []
    @Published var selectedSource: AddonStream?
    @Published var prepared: RDPreparedMedia?
    @Published var selectedAudio = ""
    @Published var selectedSubtitle = "none"
    @Published var selectedQuality: RDQuality = .high
    @Published var compatibilityMode = false
    @Published var message = "Apri una sorgente Chromecast da Stremio."
    @Published var busy = false
    @Published var connected = false
    @Published var playing = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Double = 0.5
    @Published var userSeeking = false
    @Published var userAdjustingVolume = false
    @Published var hasLoaded = false
    @Published private(set) var loading = false
    @Published private(set) var playbackIssue: String?
    @Published private(set) var deviceMuted = false
    @Published private(set) var localProcessing = false
    @Published private(set) var processingDetail = "Automatico"
    @Published private(set) var onlineSubtitles:[OnlineSubtitle] = []
    @Published private(set) var subtitleSearchBusy = false
    @Published private(set) var subtitleDownloadBusy = false
    @Published private(set) var subtitlePreparation = "Preparo i sottotitoli…"
    @Published private(set) var subtitleIssue:String?
    @Published private(set) var subtitlePlaybackWarning:String?
    @Published private(set) var subtitleDelay:Double = 0
    private var selectedOnlineSubtitle:OnlineSubtitle?
    private var subtitleSearchTask:Task<Void,Never>?
    private var subtitlePickTask:Task<Void,Never>?
    private var subtitleChoices = PlaybackRequestState()
    private var embeddedCaptionTask:Task<Void,Never>?
    private let independentCaptions=IndependentCaptions()
    private var loadedAudioKey=""
    private var loadedSourceInput:URL?
    private var attemptedEmbeddedCaptions = Set<String>()
    private var subtitleSearchStamp = Date.distantPast
    private var subtitleRetryAfter = Date.distantPast
    private var extractedCaptionText:String?
    private let completeCaptionCache=CaptionDocumentCache()
    private let standardCaptions=StandardCaptionHost()
    private var directCaptionTask:Task<Void,Never>?
    private var directCaptionAttempt=""
    private var mediaCORS:[URL:Bool]=[:]
    private var loadedDirectCaptionURLs:[Int:URL]=[:]
    private var loadedDirectCaptionIdentity=""
    private var cachedCaptionCatalog:(URL,CaptionCatalog)?
    private var extractedCaptionKey = ""
    private var extractedCaptionLanguage = "en"
    private var lastAppliedSubtitleDelay:Double = 0
    private var pendingSubtitleDelay:Double?
    private var loadStartPosition:Double = 0
    @Published var subtitleFile: URL?
    @Published private(set) var embeddedSubtitleURL: URL?
    private var handoff: BridgeHandoff?
    private var configuration: AddonConfiguration?
    private var preparedCache: [String:(RDPreparedMedia,Date)] = [:]
    private var originalURL: URL?
    private var work: Task<Void, Never>?
    private var loadRequest: GCKRequest?
    private var timer: Timer?
    private var lastGoodPosition: Double = 0
    private var loadPending = false
    private var loadAccepted = false
    private var loadTimeout: Task<Void, Never>?
    private var sourceRequests = PlaybackRequestState()
    private var streamRequests = PlaybackRequestState()
    private var controlRequests = PlaybackRequestState()
    private var playbackIntent = PlaybackIntent()
    private var timeline = PlaybackTimeline()
    private var playWhenReady = true
    private var transportRetries = 0
    private var recovery = PlaybackRecoveryState()
    private var progress = PlaybackProgressMonitor()
    private var lastConfirmedPosition:Double?
    private var confirmedChoice:(audio:String,subtitle:String,online:OnlineSubtitle?,delay:Double)?
    private var sourceResume: (content:PlaybackContent,position:Double,duration:Double,playing:Bool)?
    private var lastPositionSave = Date.distantPast
    private var positionKey: String?
    private var bufferingSince: Date?
    private var expectedContentID: String?
    private var loadedSignature: String?
    private var loadedStreamGeneration: UUID?
    private var loadedMediaSessionID:Int?
    private var loadedSubtitle: String?
    private var subtitleRequest: GCKRequest?
    private var pendingSubtitle: String?
    private weak var observedClient: GCKRemoteMediaClient?
    private var listenersAttached = false
    private var directCaptureTask: Task<Void,Never>?
    private var directCaptureKey: String?
    private var directCaptureAttempt = Date.distantPast
    private var directCaptureAttemptKey: String?
    private var subtitleStyleWork: Task<Void,Never>?
    private var streamCheckTask: Task<Void,Never>?
    private var checkingStream = false
    private var nativeEngine: EmbeddedMediaEngine?
    private var captionCache: [URL:String] = [:]
    private var captionFailures: [URL:Date] = [:]
    private struct NativeSelection: Equatable {
        let input: URL
        let audio: String
        let subtitle: String
        let appearance: SubtitleAppearance
        let external: URL?
        let extracted: URL?
        let captionIdentity:String
        let bitmapDelay:Double
    }
    private var nativeSelection: NativeSelection?
    private var streamOffset: Double { nativeEngine?.offset ?? 0 }
    private var forceLocalPlayback = false
    private var localFallbackLevel = 0
    private var nativeEngineGeneration:UUID?
    private var commandRequest: GCKRequest?
    private var commandContinuation: CheckedContinuation<Bool, Never>?
    private var commandTimeout: Task<Void, Never>?
    private var commandAction = "none"
    private var commandGeneration:UUID?
    private var intentCorrectionRequest:GCKRequest?
    private var intentCorrection:Bool?
    private let lockScreen = LockScreenPlayback()
    private var lastDevice: GCKDevice?
    private var reconnectTask: Task<Void,Never>?
    private var trackChangePending = false
    private var trackApplyTask: Task<Void,Never>?
    private var seekDispatchTask: Task<Void,Never>?
    private var wantsPlayback = false
    private var lastDiagnosticSnapshot = Date.distantPast
    private var transferCheckpoint:(engine:ObjectIdentifier,time:Date,metrics:LocalTransferMetrics)?
    var displayTitle: String { MediaDisplayTitle.clean(selectedSource?.filename ?? selectedSource?.descriptionText.components(separatedBy:.newlines).first ?? "Video da Stremio") }
    var deviceName: String { castSession?.device.friendlyName ?? lastDevice?.friendlyName ?? "Chromecast" }

    private var backgroundServiceStopped=false
    private let backgroundProcessing=CastBackgroundProcessing()
    override init() {
        super.init()
        backgroundProcessing.register()
        LegacyPlaybackActivities.retire()
        independentCaptions.onStatus={ [weak self] busy,issue in
            self?.subtitleDownloadBusy=busy
            self?.subtitleIssue=issue
            self?.subtitlePlaybackWarning=issue
        }
        PlaybackDiagnostics.record(.app,["phase":"launch"])
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(forName:UIApplication.didReceiveMemoryWarningNotification,object:nil,queue:.main) { _ in
            Task { @MainActor in PlaybackDiagnostics.record(.app,["phase":"memory_warning"]) }
        }
        positionKey = UserDefaults.standard.string(forKey: "cast.session.positionKey")
        if let positionKey { lastGoodPosition = UserDefaults.standard.double(forKey: positionKey) }
        CastActivityCommands.handler = { [weak self] command in await self?.handleCommand(command) ?? false }
        lockScreen.handler = { [weak self] command in await self?.handleCommand(command) ?? false }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateStatus() }
        }
    }
    private var castSession: GCKCastSession? { GCKCastContext.sharedInstance().sessionManager.currentCastSession }
    private var client: GCKRemoteMediaClient? { castSession?.remoteMediaClient }
    private func contentDigest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private var ownsCurrentMedia: Bool {
        guard let info = client?.mediaStatus?.mediaInformation else { return false }
        let candidates = [info.contentURL?.absoluteString, info.contentID].compactMap { $0 }.filter { !$0.isEmpty }
        if let expectedContentID { return CastContentIdentity.matches(expected:expectedContentID,contentURL:info.contentURL?.absoluteString,contentID:info.contentID) }
        guard let saved = UserDefaults.standard.string(forKey: "cast.session.content") else { return false }
        return candidates.contains { contentDigest($0) == saved }
    }
    private func capturePosition() {
        guard timeline.target == nil, timeline.queuedTarget == nil, !checkingStream, ownsCurrentMedia, !loadPending, let client,
              let state = client.mediaStatus?.playerState, state == .playing || state == .paused else { return }
        let value = client.approximateStreamPosition() + streamOffset
        guard value.isFinite, value >= 0, state != .buffering || value > 0 else { return }
        lastGoodPosition = value
        if let positionKey { UserDefaults.standard.set(value, forKey: positionKey);UserDefaults.standard.set(Date(),forKey:positionKey+".updated") }
    }
    func savePlaybackPosition(phase:String = "background") {
        capturePosition();syncStremioProgress(force:true)
        PlaybackDiagnostics.record(.app,["phase":phase,"position":PlaybackDiagnostics.number(lastGoodPosition)])
        recordEnergySnapshot(); PlaybackDiagnostics.shared.flush()
    }
    private func syncStremioProgress(completed:Bool=false,force:Bool=false) {
        guard let handoff,let confirmed=lastConfirmedPosition,confirmed.isFinite,confirmed>=0,duration.isFinite,duration>0 else{return}
        let ended=completed && confirmed>=duration-max(2,min(30,duration*0.02))
        let ids=SeriesNavigation.seriesID(handoff.id).map{SeriesNavigation.ordered(episodes,series:$0,includeSpecials:true).map(\.id)} ?? []
        let title=handoff.type=="series" ? displayTitle.components(separatedBy:" · S").first ?? displayTitle:displayTitle
        StremioSync.shared.observe(type:handoff.type,videoID:handoff.id,title:title,position:ended ? duration:confirmed,duration:duration,completed:ended,force:force,episodes:ids)
    }
    private func recordEnergySnapshot() {
        if let prepared {
            let video=prepared.video
            let audio=prepared.audio.first(where:{$0.key==selectedAudio})
            let subtitle=prepared.subtitles.first(where:{$0.key==selectedSubtitle})
            var format:[String:String]=["phase":"context","codec":video?.codec ?? "unknown",
                "audio":audio?.codec ?? "unknown","channels":String(audio?.channels ?? 0),
                "subtitle":subtitle?.codec ?? selectedSubtitle,"mode":nativeEngine.map{String(describing:$0.diagnosticMode)} ?? "direct",
                "local":String(localProcessing),"generation":String((nativeEngineGeneration ?? streamRequests.generation).uuidString.prefix(8)),"requestGeneration":String(streamRequests.generation.uuidString.prefix(8)),
                "session":String(client?.mediaStatus?.mediaSessionID ?? 0),"previousSession":String(loadedMediaSessionID ?? 0)]
            if let video {
                format["width"]=String(video.width);format["height"]=String(video.height)
                format["fps"]=PlaybackDiagnostics.number(video.frameRate)
            }
            PlaybackDiagnostics.record(.metadata,format)
        }
        let device=UIDevice.current
        PlaybackDiagnostics.record(.snapshot,["phase":"energy","battery":device.batteryLevel < 0 ? "unknown":PlaybackDiagnostics.number(Double(device.batteryLevel)*100),"power":String(device.batteryState.rawValue),"thermal":String(ProcessInfo.processInfo.thermalState.rawValue),"lowPower":String(ProcessInfo.processInfo.isLowPowerModeEnabled),"local":String(localProcessing),"position":PlaybackDiagnostics.number(position)])
        guard let engine=nativeEngine else { return }
        if var metrics=engine.productionMetrics() {
            metrics["mode"]=String(describing:engine.diagnosticMode)
            metrics["generation"]=String((nativeEngineGeneration ?? streamRequests.generation).uuidString.prefix(8))
            metrics["paused"]=String(!playWhenReady)
            PlaybackDiagnostics.record(.producer,metrics)
        }
        let source=sourceRequests.generation
        Task { [weak self,weak engine] in
            guard let self,let engine,let metrics=await engine.transferMetrics(),self.nativeEngine === engine,self.sourceRequests.accepts(source) else { return }
            let now=Date(),identity=ObjectIdentifier(engine)
            if let old=self.transferCheckpoint,old.engine==identity {
                let seconds=now.timeIntervalSince(old.time)
                if seconds>0 {
                    PlaybackDiagnostics.record(.producer,["phase":"transfer","bytes":String(metrics.bytes),"seconds":PlaybackDiagnostics.number(seconds),"rate":PlaybackDiagnostics.number(Double(max(0,metrics.bytes-old.metrics.bytes))*8/seconds),"upstreamWait":PlaybackDiagnostics.number(max(0,metrics.upstreamWait-old.metrics.upstreamWait)),"downstreamWait":PlaybackDiagnostics.number(max(0,metrics.downstreamWait-old.metrics.downstreamWait)),"paused":String(!self.playWhenReady),"mode":String(describing:engine.diagnosticMode),"generation":String((self.nativeEngineGeneration ?? self.streamRequests.generation).uuidString.prefix(8))])
                }
            }
            self.transferCheckpoint=(identity,now,metrics)
        }
    }
    func copyDiagnostics() {
        PlaybackDiagnostics.record(.snapshot,["phase":"copy","connected":String(connected),"local":String(localProcessing),"position":PlaybackDiagnostics.number(position),"duration":PlaybackDiagnostics.number(duration),"pending":String(loading || loadPending || checkingStream)])
        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic:PlaybackDiagnostics.shared.report()]],options:[.localOnly:true,.expirationDate:Date().addingTimeInterval(3600)])
    }
    func refreshConnection() {
        independentCaptions.attach(castSession)
        let manager = GCKCastContext.sharedInstance().sessionManager
        if !listenersAttached { manager.add(self); listenersAttached = true }
        if observedClient !== client {
            observedClient?.remove(self); observedClient = client; client?.add(self)
        }
        client?.requestStatus()
        if let device = castSession?.device { lastDevice = device }
        updateStatus()
        if resumePendingRecovery() { return }
        if connected && wantsPlayback && prepared != nil && !busy && !loading && !hasLoaded && !loadPending {
            if recovery.attempts>0 {
                if !recoverPlayback(allowVideoConversion:false) {
                    message="Il recupero automatico non è riuscito. Puoi riprovare dal punto conservato."
                    playbackIssue=message
                }
            } else {load()}
        }
    }
    func sessionManager(_ manager: GCKSessionManager, didStart session: GCKSession) { refreshConnection() }
    func sessionManager(_ manager: GCKSessionManager, didResumeSession session: GCKSession) { refreshConnection() }
    @objc(sessionManager:didSuspendSession:withReason:)
    func sessionManager(_ manager:GCKSessionManager,didSuspend session:GCKSession,with reason:GCKConnectionSuspendReason) {
        PlaybackDiagnostics.record(.cast,["phase":"suspend","code":String(reason.rawValue)])
        guard wantsPlayback else { return }
        connected = false; message = "Ricollego i controlli alla TV…"
        reconnectControls()
    }
    func sessionManager(_ manager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) {
        var fields=error.map{PlaybackDiagnostics.errorFields($0,phase:"end")} ?? ["phase":"end"]
        fields["result"]=error == nil ? "normal":"error"
        PlaybackDiagnostics.record(.cast,fields)
        if error != nil && wantsPlayback && (hasLoaded || localProcessing) {
            connected = false; finishCommand(false)
            message = "Ricollego i controlli alla TV…"
            reconnectControls(); return
        }
        wantsPlayback = false; reconnectTask?.cancel(); reconnectTask = nil; lockScreen.clear()
        stopCaptionDelivery()
        streamCheckTask?.cancel(); checkingStream = false; loading = false
        capturePosition(); stopLocalProcessing(); connected = false; playing = false; finishCommand(false)
    }
    func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus?) { updateStatus() }
    private func updateStatus() {
        guard UIApplication.shared.applicationState == .active || localProcessing || lockScreen.active else { return }
        connected = GCKCastContext.sharedInstance().sessionManager.hasConnectedCastSession()
        PlaybackDiagnostics.shared.changed("connection",event:.cast,["connected":String(connected)])
        guard !backgroundServiceStopped else{return}
        guard let session = castSession, let client = session.remoteMediaClient, connected else {
            if wantsPlayback { reconnectControls(); updateActivity(status:"Ricollego i controlli…") }
            return
        }
        reconnectTask?.cancel(); reconnectTask = nil
        if resumePendingRecovery() { return }
        backgroundProcessing.update(position:lastConfirmedPosition)
        if !userAdjustingVolume { volume = Double(session.currentDeviceVolume) }
        deviceMuted = session.currentDeviceMuted
        if let status = client.mediaStatus {
            PlaybackDiagnostics.shared.changed("receiver",event:.cast,["status":String(status.playerState.rawValue),"idle":String(status.idleReason.rawValue),"owned":String(ownsCurrentMedia),"pending":String(loadPending),"local":String(localProcessing),"session":String(status.mediaSessionID),"previousSession":String(loadedMediaSessionID ?? 0)])
            if Date().timeIntervalSince(lastDiagnosticSnapshot) >= 15 {
                lastDiagnosticSnapshot = Date()
                PlaybackDiagnostics.record(.snapshot,["position":PlaybackDiagnostics.number(position),"reported":PlaybackDiagnostics.number(client.approximateStreamPosition()+streamOffset),"raw":PlaybackDiagnostics.number(status.streamPosition+streamOffset),"confirmed":PlaybackDiagnostics.number(lastConfirmedPosition ?? -1),"offset":PlaybackDiagnostics.number(streamOffset),"duration":PlaybackDiagnostics.number(duration),"target":PlaybackDiagnostics.number(timeline.target ?? -1)])
                recordEnergySnapshot()
            }
            // This status still belongs to the stream being replaced. Keep the
            // requested position, autoplay intent and any new preparation intact.
            if checkingStream { return }
            if let loadedStreamGeneration, !streamRequests.accepts(loadedStreamGeneration) { return }
            if PlaybackCompletion.detachedEnd(finished:status.playerState == .idle && status.idleReason == .finished,hasLoaded:hasLoaded,pending:loadPending,informationPresent:status.mediaInformation != nil,currentSession:status.mediaSessionID,lastSession:loadedMediaSessionID) {
                finishOwnedPlayback();return
            }
            // Receivers can reuse mediaSessionID across LOAD calls. Match the
            // expected content instead; never copy another video's position.
            guard ownsCurrentMedia else {
                if hasLoaded && !loadPending && !checkingStream { stopCaptionDelivery();stopLocalProcessing(); hasLoaded = false; wantsPlayback = false; lockScreen.clear(); message = "La TV sta riproducendo un altro contenuto." }
                if !loadPending && timeline.target == nil { playing = false }
                return
            }
            if loadPending && !loadAccepted { return }
            if loadPending && status.playerState == .idle && status.idleReason != .error { return }
            if (status.playerState == .playing || status.playerState == .paused) && !playbackIntent.accepts(status.playerState == .playing) {
                if intentCorrection != playWhenReady {
                    intentCorrection=playWhenReady
                    PlaybackDiagnostics.record(.command,["phase":"intent_correction","action":playWhenReady ? "play":"pause"])
                    let request=playWhenReady ? client.play():client.pause()
                    intentCorrectionRequest=request;request.delegate=self
                }
                return
            }
            if status.playerState == .playing || status.playerState == .paused { intentCorrection=nil }
            let wasPlaying=playing
            playing = status.playerState == .playing
            if (status.playerState == .playing && (!loadPending || playWhenReady)) || (status.playerState == .paused && (!loadPending || !playWhenReady)) { nativeEngine?.setReceiverPaused(status.playerState == .paused) }
            if loadPending && loadAccepted && playWhenReady && status.playerState == .paused { _ = client.play() }
            if loadPending && loadAccepted && !playWhenReady && status.playerState == .playing { _ = client.pause() }
            if status.playerState != .buffering { bufferingSince = nil }
            let observed = client.approximateStreamPosition() + streamOffset
            let ready = (status.playerState == .playing && (!loadPending || playWhenReady)) || (status.playerState == .paused && (!loadPending || !playWhenReady))
            // A transient PLAYING acknowledgement at time zero is not proof
            // that video has started. Keep the timeout armed until real media
            // time advances; a paused load can be acknowledged without motion.
            let progressed = !loadPending || PlaybackReadiness.progressed(actual:status.streamPosition+streamOffset,start:loadStartPosition,paused:!playWhenReady)
            let confirmed = timeline.observe(observed,ready:ready && progressed && (!loadPending || loadAccepted))
            if confirmed && timeline.queuedTarget == nil {
                lastGoodPosition = observed
                let actual=status.streamPosition+streamOffset
                if actual.isFinite,actual >= 0 { lastConfirmedPosition=actual }
                if let positionKey, observed > 0, Date().timeIntervalSince(lastPositionSave) >= 10 {
                    UserDefaults.standard.set(observed, forKey: positionKey);UserDefaults.standard.set(Date(),forKey:positionKey+".updated"); lastPositionSave = Date()
                }
                if !userSeeking { position = observed }
            }
            let reported = status.mediaInformation?.streamDuration ?? 0
            let known = prepared?.duration ?? UserDefaults.standard.double(forKey:"cast.session.duration")
            let d = localProcessing ? (known > 0 ? known : (reported > 0 ? reported + streamOffset : duration)) : (reported.isFinite && reported > 0 ? reported : (known > 0 ? known : duration))
            if d.isFinite && d > 0 { duration = d }
            let currentLoad = !loadPending || loadAccepted
            if localProcessing,!loadPending,!checkingStream,timeline.target == nil,timeline.queuedTarget == nil,
               progress.observe(position:status.streamPosition+streamOffset,now:Date(),expectedToAdvance:playWhenReady) {
                progress.reset()
                PlaybackDiagnostics.record(.recovery,["phase":"clock_stalled","position":PlaybackDiagnostics.number(lastConfirmedPosition ?? lastGoodPosition)])
                if recoverPlayback(allowVideoConversion:false) { return }
            }
            if progress.stable && (!localProcessing || nativeEngine?.failed != true) { recovery.reset() }
            if ready && confirmed && currentLoad && (!localProcessing || nativeEngine?.failed != true) {
                if loadPending || !hasLoaded { playbackIssue = nil }
                hasLoaded = true; wantsPlayback = true
                episodeAutoplay=nil;requireEpisodeLanguage=false
                loadedMediaSessionID=status.mediaSessionID
                syncStremioProgress(force:wasPlaying && !playing)
                if loadedAudioKey==selectedAudio,loadedSubtitle==selectedSubtitle {
                    confirmedChoice=(selectedAudio,selectedSubtitle,selectedOnlineSubtitle,subtitleDelay)
                }
                playWhenReady = playing
                if loadPending { loadPending = false; loading = false; loadTimeout?.cancel(); hasLoaded = true }
                if !checkingStream { message = playing ? "In riproduzione sulla TV." : "In pausa sulla TV." }
                updateActivity(status: playing ? "In riproduzione" : "In pausa")
                prepareDirectControls()
                flushQueuedSeek()
                applyPendingTrackChange()
                applySubtitleTiming()
            } else if status.playerState == .buffering {
                if bufferingSince == nil { bufferingSince = Date() }
                let stalled = Date().timeIntervalSince(bufferingSince!) >= 45
                if localProcessing && nativeSelection?.subtitle.hasPrefix("vlc_") == true && Date().timeIntervalSince(bufferingSince!) >= 15 {
                    if advanceAutoplaySource(){return}
                    disableSubtitlesAndResume(automatic:true); return
                }
                if stalled && localProcessing {
                    if recoverPlayback(allowVideoConversion:false) { return }
                    playbackIssue = "Il flusso è fermo. La posizione è conservata: puoi riprovare o cambiare sorgente."
                    hasLoaded = false; loading = false; loadPending = false
                }
                message = stalled ? "Buffering prolungato. Riprova dal punto conservato o cambia sorgente." : "Caricamento sulla TV…"
                updateActivity(status: stalled ? "Buffering: apri l’app per riprovare" : "Caricamento")
            } else if status.playerState == .idle && currentLoad && status.idleReason == .error {
                loadPending = false; loading = false; loadTimeout?.cancel(); loadRequest = nil
                hasLoaded=false
                if advanceAutoplaySource(){return}
                if recoverPlayback() { return }
                message = "La riproduzione si è interrotta. Riprova: la posizione è conservata."
                updateActivity(status: "Errore: apri l’app per riprovare")
            } else if status.playerState == .idle && currentLoad && status.idleReason == .finished {
                finishOwnedPlayback()
            } else if status.playerState == .idle && currentLoad && status.idleReason == .cancelled {
                stopCaptionDelivery()
                wantsPlayback = false; lockScreen.clear()
                loadPending = false; loading = false; loadTimeout?.cancel(); hasLoaded = false
                stopLocalProcessing(); message = "Riproduzione interrotta."
                updateActivity(status:"Riproduzione interrotta")
            }
        }
    }
    private func reconnectControls() {
        guard reconnectTask == nil, wantsPlayback, let device = lastDevice else { return }
        reconnectTask = Task { [weak self] in
            for delay in [1,2,4,8,12] {
                try? await Task.sleep(nanoseconds:UInt64(delay)*1_000_000_000)
                guard !Task.isCancelled, let self, self.wantsPlayback else { return }
                let manager = GCKCastContext.sharedInstance().sessionManager
                if manager.hasConnectedCastSession() { self.refreshConnection(); return }
                if manager.connectionState != .connecting { _ = manager.startSession(with:device) }
            }
            self?.reconnectTask = nil
        }
    }
    private func finishOwnedPlayback() {
        guard wantsPlayback || hasLoaded else{return}
        PlaybackDiagnostics.record(.load,["phase":"finished","position":PlaybackDiagnostics.number(lastConfirmedPosition ?? lastGoodPosition)])
        syncStremioProgress(completed:true,force:true)
        backgroundProcessing.finish(success:true)
        let continueSeries=(UserDefaults.standard.object(forKey:"cast.series.autoplay") as? Bool ?? true) && (adjacentEpisode(1)?.aired()==true)
        stopCaptionDelivery();wantsPlayback=false;lockScreen.clear(reason:"finished")
        loadPending=false;loading=false;loadTimeout?.cancel();loadRequest=nil
        if let positionKey { UserDefaults.standard.set(0,forKey:positionKey);UserDefaults.standard.set(Date(),forKey:positionKey+".updated") }
        sourceResume=nil;hasLoaded=false;lastGoodPosition=0;lastConfirmedPosition=nil
        loadedMediaSessionID=nil;timeline.reset();recovery.reset();progress.reset()
        stopLocalProcessing();message="Riproduzione terminata."
        if continueSeries {moveEpisode(1,automatic:true)}
    }
    private func prepareDirectControls() {
        guard connected, ownsCurrentMedia, let session = castSession,
              let digest = UserDefaults.standard.string(forKey:"cast.session.content") else { return }
        let host = session.device.ipAddress
        let key = host + "|" + digest
        guard directCaptureKey != key, directCaptureAttemptKey != key || Date().timeIntervalSince(directCaptureAttempt) > 30 else { return }
        directCaptureAttempt = Date()
        directCaptureAttemptKey = key
        directCaptureKey = key
        directCaptureTask?.cancel()
        directCaptureTask = Task {
            do { try await CastDirectControl.capture(host:host,contentDigest:digest) }
            catch { if !Task.isCancelled { directCaptureKey = nil } }
        }
    }
    func open(_ url: URL) {
        PlaybackDiagnostics.record(.source,["phase":"handoff"])
        if url.scheme == "stremiocast" && url.host == "controls" {
            if client == nil { message = "Riconnetti Chromecast per usare i controlli." }
            return
        }
        episodeRequest=UUID();episodeBusy=false;episodeTask?.cancel();episodes=[];fallbackEpisode=nil;episodeIssue=nil
        work?.cancel()
        clearSubtitleChoices()
        sourceResume = nil
        resetPlayback()
        sources = []; selectedSource = nil; prepared = nil; handoff = nil; configuration = nil; originalURL = nil; hasLoaded = false; lastGoodPosition = 0
        do {
            let ticket = try BridgeClient.shared.ticket(from:url)
            let sourceToken = sourceRequests.generation
            busy = true; message = "Apro la sorgente…"
            work = Task {
                do {
                    let data = try await BridgeClient.shared.handoff(ticket:ticket)
                    try validateSource(sourceToken)
                    handoff = data; work = nil
                    beginSources(data)
                } catch is CancellationError { } catch {
                    if Task.isCancelled || !sourceRequests.accepts(sourceToken) { return }
                    busy = false
                    message = (error as? BridgeError)?.localizedDescription ?? "Non riesco ad aprire il collegamento. Riprova da Stremio."
                }
            }
        } catch { busy = false; message = (error as? BridgeError)?.localizedDescription ?? "Collegamento non valido." }
    }
    private func beginSources(_ data: BridgeHandoff) {
        refreshEpisodes()
        work?.cancel()
        sourceRequests.invalidate()
        let sourceToken = sourceRequests.generation
        do {
            guard let saved = try AddonConfigStore.load(provider:data.provider) else {
                busy = false; showSetup = true
                setupMessage = "Aggiungi il tuo collegamento personale " + data.provider.capitalized + " per continuare."
                message = "Configura l’add-on su questo iPhone."
                return
            }
            configuration = saved; busy = true; message = "Cerco la sorgente sul tuo account…"
            work = Task {
                do {
                    let found = try await BridgeClient.shared.sources(data,manifest:saved.manifest)
                    try validateSource(sourceToken)
                    sources = found; busy = false; work = nil
                    if let wanted = data.selection, let selected = found.first(where: { $0.identity == wanted }) {
                        choose(selected)
                    } else {
                        message = data.selection == nil ? "Scegli una sorgente." : "La sorgente è cambiata: scegli un file dall’elenco aggiornato."
                    }
                } catch is CancellationError { } catch {
                    if Task.isCancelled || !sourceRequests.accepts(sourceToken) { return }
                    busy = false
                    message = (error as? BridgeError)?.localizedDescription ?? "Non riesco a leggere le sorgenti. Riprova da Stremio."
                }
            }
        } catch {
            busy = false; showSetup = true
            setupMessage = (error as? AddonConfigError)?.localizedDescription ?? "Non riesco a leggere la configurazione."
        }
    }
    @discardableResult func saveConfigurations(torrentio: String, comet: String, subtitleEndpoint: String = "", subtitleToken: String = "") -> Bool {
        do {
            var values: [AddonConfiguration] = []
            if !torrentio.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { values.append(try AddonConfigStore.parse(torrentio,provider:"torrentio")) }
            if !comet.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { values.append(try AddonConfigStore.parse(comet,provider:"comet")) }
            guard !values.isEmpty || !subtitleEndpoint.isEmpty else { setupMessage = "Incolla almeno un collegamento personale."; return false }
            if !subtitleEndpoint.isEmpty { try SubtitleHosting.save(endpoint:subtitleEndpoint,token:subtitleToken) }
            for value in values { try AddonConfigStore.save(value) }
            showSetup = false; setupMessage = "Configurazione salvata."
            if let data = handoff {
                beginSources(data)
                if showSetup { return false }
            } else { message = "Configurazione salvata. Apri una sorgente Chromecast da Stremio." }
            return true
        } catch {
            setupMessage = (error as? AddonConfigError)?.localizedDescription ?? (error as? SubtitleError)?.localizedDescription ?? "Non riesco a salvare la configurazione."
            return false
        }
    }
    func reorderSources(){sources=BridgeClient.orderedSources(sources)}
    func changeSource() {
        clearSubtitleChoices()
        PlaybackDiagnostics.record(.source,["phase":"chooser","position":PlaybackDiagnostics.number(position)])
        captureSourceResume()
        resetPlayback()
        work?.cancel(); work = nil; busy = false; selectedSource = nil; prepared = nil; hasLoaded = false
        message = "Scegli una sorgente."
    }
    func choose(_ source: AddonStream,automaticEpisode:Bool=false) {
        if !automaticEpisode{episodeAutoplay=nil}
        episodeRequest=UUID();episodeBusy=false;fallbackEpisode=automaticEpisode ? episodeAutoplay?.target:nil;episodeIssue=nil;requireEpisodeLanguage=automaticEpisode
        clearSubtitleChoices()
        if selectedSource != nil { captureSourceResume() }
        resetPlayback(preserveAutoplay:automaticEpisode)
        wantsPlayback = true
        work?.cancel(); subtitleFile = nil; embeddedSubtitleURL = nil; selectedSource = source; prepared = nil; originalURL = nil; hasLoaded = false; lastGoodPosition = 0
        guard let handoff else { message = "Riapri la sorgente da Stremio."; return }
        let content = PlaybackContent(type:handoff.type,id:handoff.id)
        positionKey = content.positionKey
        // Old per-file keys were not scoped to an episode and can refer to a
        // different cut or episode. Only the canonical content key is trusted.
        let stored = UserDefaults.standard.double(forKey:content.positionKey)
        let resume = sourceResume?.content == content ? sourceResume : nil
        lastGoodPosition = max(0,resume?.position ?? stored)
        duration = resume?.duration ?? 0
        playWhenReady = resume?.playing ?? true
        UserDefaults.standard.set(lastGoodPosition,forKey:content.positionKey)
        position = lastGoodPosition
        let sourceToken = sourceRequests.generation
        PlaybackDiagnostics.record(.source,["phase":"choose","generation":String(sourceToken.uuidString.prefix(8)),"position":PlaybackDiagnostics.number(lastGoodPosition)])
        busy = true; message = "Leggo audio e sottotitoli del file…"
        let owner="source-prepare-"+UUID().uuidString
        CastAudioSession.shared.acquire(owner)
        work = Task {
            let background=CastBackgroundLease(name:"Prepare episode source") { [weak self] in
                guard let self,self.sourceRequests.accepts(sourceToken) else{return}
                self.work?.cancel();self.work=nil;self.busy=false
                self.message="iOS ha interrotto la preparazione della sorgente. Puoi riprovare."
            }
            defer {
                CastAudioSession.shared.release(owner)
                background.end()
            }
            do {
                guard let key = configuration?.realDebridKey, !key.isEmpty else { throw BridgeError.cannotResolve }
                let resolver = RDNativeResolver(apiKey:key, session:URLSession(configuration:.ephemeral))
                let result: RDPreparedMedia
                let cacheKey = contentDigest(key + "|" + handoff.id + "|" + source.identity + "|" + (source.torrentHash ?? "") + "|" + source.url)
                if let (saved,time) = preparedCache[cacheKey], Date().timeIntervalSince(time) < 120 {
                    result = saved
                } else {
                    let direct: URL?
                    do { direct = try await BridgeClient.shared.resolveDirect(source) }
                    catch BridgeError.cannotResolve { direct = nil }
                    try validateSource(sourceToken)
                    if let direct {
                        let file = try await resolver.originalFile(directLink:direct)
                        try validateSource(sourceToken)
                        originalURL = file.download
                        result = try await EmbeddedMediaEngine.inspect(file.download)
                    } else if let hash = source.torrentHash, let filename = source.filename {
                        let link = try await resolver.resolveTorrentLink(torrentHash:hash, filename:filename, videoSize:source.behaviorHints?.videoSize,onProgress:{ [weak self] state,progress in
                            guard let self else { return }
                            await self.showPreparationStatus(state,progress:progress,sourceToken:sourceToken)
                        })
                        let file = try await resolver.originalFile(directLink:link)
                        try validateSource(sourceToken)
                        originalURL = file.download
                        result = try await EmbeddedMediaEngine.inspect(file.download)
                    } else { throw BridgeError.cannotResolve }
                    if preparedCache.count >= 8, let oldest = preparedCache.min(by:{$0.value.1 < $1.value.1})?.key { preparedCache[oldest] = nil }
                    preparedCache[cacheKey] = (result,Date())
                }
                try validateSource(sourceToken)
                guard !result.audio.isEmpty else { throw BridgeError.cannotResolve }
                if resume==nil {
                    let updated=UserDefaults.standard.object(forKey:content.positionKey+".updated") as? Date ?? (stored>0 ? Date.distantFuture:Date.distantPast)
                    let remote=await StremioSync.shared.resume(type:handoff.type,videoID:handoff.id,localUpdated:updated)
                    try validateSource(sourceToken)
                    if let remote {lastGoodPosition=remote;position=remote;UserDefaults.standard.set(remote,forKey:content.positionKey)}
                }
                if requireEpisodeLanguage,let language=UserDefaults.standard.string(forKey:"cast.preferred.audio"),language != "auto",
                   !result.audio.contains(where:{PlaybackPreferences.language($0.language)==language}) {
                    busy=false;if advanceAutoplaySource(){return};episodeIssue="La sorgente della prossima puntata non contiene l’audio preferito. Continua da Stremio o scegli un’altra sorgente."
                    message="Scegli una sorgente con la lingua desiderata.";return
                }
                prepared = result; selectedAudio = PlaybackPreferences.audio(result.audio,fallback:result.defaultAudioKey)
                PlaybackDiagnostics.record(.metadata,["codec":result.video?.codec ?? "unknown","width":String(result.video?.width ?? 0),"height":String(result.video?.height ?? 0),"fps":PlaybackDiagnostics.number(result.video?.frameRate ?? 0),"duration":PlaybackDiagnostics.number(result.duration),"tracks":String(result.audio.count),"subtitle":String(result.subtitles.count)])
                for track in result.audio { PlaybackDiagnostics.record(.metadata,["kind":"audio","audio":track.key,"codec":track.codec,"tracks":String(track.channels ?? 0)]) }
                for track in result.subtitles { PlaybackDiagnostics.record(.metadata,["kind":"subtitle","subtitle":track.key,"codec":track.codec]) }
                selectedQuality = result.availableQualities.contains(.high) ? .high : (result.availableQualities.first ?? .high)
                compatibilityMode = false
                selectedSubtitle = PlaybackPreferences.subtitle(result.subtitles,external:externalSubtitleURL != nil,handoff:handoff.subtitleLanguage,externalLanguage:defaultSubtitleLanguage)
                restoreSubtitleDelay()
                busy = false
                if result.duration > 0 {
                    duration = result.duration
                    let restored = PlaybackResume.validated(lastGoodPosition,duration:duration)
                    if restored != lastGoodPosition { PlaybackDiagnostics.record(.recovery,["phase":"resume_reset","position":PlaybackDiagnostics.number(lastGoodPosition),"duration":PlaybackDiagnostics.number(duration)]) }
                    lastGoodPosition = restored
                    if let positionKey { UserDefaults.standard.set(restored,forKey:positionKey) }
                    position = lastGoodPosition
                }
                if requireEpisodeLanguage,selectedSubtitle=="none",PlaybackPreferences.subtitlesRequested(handoff:handoff.subtitleLanguage) {
                    if advanceAutoplaySource(){return}
                    episodeIssue="La prossima puntata non offre i sottotitoli preferiti. Scegli una traccia o continua da Stremio."
                    message="Conferma i sottotitoli prima di continuare.";return
                }
                playbackIssue = nil
                message = "Video pronto. Collega la TV per iniziare."
                if connected && wantsPlayback { load() }
            } catch is CancellationError { } catch {
                if Task.isCancelled || !sourceRequests.accepts(sourceToken) { return }
                PlaybackDiagnostics.record(.error,["phase":"resolve","kind":String(describing:type(of:error)),"code":String((error as NSError).code)])
                if let rd = error as? RDResolverError {
                    switch rd {
                    case .apiFailure(let status,let code,_): PlaybackDiagnostics.record(.error,["phase":"debrid","status":String(status),"code":code.map{String($0)} ?? "none"])
                    case .http(let status): PlaybackDiagnostics.record(.error,["phase":"debrid","status":String(status)])
                    case .rateLimited(let seconds): PlaybackDiagnostics.record(.error,["phase":"debrid","status":"429","seconds":String(seconds)])
                    default: break
                    }
                }
                busy = false
                if advanceAutoplaySource(allowRetry:autoplayMayRetry(error)){return}
                if fallbackEpisode != nil {episodeIssue="La sorgente della puntata non si è avviata. Continua da Stremio o scegli un’altra sorgente."}
                message = (error as? RDResolverError)?.localizedDescription ?? (error as? BridgeError)?.localizedDescription ?? "Non riesco a leggere le tracce di questo file. Scegli un’altra sorgente."
            }
        }
    }
    private func validateSource(_ token: UUID) throws {
        try Task.checkCancellation()
        guard sourceRequests.accepts(token) else { throw CancellationError() }
    }
    private func captureSourceResume() {
        guard let handoff else { return }
        capturePosition()
        sourceResume = (PlaybackContent(type:handoff.type,id:handoff.id),lastGoodPosition,duration,playWhenReady)
        if ownsCurrentMedia { _ = client?.pause() }
    }
    private func showPreparationStatus(_ state: String, progress: Int?, sourceToken: UUID) {
        guard !Task.isCancelled, sourceRequests.accepts(sourceToken) else { return }
        PlaybackDiagnostics.shared.changed("debrid",event:.source,["phase":state])
        let percent = progress.map { " (\($0)%)" } ?? ""
        switch state {
        case "downloading": message = "Real-Debrid sta scaricando questa sorgente\(percent). Attendo automaticamente; puoi cambiare sorgente."
        case "queued": message = "Questa sorgente è in coda su Real-Debrid\(percent). Attendo automaticamente; puoi cambiare sorgente."
        case "waiting_files_selection": message = "Seleziono il file su Real-Debrid…"
        case "downloaded", "reading_metadata": message = "File disponibile: leggo audio e sottotitoli…"
        default: message = "Real-Debrid prepara questa sorgente\(percent). Attendo automaticamente; puoi cambiare sorgente."
        }
    }
    func load(preservePosition: Bool = false) {
        guard !episodeBusy else{return}
        backgroundServiceStopped=false
        wantsPlayback = true
        transportRetries = 0; recovery.reset()
        startPlayback(requestedPosition:nil,autoplay:playWhenReady)
    }
    private func startPlayback(requestedPosition: Double?, autoplay: Bool) {
        guard let prepared, client != nil else { message = "Collega prima il Chromecast e scegli un file."; return }
        guard !loading, !loadPending, subtitleRequest == nil else { return }
        guard embeddedCaptionTask == nil || selectedEmbeddedText else { return }
        if !captionIsIndependent{promoteReadyEmbeddedText()}
        if captionIsIndependent, requestedPosition == nil, timeline.target == nil, timeline.queuedTarget == nil,
           hasLoaded, ownsCurrentMedia, loadedSourceInput == prepared.directURL, loadedAudioKey == selectedAudio,
           nativeSelection?.subtitle == nil || nativeSelection?.subtitle == "none" {
            syncIndependentCaptions();return
        }
        if requestedPosition == nil, timeline.target == nil, timeline.queuedTarget == nil, applyLoadedSubtitleTrack() { return }
        // Prepare standard WebVTT independently. A pending or failed text
        // extraction must never force a video conversion or delay its start.
        if !captionIsIndependent,selectedEmbeddedText,!attemptedEmbeddedCaptions.contains(selectedSubtitle){beginEmbeddedTextPreparation()}
        capturePosition()
        let requested = timeline.consumeQueued() ?? requestedPosition
        let audio = selectedAudio, subtitle = selectedSubtitle
        PlaybackDiagnostics.record(.prepare,["phase":"request","audio":audio,"subtitle":subtitle,"position":PlaybackDiagnostics.number(requested ?? lastGoodPosition)])
        let separateCaption=captionIsIndependent
        let burnedSubtitle = !separateCaption && !selectedEmbeddedText && subtitle.hasPrefix("vlc_") ? subtitle : "none"
        let textSelected = !separateCaption && ["external","embedded"].contains(subtitle)
        let needsLocal = DirectCaptionPolicy.needsMediaProxy(force:forceLocalPlayback,compatible:prepared.directCompatible,audioChanged:audio != prepared.defaultAudioKey,burn:burnedSubtitle != "none",textSelected:textSelected,corsAllowed:mediaCORS[prepared.directURL])
        if !needsLocal {
            if textSelected { prepareDirectCaption() }
            // Preparing text must not reload an already playing direct movie.
            if requested == nil,timeline.target == nil,hasLoaded,!localProcessing,ownsCurrentMedia,loadedSourceInput == prepared.directURL,loadedAudioKey == audio,
               textSelected,!directCaptionReady{return}
            let target = requested ?? timeline.target ?? lastGoodPosition
            timeline.begin(at:target); position = target; lastGoodPosition = target
            stopLocalProcessing(); compatibilityMode = false; processingDetail = "Video originale · \(prepared.video?.label ?? prepared.videoDescription)"
            sendLoad(preservePosition:true,autoplay:playWhenReady)
            return
        }
        if directCaptionTask != nil{
            directCaptionTask?.cancel();directCaptionTask=nil;directCaptionAttempt="";standardCaptions.cancelPreparation()
            if embeddedCaptionTask==nil{subtitleDownloadBusy=false}
        }
        let appearance = burnedSubtitle == "none" ? SubtitleAppearance() : SubtitleAppearance.load()
        let bitmapSubtitle=prepared.subtitles.first(where:{$0.key==burnedSubtitle})?.codec.lowercased()=="bdpg"
        let selection = NativeSelection(input:prepared.directURL,audio:audio,subtitle:burnedSubtitle,appearance:appearance,external:separateCaption ? nil:externalSubtitleURL,extracted:separateCaption ? nil:embeddedSubtitleURL,captionIdentity:separateCaption ? "receiver":subtitleIdentity,bitmapDelay:bitmapSubtitle ? subtitleDelay:0)
        // Burning a subtitle is not a permanent reason to re-encode the movie.
        // Re-evaluate the original-video route when the selected tracks change.
        let previousFallback=localFallbackLevel
        if selection != nativeSelection { localFallbackLevel = 0 }
        let requiredCaption = separateCaption ? nil:subtitle == "external" ? 1 : subtitle == "embedded" ? 2 : nil
        let delay = subtitleDelay
        if requested == nil, hasLoaded, ownsCurrentMedia, selection == nativeSelection, let engine = nativeEngine, engine.running, let url = engine.streamURL, requiredCaption == nil || engine.captionURLs[requiredCaption!] != nil {
            sendLoad(preservePosition:false,urlOverride:url,contentTypeOverride:engine.contentType,autoplay:playWhenReady)
            return
        }
        guard let host = castSession?.device.ipAddress, CastWire.localIPv4(host) else { playbackIssue = EmbeddedMediaError.address.localizedDescription; return }
        let start = requested ?? timeline.target ?? lastGoodPosition
        backgroundProcessing.begin(duration:prepared.duration,position:start) { [weak self] in
            self?.backgroundProcessingExpired()
        }
        let sourceToken = sourceRequests.generation
        let previousRequests=streamRequests,previousTimeline=timeline
        let previousLoaded=hasLoaded && ownsCurrentMedia
        let previousDetail=processingDetail
        let previousChoice=confirmedChoice
        let previousEngine=nativeEngine
        streamRequests.invalidate()
        let streamToken = streamRequests.generation
        timeline.begin(at:start); progress.reset(); position = start; lastGoodPosition = start
        // Freeze the old stream while replacing its audio/subtitle pipeline.
        // Its late statuses must not move the new original-media timeline.
        if ownsCurrentMedia {
            nativeEngine?.setReceiverPaused(true)
            _ = client?.pause()
        }
        checkingStream = true; loading = true; playbackIssue = nil
        processingDetail = "Preparazione del flusso…"
        message = "Preparo il flusso sull’iPhone…"
        updateActivity(status:"Caricamento")
        streamCheckTask = Task { [weak self] in
            let background=CastBackgroundLease(name:"Prepare Cast stream") { [weak self] in
                guard let self,self.streamRequests.accepts(streamToken) else{return}
                self.backgroundProcessingExpired()
            }
            defer {background.end()}
            do {
                guard let self else { return }
                var captions: [Int:String] = [:]
                for (id,url) in [(1,selection.external),(2,selection.extracted)] {
                    if id == requiredCaption {
                        if id == 2, let text = self.extractedCaptionText { captions[id] = text }
                        else if let url, let text = await self.readCaption(url) { captions[id] = text }
                    }
                    try self.validateStream(source:sourceToken,stream:streamToken)
                }
                if let requiredCaption, captions[requiredCaption] == nil {
                    let languages = self.handoff?.subtitleLanguage == "ita" ? ["it","ita"] : ["en","eng"]
                    self.selectedSubtitle = prepared.subtitles.first(where:{languages.contains($0.language.lowercased())})?.key ?? "none"
                    self.checkingStream = false; self.loading = false
                    self.startPlayback(requestedPosition:start,autoplay:autoplay)
                    return
                }
                let convertVideo = prepared.requiresVideoConversion || burnedSubtitle != "none"
                let modes = EmbeddedMediaEngine.modes(requiresVideo:convertVideo,fallbackLevel:self.localFallbackLevel,video:prepared.video,burn:burnedSubtitle != "none",bitmap:bitmapSubtitle)
                var lastError: Error = EmbeddedMediaError.encoder
                for mode in modes {
                    PlaybackDiagnostics.record(.prepare,["phase":"attempt","mode":String(describing:mode),"generation":String(streamToken.uuidString.prefix(8)),"offset":PlaybackDiagnostics.number(start)])
                    try self.validateStream(source:sourceToken,stream:streamToken)
                    self.message = mode == .copy ? "Adatto l’audio sull’iPhone, mantenendo il video originale…" : "Adatto il video sull’iPhone per il Chromecast…"
                    let engine = EmbeddedMediaEngine()
                    do {
                        let audioID = prepared.audio.count > 1 && audio.hasPrefix("vlc_") ? Int(audio.dropFirst(4)) : nil
                        let audioTrack = prepared.audio.first(where:{$0.key == audio})
                        let copyAudio = ["aac","mp3"].contains(audioTrack?.codec.lowercased() ?? "") && (audioTrack?.channels ?? 0) > 0 && (audioTrack?.channels ?? 0) <= 2
                        let subtitleID = burnedSubtitle.hasPrefix("vlc_") ? Int(burnedSubtitle.dropFirst(4)) : nil
                        let repairAudio = AudioRepairPipe.required(audioTrack?.codec ?? "")
                        let audioIndex = prepared.audio.firstIndex(where:{$0.key == audio}) ?? 0
                        let subtitleIndex = prepared.subtitles.firstIndex(where:{$0.key == burnedSubtitle})
                        let url = try await engine.start(input:prepared.directURL,deviceIP:host,start:start,videoMode:mode,audioID:audioID,subtitleID:subtitleID,style:appearance,copyAudio:copyAudio,repairAudio:repairAudio,audioIndex:audioIndex,subtitleIndex:subtitleIndex,captions:captions,subtitleDelay:delay,video:prepared.video,bitmapSubtitle:bitmapSubtitle,audioCodec:audioTrack?.codec ?? "")
                        try self.validateStream(source:sourceToken,stream:streamToken)
                        guard self.prepared?.directURL == prepared.directURL, self.selectedAudio == audio, separateCaption ? self.captionIsIndependent:self.selectedSubtitle == subtitle,
                              separateCaption || (self.externalSubtitleURL == selection.external && self.subtitleIdentity == selection.captionIdentity),
                              requiredCaption.map({engine.captionID(kind:$0,delay:self.subtitleDelay) != nil}) ?? true,
                              burnedSubtitle == "none" || SubtitleAppearance.load() == appearance else {
                            engine.stop()
                            self.checkingStream = false; self.loading = false
                            self.startPlayback(requestedPosition:start,autoplay:self.playWhenReady)
                            return
                        }
                        self.nativeEngine?.stop()
                        self.nativeEngine = engine;self.nativeEngineGeneration=streamToken; self.nativeSelection = selection
                        if burnedSubtitle != "none" { engine.setBurnedSubtitleDelay(self.subtitleDelay) }
                        PlaybackDiagnostics.record(.prepare,["phase":"ready","mode":String(describing:mode)])
                        engine.refreshBackground()
                        self.localProcessing = true; self.compatibilityMode = true; CastActivityCommands.usesLocalStream = true
                        self.localFallbackLevel = mode == .copy ? 0 : mode == .softwareVP8 ? 2 : 1
                        let rate = prepared.video.map { format in
                            format.conversionFrameRate.map { "\(Int($0)) fps" } ?? format.frameRateLabel
                        } ?? "fps originali"
                        let format = prepared.video
                        let scale = format.map{ min(1,min(1920 / Double(max(1,$0.width)),1080 / Double(max(1,$0.height)))) } ?? 1
                        let dimensions = format.flatMap{ $0.width > 0 && $0.height > 0 ? "\(Int(Double($0.width)*scale)/2*2)×\(Int(Double($0.height)*scale)/2*2)" : nil } ?? "risoluzione non rilevata"
                        self.processingDetail = mode == .copy ? "Video originale · \(prepared.video?.label ?? prepared.videoDescription) · \(copyAudio ? "audio originale" : "audio AAC stereo")" : "Video convertito \(mode == .softwareVP8 ? "VP8" : "H.264") · \(dimensions) · \(rate)"
                        engine.onFailure = { [weak self, weak engine] allowVideoConversion in
                            guard let self, let engine, self.nativeEngine === engine, self.sourceRequests.accepts(sourceToken), self.streamRequests.accepts(streamToken), !self.checkingStream else { return }
                            self.loadPending=false;self.loading=false;self.loadTimeout?.cancel();self.loadRequest=nil
                            let sameProducer=self.recovery.retrySameProducer(mode:String(describing:engine.diagnosticMode),code:engine.backendExitCode)
                            if sameProducer{PlaybackDiagnostics.record(.recovery,["phase":"retry_same_producer","mode":String(describing:engine.diagnosticMode),"attempt":String(self.recovery.attempts)])}
                            if !self.recoverPlayback(allowVideoConversion:allowVideoConversion && !sameProducer) { self.playbackIssue = "Il motore integrato ha interrotto la conversione. La posizione è conservata." }
                        }
                        self.lastGoodPosition = self.timeline.queuedTarget ?? max(0,start); self.position = self.lastGoodPosition
                        self.checkingStream = false; self.loading = false
                        self.sendLoad(preservePosition:false,urlOverride:url,contentTypeOverride:engine.contentType,autoplay:self.playWhenReady)
                        return
                    } catch {
                        PlaybackDiagnostics.record(.error,["phase":"prepare","mode":String(describing:mode),"kind":String(describing:type(of:error)),"code":(error as? EmbeddedMediaError).map{String(describing:$0)} ?? "other"])
                        engine.stop(); lastError = error
                        try self.validateStream(source:sourceToken,stream:streamToken)
                    }
                }
                throw lastError
            } catch {
                guard !Task.isCancelled, let self, self.sourceRequests.accepts(sourceToken), self.streamRequests.accepts(streamToken) else { return }
                self.checkingStream = false; self.loading = false
                // A failed candidate never owns the current receiver session.
                // Restore the generation and timeline as well as the UI, or
                // old receiver updates and the next selection remain blocked.
                if previousLoaded,previousEngine?.failed != true,self.ownsCurrentMedia {
                    let latestChoiceChanged=self.selectedAudio != audio || self.selectedSubtitle != subtitle
                    self.streamRequests=previousRequests;self.timeline=self.timeline.restoring(previousTimeline)
                    self.hasLoaded=true;self.processingDetail=previousDetail;self.localFallbackLevel=previousFallback
                    if !latestChoiceChanged,let previousChoice {
                        self.selectedAudio=previousChoice.audio;self.selectedSubtitle=previousChoice.subtitle
                        self.selectedOnlineSubtitle=previousChoice.online;self.subtitleDelay=previousChoice.delay
                        self.trackChangePending=false
                    }
                    self.nativeEngine?.setReceiverPaused(!self.playWhenReady)
                    _ = self.playWhenReady ? self.client?.play():self.client?.pause()
                    self.subtitleIssue="Questa traccia non si è avviata. Ho mantenuto la riproduzione precedente."
                    self.subtitlePlaybackWarning=self.subtitleIssue;self.playbackIssue=nil
                    PlaybackDiagnostics.record(.recovery,["phase":"track_rollback","audio":audio,"subtitle":subtitle])
                    self.flushQueuedSeek();self.applyPendingTrackChange();return
                }
                self.timeline.cancelActive();self.loadedStreamGeneration=nil;self.progress.reset()
                self.hasLoaded = false
                if self.advanceAutoplaySource(){return}
                self.backgroundProcessing.finish()
                self.processingDetail = "Flusso non disponibile"
                self.playbackIssue = (error as? EmbeddedMediaError)?.localizedDescription ?? "Il motore integrato non ha preparato questa sorgente."
                self.message = "Preparazione del flusso non riuscita."
            }
        }
    }
    private func validateStream(source:UUID,stream:UUID) throws {
        try validateSource(source)
        guard streamRequests.accepts(stream) else { throw CancellationError() }
    }
    private func sendLoad(preservePosition: Bool, urlOverride: URL? = nil, contentTypeOverride: String? = nil, autoplay: Bool = true) {
        PlaybackDiagnostics.record(.load,["phase":"request","local":String(urlOverride != nil),"position":PlaybackDiagnostics.number(position),"paused":String(!autoplay)])
        guard let prepared, let client else { message = "Collega prima il Chromecast e scegli un file."; return }
        guard !loadPending, subtitleRequest == nil else { return }
        // startPlayback captured the original-media position before replacing
        // the old engine. Reading it again here would lose the old stream offset.
        do {
            let url = urlOverride ?? prepared.directURL
            let directURLs = directCaptionReady || selectedSubtitle == "none" ? standardCaptions.urls : [:]
            let captions:[Int:URL] = captionIsIndependent ? [:]:urlOverride != nil ? (nativeEngine?.captionURLs ?? [:]) : directURLs
            let signature = url.absoluteString + (captionIsIndependent ? "|receiver":"|" + captions.sorted(by:{$0.key<$1.key}).map{"\($0.key):\($0.value.absoluteString)"}.joined(separator:"|"))
            let captionKind = captionIsIndependent ? nil:selectedSubtitle == "external" ? 1 : selectedSubtitle == "embedded" ? 2 : nil
            let activeID = captionKind.flatMap{kind in urlOverride != nil ? nativeEngine?.captionID(kind:kind,delay:subtitleDelay) : standardCaptions.identifier(kind:kind,delay:subtitleDelay)}.flatMap{captions[$0] == nil ? nil : $0}
            // Text tracks are attached even when disabled, so selecting one
            // later does not need to reload the movie or recreate its buffer.
            if hasLoaded && ownsCurrentMedia && loadedSignature == signature && loadedSubtitle != selectedSubtitle {
                let ids:[NSNumber] = activeID.map{[NSNumber(value:$0)]} ?? []
                if selectedSubtitle == "external" && externalSubtitleURL == nil { return }
                let request = client.setActiveTrackIDs(ids)
                subtitleRequest = request; request.delegate = self
                pendingSubtitle = selectedSubtitle
                pendingSubtitleDelay = subtitleDelay
                message = "Aggiorno i sottotitoli sulla TV…"
                return
            }
            if hasLoaded && ownsCurrentMedia && loadedSignature == signature && loadedSubtitle == selectedSubtitle { return }
            let info = GCKMediaInformationBuilder(contentURL:url)
            info.contentID = url.absoluteString
            if prepared.duration > 0 { info.streamDuration = max(1,prepared.duration - (urlOverride == nil ? 0 : streamOffset)) }
            info.streamType = .buffered
            info.contentType = contentTypeOverride ?? prepared.directContentType
            let metadata = GCKMediaMetadata(metadataType:.movie)
            metadata.setString(displayTitle, forKey:kGCKMetadataKeyTitle)
            info.metadata = metadata
            info.textTrackStyle = SubtitleAppearance.load().castStyle
            if independentCaptions.enabled{
                independentCaptions.attach(castSession)
                if captionIsIndependent{syncIndependentCaptions()}else{independentCaptions.clearSource()}
                independentCaptions.bind(epoch:streamRequests.generation.uuidString,offset:urlOverride == nil ? 0:streamOffset)
                info.customData=["bridge":independentCaptions.mediaData]
            }
            let load = GCKMediaLoadRequestDataBuilder()
            load.autoplay = NSNumber(value:autoplay)
            var textTracks: [GCKMediaTrack] = []
            for (id,url) in captions.sorted(by:{$0.key < $1.key}) {
                let kind = SubtitleWindow.kind(id)
                let language = kind == 2 ? extractedCaptionLanguage : externalSubtitleLanguage
                let center = urlOverride != nil ? (nativeEngine?.captionWindow.center ?? 0) : standardCaptions.window.center
                let delay = id >= 10000 ? center+Double(id%10000-10)/2 : center
                let name = SubtitleLanguage.name(language) + (urlOverride == nil ? "" : String(format:" · %+.1f s",delay))
                if urlOverride != nil || url.pathExtension.lowercased() == "vtt",
                   let track = GCKMediaTrack(identifier:id,contentIdentifier:url.absoluteString,contentType:"text/vtt",type:.text,textSubtype:.subtitles,name:name,languageCode:SubtitleLanguage.code(language),customData:nil) { textTracks.append(track) }
            }
            info.mediaTracks = textTracks
            load.activeTrackIDs = activeID.map{[NSNumber(value:$0)]} ?? []
            load.mediaInformation = info.build()
            if urlOverride != nil { load.startTime = 0 }
            else if preservePosition || lastGoodPosition > 0 { load.startTime = max(0, lastGoodPosition) }
            loadPending = true
            loadStartPosition = urlOverride == nil ? max(0,lastGoodPosition) : streamOffset
            lastAppliedSubtitleDelay = subtitleDelay
            playbackIssue = nil
            loading = true
            hasLoaded = false
            loadAccepted = false
            expectedContentID = url.absoluteString
            loadedSignature = signature
            loadedStreamGeneration = streamRequests.generation
            loadedSubtitle = captionKind != nil && activeID == nil ? "none" : selectedSubtitle
            loadedDirectCaptionURLs = urlOverride == nil ? captions : [:]
            loadedDirectCaptionIdentity = urlOverride == nil ? standardCaptions.identity : ""
            loadedAudioKey=selectedAudio;loadedSourceInput=prepared.directURL
            UserDefaults.standard.set(contentDigest(url.absoluteString), forKey: "cast.session.content")
            UserDefaults.standard.set(prepared.duration, forKey:"cast.session.duration")
            if let positionKey { UserDefaults.standard.set(positionKey, forKey: "cast.session.positionKey") }
            let request = client.loadMedia(with:load.build())
            loadRequest = request; request.delegate = self
            message = "Invio il video al Chromecast…"
            updateActivity(status: "Caricamento")
            loadTimeout?.cancel()
            loadTimeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled, let self, self.loadPending else { return }
                self.loadPending = false; self.loading = false; self.loadRequest = nil
                if self.advanceAutoplaySource(){return}
                if self.nativeSelection?.subtitle.hasPrefix("vlc_") == true { self.disableSubtitlesAndResume(automatic:true); return }
                if self.recoverPlayback(allowVideoConversion:false) { return }
                self.message = "La TV non ha avviato il video dopo l’adattamento automatico. La posizione è conservata."
                self.playbackIssue = "La TV non ha avviato il flusso dopo l’adattamento automatico. La posizione è conservata."
                self.updateActivity(status: "Apri l’app per riprovare")
            }
        } catch { message = "Non riesco a preparare il video con queste tracce." }
    }
    func extractEmbeddedSubtitles() {
        guard let prepared, !busy, !loading else { return }
        busy = true; subtitleFile = nil
        message = "Estraggo i sottotitoli dal file: mantieni l’app aperta…"
        work?.cancel()
        work = Task {
            var reader: SubtitleRangeReader?
            do {
                let ranges = try SubtitleRangeReader(url:prepared.directURL); reader = ranges
                let language = handoff?.subtitleLanguage == "ita" ? "it" : "en"
                let vtt = try await MkvSubtitleExtractor.extract(read:{ try await ranges.read($0,$1) },language:language)
                await ranges.close(); reader = nil
                try Task.checkCancellation()
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("subtitles-\(UUID().uuidString).vtt")
                try Data(vtt.utf8).write(to:file,options:.atomic)
                subtitleFile = file
                if let hosting = try SubtitleHosting.load() {
                    message = "Rendo disponibili i sottotitoli alla TV…"
                    let url = try await hosting.upload(vtt)
                    try Task.checkCancellation()
                    embeddedSubtitleURL = url; selectedSubtitle = "embedded"
                    message = "Sottotitoli dal file pronti. Premi Applica le tracce; verifica testo e sincronizzazione."
                } else {
                    message = "WebVTT estratto. Puoi esportarlo; per usarlo sulla TV configura un servizio sottotitoli."
                }
                busy = false
            } catch {
                if let reader { await reader.close() }
                guard !Task.isCancelled else { return }
                busy = false
                message = (error as? SubtitleError)?.localizedDescription ?? "Preparazione sottotitoli non riuscita. Il WebVTT estratto, se presente, resta esportabile."
            }
        }
    }
    private func readCaption(_ url:URL) async -> String? {
        if let text = captionCache[url] { return text }
        if let failed = captionFailures[url], Date().timeIntervalSince(failed) < 60 { return nil }
        do {
            let text = try await WebVTTTimeline.fetch(url)
            _ = try WebVTTTimeline.rebased(text,offset:0)
            if captionCache.count >= 4 { captionCache.removeAll() }
            captionCache[url] = text; return text
        } catch {
            if !Task.isCancelled {
                captionFailures[url] = Date()
                PlaybackDiagnostics.record(.error,PlaybackDiagnostics.errorFields(error,phase:"caption_read"))
                if let error=error as? SubtitleFetchError { subtitleIssue=error.localizedDescription }
            }
            return nil
        }
    }
    var externalSubtitleLanguage:String { selectedOnlineSubtitle?.lang ?? defaultSubtitleLanguage }
    var externalSubtitleLabel:String { SubtitleLanguage.name(externalSubtitleLanguage) }
    var embeddedSubtitleLabel:String { SubtitleLanguage.name(extractedCaptionLanguage) + " · dal file" }
    var hasExtractedCaption:Bool { embeddedSubtitleURL != nil || extractedCaptionText != nil }
    var selectedOnlineSubtitleID:String? { selectedOnlineSubtitle?.id }
    private var subtitleIdentity:String {
        if selectedSubtitle == "none" { return "none" }
        if selectedSubtitle == "embedded" { return "embedded:"+extractedCaptionKey }
        if selectedSubtitle.hasPrefix("vlc_") { return selectedSubtitle }
        if let chosen = selectedOnlineSubtitle { return "online:"+chosen.id+":"+SubtitleLanguage.code(chosen.lang) }
        return externalSubtitleURL.map{"source:"+String(contentDigest($0.absoluteString).prefix(24))} ?? "source"
    }
    private var subtitlePreferenceKey:String? {
        guard let handoff, let source = selectedSource else { return nil }
        return "cast.subtitle.delay." + contentDigest(handoff.type+"|"+handoff.id+"|"+source.identity+"|"+selectedSubtitle+"|"+subtitleIdentity)
    }
    var externalSubtitleURL: URL? {
        if let chosen = selectedOnlineSubtitle { return OnlineSubtitle.safeURL(chosen.url) }
        guard PlaybackPreferences.subtitlesRequested(handoff:handoff?.subtitleLanguage) else { return nil }
        return SubtitleCatalog.sourceURL(sourceSubtitleOptions,language:defaultSubtitleLanguage,
            fallback:handoff?.externalSubtitleURL,fallbackLanguage:handoff?.subtitleLanguage)
    }
    var sourceSubtitleOptions:[OnlineSubtitle] {
        (selectedSource?.subtitles ?? []).enumerated().compactMap { index,item in
            guard let raw = URL(string:item.url), let url = OnlineSubtitle.safeURL(raw) else { return nil }
            return OnlineSubtitle(id:item.id ?? "source-"+String(contentDigest(url.absoluteString).prefix(16)),url:url,lang:item.lang ?? "und",label:item.label ?? "Sottotitoli Stremio \(index+1)",provider:"Stremio")
        }
    }
    @Published private(set) var captionCacheBytes=0
    @Published private(set) var captionCacheMessage:String?
    func refreshCaptionCacheInfo(){captionCacheBytes=completeCaptionCache.diskBytes()}
    func clearCaptionCache(){
        let cleared=completeCaptionCache.clear()
        captionCache.removeAll();captionFailures.removeAll();refreshCaptionCacheInfo()
        captionCacheMessage=cleared ? "Cache sottotitoli svuotata. La traccia attiva resta disponibile.":"Non riesco a eliminare tutti i file della cache. Puoi riprovare."
    }
    var defaultSubtitleLanguage:String { PlaybackPreferences.subtitleLanguage(handoff:handoff?.subtitleLanguage) }
    private func clearSubtitleChoices() {
        independentCaptions.clearSource()
        subtitleChoices.invalidate(); subtitleSearchTask?.cancel(); subtitlePickTask?.cancel()
        embeddedCaptionTask?.cancel(); embeddedCaptionTask = nil; attemptedEmbeddedCaptions.removeAll()
        subtitlePlaybackWarning = nil
        subtitleSearchTask = nil; subtitlePickTask = nil
        onlineSubtitles = []; selectedOnlineSubtitle = nil; subtitleSearchBusy = false; subtitleDownloadBusy = false; subtitleIssue = nil
        subtitleSearchStamp = .distantPast; subtitleRetryAfter = .distantPast
        extractedCaptionText = nil; extractedCaptionKey = ""; extractedCaptionLanguage = "en"
        cachedCaptionCatalog=nil
        subtitleDelay = 0; lastAppliedSubtitleDelay = 0; pendingSubtitleDelay = nil
    }
    func searchSubtitles(refresh:Bool = false) {
        guard let handoff, let source = selectedSource, !subtitleSearchBusy else { return }
        if Date() < subtitleRetryAfter { return }
        if !refresh && Date().timeIntervalSince(subtitleSearchStamp) < 300 { return }
        subtitleSearchTask?.cancel(); subtitleSearchBusy = true; subtitleIssue = nil
        let sourceToken = sourceRequests.generation
        let filename = source.filename, size = source.behaviorHints?.videoSize, original = prepared?.directURL
        subtitleSearchTask = Task {
            defer { if sourceRequests.accepts(sourceToken) { subtitleSearchBusy = false } }
            do {
                var hash = source.behaviorHints?.videoHash
                if hash == nil, let size, size >= 131072, size < 1 << 50, let original,
                   let reader = try? SubtitleRangeReader(url:original) {
                    defer { Task { await reader.close() } }
                    if let first = try? await reader.read(0,65536), let last = try? await reader.read(Int(size)-65536,65536) { hash = SubtitleCatalog.hash(first:first,last:last,size:size) }
                }
                try validateSource(sourceToken)
                let results = try await SubtitleCatalog.search(type:handoff.type,id:handoff.id,filename:filename,size:size,hash:hash,fps:prepared?.video?.frameRate ?? 0)
                try validateSource(sourceToken)
                onlineSubtitles = results; subtitleSearchStamp = Date()
                PlaybackDiagnostics.record(.tracks,["phase":"catalog_ready","tracks":String(results.count),"kind":hash == nil ? "identity" : "file_hash"])
                if results.isEmpty { subtitleIssue = "OpenSubtitles non ha trovato versioni per questo contenuto." }
            } catch {
                guard !Task.isCancelled, sourceRequests.accepts(sourceToken) else { return }
                if case SubtitleCatalogError.limited(let seconds) = error { subtitleRetryAfter = Date().addingTimeInterval(Double(seconds)) }
                subtitleIssue = (error as? SubtitleCatalogError)?.localizedDescription ?? "Non riesco a contattare OpenSubtitles. Riprova tra poco."
                PlaybackDiagnostics.record(.error,["phase":"subtitle_catalog","kind":String(describing:type(of:error)),"code":String((error as NSError).code)])
            }
        }
    }
    func pickSubtitle(_ subtitle:OnlineSubtitle) {
        guard let url = OnlineSubtitle.safeURL(subtitle.url) else { return }
        directCaptionTask?.cancel();directCaptionTask=nil;directCaptionAttempt="";standardCaptions.cancelPreparation()
        subtitleChoices.invalidate(); let choice = subtitleChoices.generation, source = sourceRequests.generation
        trackApplyTask?.cancel(); trackApplyTask = nil
        embeddedCaptionTask?.cancel(); embeddedCaptionTask = nil
        subtitlePickTask?.cancel(); subtitleDownloadBusy = true; subtitleIssue = nil
        subtitlePickTask = Task {
            defer { if subtitleChoices.accepts(choice) { subtitleDownloadBusy = false } }
            do {
                let text = try await WebVTTTimeline.fetch(url)
                try validateSource(source); guard subtitleChoices.accepts(choice) else { throw CancellationError() }
                if captionCache.count >= 8 { captionCache.removeAll() }
                captionFailures[url] = nil; captionCache[url] = text; selectedOnlineSubtitle = subtitle; selectedSubtitle = "external"
                subtitlePlaybackWarning = nil
                restoreSubtitleDelay()
                PlaybackPreferences.remember(audio:nil,subtitle:subtitle.lang)
                PlaybackDiagnostics.record(.tracks,["phase":"subtitle_chosen","kind":subtitle.provider == "Stremio" ? "stremio" : "opensubtitles","subtitle":String(contentDigest(subtitle.id).prefix(8)),"codec":"webvtt"])
                if hasLoaded { load(preservePosition:true) }
            } catch {
                guard !Task.isCancelled, sourceRequests.accepts(source), subtitleChoices.accepts(choice) else { return }
                subtitleIssue = (error as? SubtitleFetchError)?.localizedDescription ?? "Non riesco a scaricare questa versione dei sottotitoli. Controlla la connessione o scegline un’altra."
                var fields=PlaybackDiagnostics.errorFields(error,phase:"subtitle_download")
                fields["kind"]=subtitle.provider == "Stremio" ? "stremio":"opensubtitles"
                if case SubtitleFetchError.http(let status)=error { fields["status"]=String(status) }
                if case SubtitleFetchError.format=error { fields["result"]="format" }
                if case SubtitleFetchError.limit=error { fields["result"]="limit" }
                PlaybackDiagnostics.record(.error,fields)
            }
        }
    }
    private func restoreSubtitleDelay(fallback:Double = 0) {
        let saved = subtitlePreferenceKey.flatMap{UserDefaults.standard.object(forKey:$0) as? NSNumber}?.doubleValue
        subtitleDelay = SubtitleWindow.normalized(saved ?? fallback)
    }
    func changeSubtitleDelay(_ value:Double) {
        subtitleIssue = nil
        subtitleDelay = SubtitleWindow.normalized(value)
        if let key = subtitlePreferenceKey { UserDefaults.standard.set(subtitleDelay,forKey:key) }
        PlaybackDiagnostics.record(.tracks,["kind":"subtitle_delay","seconds":PlaybackDiagnostics.number(subtitleDelay)])
        applySubtitleTiming()
    }
    private func applySubtitleTiming() {
        if captionIsIndependent{syncIndependentCaptions();return}
        if selectedEmbeddedText{
            guard hasLoaded,!loading,!checkingStream,embeddedCaptionTask == nil,extractedCaptionKey == selectedSubtitle,extractedCaptionText != nil else{return}
            promoteReadyEmbeddedText();load(preservePosition:true);return
        }
        guard selectedSubtitle != "none", hasLoaded, !loading, !checkingStream, trackApplyTask == nil, embeddedCaptionTask == nil, timeline.target == nil, timeline.queuedTarget == nil else { return }
        if !localProcessing,["external","embedded"].contains(selectedSubtitle){
            if applyLoadedSubtitleTrack(){return}
            prepareDirectCaption()
            if directCaptionReady || prepared.map({mediaCORS[$0.directURL] == false}) == true{load(preservePosition:true)}
            return
        }
        if let nativeSelection, nativeSelection.external != externalSubtitleURL || nativeSelection.captionIdentity != subtitleIdentity {
            guard subtitleRequest == nil else { return }; load(preservePosition:true); return
        }
        if selectedSubtitle.hasPrefix("vlc_") {
            if nativeEngine?.usesBitmapOverlay == true,lastAppliedSubtitleDelay != subtitleDelay { load(preservePosition:true);return }
            nativeEngine?.setBurnedSubtitleDelay(subtitleDelay); lastAppliedSubtitleDelay = subtitleDelay; return
        }
        guard subtitleRequest == nil else { return }
        let kind = selectedSubtitle == "embedded" ? 2 : 1
        if let id = nativeEngine?.captionID(kind:kind,delay:subtitleDelay), let client {
            guard lastAppliedSubtitleDelay != subtitleDelay else { return }
            let request = client.setActiveTrackIDs([NSNumber(value:id)])
            subtitleRequest = request; request.delegate = self; pendingSubtitle = selectedSubtitle; pendingSubtitleDelay = subtitleDelay
        } else {
            trackApplyTask?.cancel()
            trackApplyTask = Task {
                try? await Task.sleep(nanoseconds:450_000_000)
                guard !Task.isCancelled, hasLoaded, !loading else { return }
                trackApplyTask = nil
                capturePosition(); startPlayback(requestedPosition:lastGoodPosition,autoplay:playWhenReady)
            }
        }
    }
    func disableSubtitlesAndResume(automatic:Bool = false) {
        directCaptionTask?.cancel();directCaptionTask=nil;directCaptionAttempt="";standardCaptions.cancelPreparation()
        if automatic {
            subtitlePlaybackWarning = "La traccia nel file ha bloccato la riproduzione. Il video è ripartito senza sottotitoli; puoi scegliere un’altra traccia. La tua lingua preferita è conservata."
        } else {
            PlaybackPreferences.remember(audio:nil,subtitle:"none")
            subtitlePlaybackWarning = nil
        }
        subtitleChoices.invalidate(); embeddedCaptionTask?.cancel(); embeddedCaptionTask = nil
        trackApplyTask?.cancel(); trackApplyTask = nil
        selectedSubtitle = "none"; subtitleDelay = 0; subtitlePickTask?.cancel(); subtitleDownloadBusy = false
        streamCheckTask?.cancel(); streamRequests.invalidate(); checkingStream = false
        loadTimeout?.cancel(); loadPending = false; loading = false; subtitleRequest = nil; pendingSubtitle = nil; pendingSubtitleDelay = nil
        nativeEngine?.setReceiverPaused(false)
        startPlayback(requestedPosition:lastGoodPosition,autoplay:playWhenReady)
        message = "Riprendo il video senza la traccia di sottotitoli che non si è avviata."
        PlaybackDiagnostics.record(.recovery,["phase":"subtitle_disabled","position":PlaybackDiagnostics.number(lastGoodPosition)])
    }
    func togglePlayback() { Task { _ = await handleCommand("toggle") } }
    private var captionIsIndependent:Bool{
        guard independentCaptions.enabled else{return false}
        if ["none","external","embedded"].contains(selectedSubtitle){return true}
        let codec=prepared?.subtitles.first(where:{$0.key==selectedSubtitle})?.codec.lowercased() ?? ""
        return ["subt","srt","subrip","ssa","ass","text","utf8","wvtt","webvtt","tx3g","mov_text","stpp","ttml"].contains(codec)
    }
    private func syncIndependentCaptions(){
        guard captionIsIndependent,let prepared else{return}
        independentCaptions.synchronize(input:prepared.directURL,tracks:prepared.subtitles,selected:selectedSubtitle,extractedKey:extractedCaptionKey,
            external:externalSubtitleURL,externalText:externalSubtitleURL.flatMap{captionCache[$0]},source:sourceRequests.generation.uuidString,
            position:timeline.target ?? lastGoodPosition,duration:prepared.duration,delay:subtitleDelay)
    }
    func retryIndependentCaptions(){
        if let url=externalSubtitleURL { captionFailures[url]=nil;captionCache[url]=nil }
        if independentCaptions.enabled{independentCaptions.retry()}
        else if selectedEmbeddedText{subtitleChoices.invalidate();attemptedEmbeddedCaptions.remove(selectedSubtitle);beginEmbeddedTextPreparation()}
        else if !localProcessing,["external","embedded"].contains(selectedSubtitle){directCaptionAttempt="";subtitleIssue=nil;subtitlePlaybackWarning=nil;prepareDirectCaption()}
        else if let selectedOnlineSubtitle{pickSubtitle(selectedOnlineSubtitle)}
    }
    var supportsOriginalSubtitleStyle:Bool{independentCaptions.enabled}
    var preservesOriginalSubtitleStyle:Bool{ReceiverConfiguration.preserveASS}
    func setOriginalSubtitleStyle(_ value:Bool){UserDefaults.standard.set(value,forKey:"cast.subtitle.originalASS");applySubtitleAppearance()}
    /// Only edit registered receiver tracks. Do not pause the producer, replace
    /// its URL, issue LOAD or touch the timeline for a text caption toggle.
    private func applyLoadedSubtitleTrack() -> Bool {
        if hasLoaded,ownsCurrentMedia,!localProcessing,!forceLocalPlayback,let client,let prepared,loadedSourceInput==prepared.directURL,loadedAudioKey==selectedAudio,mediaCORS[prepared.directURL] != false || selectedSubtitle=="none"{
            let ids:[NSNumber]
            if selectedSubtitle=="none"{ids=[]}
            else{
                guard directCaptionReady,loadedDirectCaptionIdentity==subtitleIdentity,
                      let kind=selectedSubtitle=="embedded" ? 2:selectedSubtitle=="external" ? 1:nil,
                      let id=standardCaptions.identifier(kind:kind,delay:subtitleDelay),
                      loadedDirectCaptionURLs[id]==standardCaptions.urls[id] else{return false}
                ids=[NSNumber(value:id)]
            }
            if loadedSubtitle==selectedSubtitle && lastAppliedSubtitleDelay==subtitleDelay{return true}
            let request=client.setActiveTrackIDs(ids);subtitleRequest=request;request.delegate=self
            pendingSubtitle=selectedSubtitle;pendingSubtitleDelay=subtitleDelay
            PlaybackDiagnostics.record(.tracks,["phase":"direct_text_switch","subtitle":selectedSubtitle])
            return true
        }
        guard hasLoaded, ownsCurrentMedia, let client, let prepared,
              let selection = nativeSelection, selection.input == prepared.directURL,
              selection.audio == selectedAudio, selection.subtitle == "none",
              let engine = nativeEngine, engine.running else { return false }
        let ids:[NSNumber]
        if selectedSubtitle == "none" { ids = [] }
        else {
            guard selection.captionIdentity == subtitleIdentity else { return false }
            let kind = selectedSubtitle == "embedded" ? 2 : selectedSubtitle == "external" ? 1 : nil
            guard let kind, let id = engine.captionID(kind:kind,delay:subtitleDelay) else { return false }
            ids = [NSNumber(value:id)]
        }
        if loadedSubtitle == selectedSubtitle && lastAppliedSubtitleDelay == subtitleDelay { return true }
        let request = client.setActiveTrackIDs(ids)
        subtitleRequest = request; request.delegate = self
        pendingSubtitle = selectedSubtitle; pendingSubtitleDelay = subtitleDelay
        message = "Aggiorno i sottotitoli sulla TV…"
        PlaybackDiagnostics.record(.tracks,["phase":"text_switch","subtitle":selectedSubtitle,"position":PlaybackDiagnostics.number(position)])
        return true
    }
    func selectSubtitle(_ key:String) {
        let selected = key == extractedCaptionKey && extractedCaptionText != nil ? "embedded" : key
        guard selected != selectedSubtitle else { return }
        selectedSubtitle = selected
        subtitlePlaybackWarning = nil
        attemptedEmbeddedCaptions.remove(key)
        tracksChanged(audio:false)
    }
    func selectAudio(_ key:String) {
        guard key != selectedAudio else { return }
        selectedAudio = key
        tracksChanged(audio:true)
    }
    func tracksChanged(audio:Bool) {
        PlaybackDiagnostics.record(.tracks,["kind":audio ? "audio" : "subtitle","audio":selectedAudio,"subtitle":selectedSubtitle,"position":PlaybackDiagnostics.number(position)])
        if !audio {
            PlaybackDiagnostics.record(.tracks,["phase":"subtitle_route","subtitle":selectedSubtitle,"codec":prepared?.subtitles.first(where:{$0.key==selectedSubtitle})?.codec ?? "external","kind":selectedEmbeddedText ? "text":selectedSubtitle.hasPrefix("vlc_") ? "overlay":"separate"])
            if let url=externalSubtitleURL { captionFailures[url]=nil }
        }
        guard let prepared, !busy else { return }
        trackChangePending = true
        if audio { PlaybackPreferences.remember(audio:prepared.audio.first(where:{$0.key == selectedAudio}),subtitle:nil) }
        else {
            subtitleChoices.invalidate(); subtitlePickTask?.cancel(); subtitleDownloadBusy = false
            directCaptionTask?.cancel();directCaptionTask=nil;directCaptionAttempt="";standardCaptions.cancelPreparation()
            embeddedCaptionTask?.cancel(); embeddedCaptionTask = nil
            restoreSubtitleDelay()
            let language = selectedSubtitle == "none" ? "none" : selectedSubtitle == "external" ? externalSubtitleLanguage : selectedSubtitle == "embedded" ? extractedCaptionLanguage : prepared.subtitles.first(where:{$0.key == selectedSubtitle})?.language
            PlaybackPreferences.remember(audio:nil,subtitle:language)
        }
        trackApplyTask?.cancel()
        trackApplyTask = Task {
            try? await Task.sleep(nanoseconds:400_000_000)
            guard !Task.isCancelled else { return }
            trackApplyTask = nil
            applyPendingTrackChange()
        }
    }
    private func applyPendingTrackChange() {
        // A track selection during LOAD/seek is an intent, not a disposable
        // callback. Use the latest audio and subtitle together after the receiver
        // is ready; a subtitle tap must not erase an earlier queued audio change.
        guard trackChangePending, trackApplyTask == nil,
              !loading, !loadPending, !checkingStream, subtitleRequest == nil,
              timeline.target == nil, timeline.queuedTarget == nil else { return }
        if !hasLoaded {
            guard playbackIssue != nil else { return }
            trackChangePending=false;load(preservePosition:true);return
        }
        guard ownsCurrentMedia else { return }
        trackChangePending = false
        if loadedAudioKey != selectedAudio { load(preservePosition:true); return }
        if captionIsIndependent, nativeSelection?.subtitle == nil || nativeSelection?.subtitle == "none" {
            syncIndependentCaptions(); return
        }
        if !captionIsIndependent, selectedEmbeddedText { beginEmbeddedTextPreparation(); return }
        load(preservePosition:true)
    }
    private var selectedEmbeddedText:Bool{
        guard selectedSubtitle.hasPrefix("vlc_"),let track=prepared?.subtitles.first(where:{$0.key==selectedSubtitle}) else{return false}
        return ["subt","srt","subrip","ssa","ass","text","utf8","wvtt","webvtt","tx3g","mov_text","stpp","ttml"].contains(track.codec.lowercased())
    }
    private func promoteReadyEmbeddedText(){
        guard selectedEmbeddedText,extractedCaptionKey==selectedSubtitle,extractedCaptionText != nil else{return}
        let previousDelay=subtitleDelay;selectedSubtitle="embedded";restoreSubtitleDelay(fallback:previousDelay)
        if let key=subtitlePreferenceKey{UserDefaults.standard.set(subtitleDelay,forKey:key)}
    }
    private var directCaptionReady:Bool{
        guard standardCaptions.identity==subtitleIdentity,standardCaptions.peer==castSession?.device.ipAddress,
              let kind=selectedSubtitle=="embedded" ? 2:selectedSubtitle=="external" ? 1:nil else{return false}
        return standardCaptions.identifier(kind:kind,delay:subtitleDelay) != nil
    }
    private func prepareDirectCaption(){
        guard !captionIsIndependent,!directCaptionReady,let prepared,let peer=castSession?.device.ipAddress,
              let kind=selectedSubtitle=="embedded" ? 2:selectedSubtitle=="external" ? 1:nil else{return}
        let identity=subtitleIdentity,delay=subtitleDelay
        let key=contentDigest(prepared.directURL.absoluteString)+identity+peer+String(delay)
        guard directCaptionAttempt != key else{return}
        directCaptionTask?.cancel();standardCaptions.cancelPreparation();directCaptionAttempt=key
        let source=sourceRequests.generation,choice=subtitleChoices.generation
        subtitleDownloadBusy=true;subtitlePreparation="Collego i sottotitoli alla TV…"
        directCaptionTask=Task{
            defer{if sourceRequests.accepts(source),subtitleChoices.accepts(choice),directCaptionAttempt==key{directCaptionTask=nil;subtitleDownloadBusy=false}}
            do{
                let allowed:Bool
                if let cached=mediaCORS[prepared.directURL]{allowed=cached}
                else{allowed=await StandardCaptionHost.supportsDirectMedia(prepared.directURL)}
                try validateSource(source);try Task.checkCancellation()
                guard subtitleChoices.accepts(choice),subtitleIdentity==identity,subtitleDelay==delay else{throw CancellationError()}
                if mediaCORS.count>=8{mediaCORS.removeAll()};mediaCORS[prepared.directURL]=allowed
                if allowed{
                    let text:String
                    if kind==2,let extractedCaptionText{text=extractedCaptionText}
                    else if let url=kind==1 ? externalSubtitleURL:embeddedSubtitleURL,let loaded=await readCaption(url){text=loaded}
                    else{throw CaptionFailure.network}
                    try validateSource(source);try Task.checkCancellation()
                    guard subtitleChoices.accepts(choice),subtitleIdentity==identity,subtitleDelay==delay else{throw CancellationError()}
                    try await standardCaptions.prepare(text:text,kind:kind,identity:identity,delay:delay,peer:peer,localIP:EmbeddedMediaEngine.localAddress(to:peer))
                    try validateSource(source);try Task.checkCancellation()
                    subtitleIssue=nil;subtitlePlaybackWarning=nil
                }
                PlaybackDiagnostics.record(.tracks,["phase":"caption_route","mode":allowed ? "direct":"media_proxy"])
                if hasLoaded,!loading,!checkingStream,!loadPending,timeline.target==nil,timeline.queuedTarget==nil{load(preservePosition:true)}
            }catch{
                guard !Task.isCancelled,sourceRequests.accepts(source),subtitleChoices.accepts(choice),directCaptionAttempt==key else{return}
                subtitleIssue="Non riesco a collegare questi sottotitoli. Il video continua; puoi riprovare."
                subtitlePlaybackWarning=subtitleIssue
                PlaybackDiagnostics.record(.tracks,["phase":"direct_caption_failed","code":(error as? CaptionFailure).map{String(describing:$0)} ?? "network"])
            }
        }
    }
    private func beginEmbeddedTextPreparation(){
        guard selectedEmbeddedText else{return}
        embeddedCaptionTask?.cancel();attemptedEmbeddedCaptions.insert(selectedSubtitle)
        let source=sourceRequests.generation,choice=subtitleChoices.generation
        embeddedCaptionTask=Task{
            guard !Task.isCancelled,sourceRequests.accepts(source),subtitleChoices.accepts(choice) else{return}
            await extractSelectedTextTrack()
            guard !Task.isCancelled,sourceRequests.accepts(source),subtitleChoices.accepts(choice) else{return}
            embeddedCaptionTask=nil
            if hasLoaded,!loading,!loadPending,!checkingStream,extractedCaptionKey==selectedSubtitle,extractedCaptionText != nil{
                promoteReadyEmbeddedText();load(preservePosition:true)
            }
        }
    }
    private func extractSelectedTextTrack() async {
        guard let prepared,let ordinal=prepared.subtitles.firstIndex(where:{$0.key==selectedSubtitle}) else{return}
        let track=prepared.subtitles[ordinal],selected=selectedSubtitle,token=sourceRequests.generation,choice=subtitleChoices.generation
        subtitleDownloadBusy=true;subtitleIssue=nil
        defer{if subtitleChoices.accepts(choice){subtitleDownloadBusy=false}}
        do{
            try Task.checkCancellation()
            let text:String
            let cacheKey=CaptionDocumentCache.key(input:prepared.directURL,track:selected)
            if let cached=completeCaptionCache.get(cacheKey){
                text=cached
                PlaybackDiagnostics.record(.tracks,["phase":"full_caption_cache","subtitle":selected])
            }
            else{
                subtitlePreparation="Leggo i sottotitoli dal file. Il video può continuare…"
                PlaybackDiagnostics.record(.tracks,["phase":"full_caption_request","subtitle":selected,"codec":track.codec])
                let catalog:CaptionCatalog
                if let cached=cachedCaptionCatalog,cached.0==prepared.directURL{catalog=cached.1}
                else{catalog=try await CaptionExtractor.catalog(prepared.directURL);try validateSource(token);cachedCaptionCatalog=(prepared.directURL,catalog)}
                let actual=try catalog.selected(ordinal:ordinal,vlcID:Int(selected.dropFirst(4)),language:track.language,codec:track.codec)
                var batch:[(String,CaptionTrack)]=[(selected,actual)]
                let candidates=prepared.subtitles.enumerated().sorted{a,b in
                    let first=a.element.language==track.language,second=b.element.language==track.language
                    return first==second ? a.offset<b.offset:first
                }
                for (index,candidate) in candidates where candidate.key != selected && batch.count<4{
                    guard completeCaptionCache.get(CaptionDocumentCache.key(input:prepared.directURL,track:candidate.key))==nil,
                          let mapped=try? catalog.selected(ordinal:index,vlcID:Int(candidate.key.dropFirst(4)),language:candidate.language,codec:candidate.codec),
                          ["ass","ssa","subrip","srt","webvtt"].contains(mapped.codec),!batch.contains(where:{$0.1.index==mapped.index}) else{continue}
                    batch.append((candidate.key,mapped))
                }
                let documents=try await CaptionExtractor.fullDocuments(input:prepared.directURL,tracks:batch.map{$0.1}){[weak self] elapsed in
                    guard let self,self.sourceRequests.accepts(token),self.subtitleChoices.accepts(choice) else{return}
                    let seconds=Int(elapsed)
                    self.subtitlePreparation=seconds<8 ? "Preparo i sottotitoli dal file…":"Leggo i sottotitoli · \(seconds) s. Il video può continuare."
                }
                try validateSource(token);try Task.checkCancellation()
                guard let selectedText=documents[actual.index] else{throw CaptionFailure.process};text=selectedText
                for (key,mapped) in batch{if let document=documents[mapped.index]{completeCaptionCache.put(document,key:CaptionDocumentCache.key(input:prepared.directURL,track:key))}}
                PlaybackDiagnostics.record(.tracks,["phase":"full_caption_batch","tracks":String(documents.count)])
            }
            try validateSource(token)
            guard !Task.isCancelled,subtitleChoices.accepts(choice),selectedSubtitle==selected else{throw CancellationError()}
            extractedCaptionText=text;extractedCaptionKey=selected;extractedCaptionLanguage=track.language
            subtitlePlaybackWarning=nil
            PlaybackDiagnostics.record(.tracks,["phase":"full_caption_ready","subtitle":selected,"codec":track.codec,"bytes":String(text.utf8.count)])
        }catch{
            guard !Task.isCancelled,sourceRequests.accepts(token),subtitleChoices.accepts(choice),selectedSubtitle==selected else{return}
            subtitleIssue="Non riesco a preparare questa traccia testuale. Il video continua: puoi riprovare o scegliere i sottotitoli da Stremio e OpenSubtitles."
            subtitlePlaybackWarning=subtitleIssue
            PlaybackDiagnostics.record(.tracks,["phase":"full_caption_failed","subtitle":selected,"kind":String(describing:type(of:error)),"code":(error as? CaptionFailure).map{String(describing:$0)} ?? "other"])
        }
    }
    func applySubtitleAppearance() {
        if captionIsIndependent{syncIndependentCaptions();return}
        subtitleStyleWork?.cancel()
        subtitleStyleWork = Task {
            try? await Task.sleep(nanoseconds:400_000_000)
            guard !Task.isCancelled, ownsCurrentMedia, let client else { return }
            if selectedSubtitle.hasPrefix("vlc_") { load(preservePosition:true); return }
            client.setTextTrackStyle(SubtitleAppearance.load().castStyle)
        }
    }
    func seek(to value: Double) {
        PlaybackDiagnostics.record(.seek,["target":PlaybackDiagnostics.number(value),"position":PlaybackDiagnostics.number(position)])
        guard hasLoaded || loadPending || loading, value.isFinite else { return }
        let target = min(duration > 0 ? max(0,duration-(localProcessing ? 1 : 0)) : value,max(0,value))
        timeline.queue(at:target); position = target; lastGoodPosition = target
        updateActivity(status:"Caricamento")
        flushQueuedSeek()
    }
    private func flushQueuedSeek() {
        guard seekDispatchTask == nil, timeline.queuedTarget != nil, timeline.target == nil,
              !loading, !loadPending, !checkingStream, commandContinuation == nil, subtitleRequest == nil, hasLoaded,
              connected || !localProcessing else { return }
        let sourceToken = sourceRequests.generation
        seekDispatchTask = Task {
            try? await Task.sleep(nanoseconds:150_000_000)
            guard !Task.isCancelled, sourceRequests.accepts(sourceToken) else { return }
            guard !loading, !loadPending, !checkingStream, commandContinuation == nil, subtitleRequest == nil,
                  let target = timeline.consumeQueued() else { seekDispatchTask = nil; return }
            timeline.begin(at:target)
            var success = false
            if !connected && !localProcessing { success = await directCommand("seek:\(target)") }
            if !success { success = await performActivityCommand("seek:\(target)") }
            if !success && !localProcessing { success = await directCommand("seek:\(target)") }
            guard sourceRequests.accepts(sourceToken) else { return }
            if !success { timeline.cancelActive(); message = "La TV non ha confermato lo spostamento. Puoi riprovare." }
            seekDispatchTask = nil
            flushQueuedSeek()
        }
    }
    func stopPlayback() {
        Task { if !(await handleCommand("stop")) { endPlayback() } }
    }
    private func endPlayback() {
        independentCaptions.stop()
        if ownsCurrentMedia { client?.stop() }
        resetPlayback(); sourceResume = nil; hasLoaded = false; playing = false; message = "Riproduzione interrotta."
    }
    private func backgroundProcessingExpired() {
        // User cancellation or system expiration must not spawn another job.
        backgroundServiceStopped=true
        savePlaybackPosition(phase:"background_expired")
        if let confirmed=lastConfirmedPosition {
            lastGoodPosition=confirmed;position=confirmed
            if let positionKey {UserDefaults.standard.set(confirmed,forKey:positionKey);UserDefaults.standard.set(Date(),forKey:positionKey+".updated")}
        }
        controlRequests.invalidate();finishCommand(false)
        intentCorrectionRequest?.cancel();intentCorrectionRequest=nil;intentCorrection=nil;playbackIntent.reset()
        streamRequests.invalidate();loadedStreamGeneration=nil
        wantsPlayback=false;reconnectTask?.cancel();reconnectTask=nil
        streamCheckTask?.cancel();streamCheckTask=nil;checkingStream=false
        seekDispatchTask?.cancel();seekDispatchTask=nil
        loadTimeout?.cancel();loadPending=false;loading=false;loadRequest=nil
        if ownsCurrentMedia {_ = client?.pause()}
        independentCaptions.stop();stopCaptionDelivery();stopLocalProcessing()
        hasLoaded=false;playing=false;timeline.reset()
        lockScreen.clear(reason:"background_expired")
        playbackIssue="La trasmissione in background è stata interrotta da iOS o dai controlli di sistema. La posizione è conservata."
        message="Premi Riproduci per riprendere dal punto conservato."
    }
    private func stopLocalProcessing() {
        backgroundProcessing.finish()
        nativeEngine?.stop(); nativeEngine = nil; nativeEngineGeneration=nil; nativeSelection = nil
        localProcessing = false; CastActivityCommands.usesLocalStream = false
    }
    private func stopCaptionDelivery(){
        directCaptionTask?.cancel();directCaptionTask=nil;directCaptionAttempt=""
        embeddedCaptionTask?.cancel();embeddedCaptionTask=nil;attemptedEmbeddedCaptions.removeAll()
        standardCaptions.stop();loadedDirectCaptionURLs=[:];loadedDirectCaptionIdentity=""
        subtitleDownloadBusy=false
    }
    @discardableResult private func recoverPlayback(allowVideoConversion:Bool = true) -> Bool {
        guard prepared != nil,wantsPlayback else { return false }
        let alreadyPending=recovery.pending
        guard recovery.request() else {
            PlaybackDiagnostics.record(.recovery,["phase":"exhausted","attempt":String(recovery.attempts)])
            return false
        }
        if !alreadyPending,allowVideoConversion,localProcessing,localFallbackLevel < 2 { localFallbackLevel += 1 }
        if !localProcessing { forceLocalPlayback=true }
        PlaybackDiagnostics.record(.recovery,["phase":"queued","attempt":String(recovery.attempts),"position":PlaybackDiagnostics.number(lastConfirmedPosition ?? lastGoodPosition),"connected":String(connected)])
        if !connected { reconnectControls() }
        _ = resumePendingRecovery()
        return true
    }
    @discardableResult private func resumePendingRecovery() -> Bool {
        guard wantsPlayback,prepared != nil,client != nil,
              recovery.begin(connected:connected,blocked:checkingStream || loading || loadPending || subtitleRequest != nil) else { return false }
        transportRetries=recovery.attempts
        PlaybackDiagnostics.record(.recovery,["phase":"restart","attempt":String(recovery.attempts),"kind":timeline.target == nil && timeline.queuedTarget == nil ? "confirmed":"requested"])
        loadPending = false; loading = false; loadTimeout?.cancel(); loadRequest = nil; hasLoaded = false
        lastGoodPosition = timeline.consumeQueued() ?? timeline.target ?? lastConfirmedPosition ?? lastGoodPosition
        progress.reset()
        message = "Ripristino il flusso sulla TV…"
        startPlayback(requestedPosition:lastGoodPosition,autoplay:playWhenReady)
        return true
    }
    func setVolume(_ value: Double) { castSession?.setDeviceVolume(Float(min(1,max(0,value)))) }
    func unmuteDevice() { castSession?.setDeviceMuted(false) }
    func openControls() { if connected { GCKCastContext.sharedInstance().presentDefaultExpandedMediaControls() } }
    private func requestFields(_ request:GCKRequest,phase:String) -> [String:String] {
        let kind=request == loadRequest ? "load":request == subtitleRequest ? "subtitle":request == commandRequest ? "command":request == intentCorrectionRequest ? "intent":"obsolete"
        return ["phase":phase,"kind":kind,"request":String(request.requestID),"action":request == commandRequest ? commandAction:kind,"generation":String(streamRequests.generation.uuidString.prefix(8))]
    }
    func requestDidComplete(_ request: GCKRequest) {
        PlaybackDiagnostics.record(.load,requestFields(request,phase:"ack"))
        if request == intentCorrectionRequest { intentCorrectionRequest=nil;intentCorrection=nil;return }
        if request == subtitleRequest {
            loadedSubtitle = pendingSubtitle
            if let delay = pendingSubtitleDelay { lastAppliedSubtitleDelay = delay }
            subtitleRequest = nil; pendingSubtitle = nil; pendingSubtitleDelay = nil
            subtitleIssue = nil; message = "Sottotitoli aggiornati sulla TV."; flushQueuedSeek()
            if loadedSubtitle != selectedSubtitle, trackApplyTask == nil, embeddedCaptionTask == nil,
               !loading, !checkingStream, timeline.target == nil, timeline.queuedTarget == nil {
                load(preservePosition:true)
            } else { applySubtitleTiming() }
            return
        }
        if request == commandRequest { finishCommand(true); return }
        if request == loadRequest { standardCaptions.acknowledge();loadAccepted = true; message = "Attendo l’avvio sulla TV…"; loadRequest = nil }
    }
    func request(_ request: GCKRequest, didFailWithError error: GCKError) {
        var fields=requestFields(request,phase:"cast_request");fields["code"]=String(error.code)
        PlaybackDiagnostics.record(.error,fields)
        if request == intentCorrectionRequest { intentCorrectionRequest=nil;intentCorrection=nil;playbackIntent.reset();return }
        if request == subtitleRequest { subtitleRequest = nil; pendingSubtitle = nil; pendingSubtitleDelay = nil; subtitleIssue = "La TV non ha applicato il cambio. Puoi riprovare."; flushQueuedSeek(); return }
        if request == commandRequest { finishCommand(false); return }
        if request == loadRequest { loadPending = false; loading = false; loadTimeout?.cancel(); loadRequest = nil; if advanceAutoplaySource(){return};if recoverPlayback() { return }; message = "Errore Cast \(error.code): il formato non è stato riprodotto dopo l’adattamento automatico."; playbackIssue = message; updateActivity(status: "Apri l’app per riprovare") }
    }
    func request(_ request: GCKRequest, didAbortWith abortReason: GCKRequestAbortReason) {
        var fields=requestFields(request,phase:"cast_abort");fields["code"]=String(abortReason.rawValue)
        PlaybackDiagnostics.record(.command,fields)
        if request == intentCorrectionRequest { intentCorrectionRequest=nil;intentCorrection=nil;playbackIntent.reset();return }
        if request == subtitleRequest { subtitleRequest = nil; pendingSubtitle = nil; pendingSubtitleDelay = nil; message = "Cambio sottotitoli interrotto. Riprova."; flushQueuedSeek(); return }
        if request == commandRequest { finishCommand(false); return }
        if request == loadRequest {
            loadPending = false; loading = false; loadTimeout?.cancel(); loadRequest = nil
            message = "Impossibile verificare l’avvio. Riprova: la posizione è conservata."
            updateActivity(status: "Apri l’app per riprovare")
        }
    }
    private func handleCommand(_ command:String) async -> Bool {
        PlaybackDiagnostics.record(.command,["kind":command,"connected":String(connected),"local":String(localProcessing),"position":PlaybackDiagnostics.number(position)])
        if backgroundServiceStopped {
            if command == "play" || command == "toggle" {playWhenReady=true;load(preservePosition:true);return true}
            if command == "stop" {endPlayback();return true}
            return command == "pause"
        }
        if let target = CastWire.seekTarget(command,current:timeline.queuedTarget ?? lastGoodPosition,duration:duration,step:PlaybackPreferences.seekStep()) {
            seek(to:target); return true
        }
        var action = command
        if ["play","pause","toggle"].contains(command) {
            intentCorrectionRequest?.cancel();intentCorrectionRequest=nil;intentCorrection=nil
            playWhenReady = command == "toggle" ? !playWhenReady : command == "play"
            playbackIntent.request(playWhenReady); controlRequests.invalidate()
            action = playWhenReady ? "play" : "pause"
        }
        if loading || loadPending || checkingStream {
            switch command {
            case "play","pause","toggle": return true
            case "stop": endPlayback(); return true
            default: return false
            }
        }
        let sourceToken = sourceRequests.generation
        let canUseDirect = !localProcessing || ["toggle","play","pause","stop"].contains(command)
        if canUseDirect && (UIApplication.shared.applicationState != .active || !connected) {
            if await directCommand(action) { return true }
        }
        guard sourceRequests.accepts(sourceToken) else { return false }
        if await performActivityCommand(action) { return true }
        guard sourceRequests.accepts(sourceToken) else { return false }
        return canUseDirect ? await directCommand(action) : false
    }
    private func directCommand(_ command:String) async -> Bool {
        let sourceToken = sourceRequests.generation
        let controlToken = controlRequests.generation
        let success = await CastDirectControl.perform(command,offset:streamOffset,originalDuration:localProcessing ? duration : nil) { [weak self] position,duration,playing in
            guard let self, self.sourceRequests.accepts(sourceToken), !self.checkingStream, !self.loadPending else { return }
            if self.timeline.observe(position,ready:true) && self.timeline.queuedTarget == nil { self.position = position; self.lastGoodPosition = position }
            if duration > 0 { self.duration = duration }
            if self.controlRequests.accepts(controlToken), self.playbackIntent.accepts(playing) {
                self.playing = playing; self.playWhenReady = playing
                self.nativeEngine?.setReceiverPaused(!playing)
            }
            self.updateActivity(status:playing ? "In riproduzione" : "In pausa")
        }
        guard sourceRequests.accepts(sourceToken) else { return false }
        if success && command == "stop" { resetPlayback(); hasLoaded = false; playing = false; message = "Riproduzione interrotta." }
        return success
    }
    private func performActivityCommand(_ command: String) async -> Bool {
        let sourceToken = sourceRequests.generation
        if client == nil || !connected { reconnectControls() }
        for _ in 0..<20 {
            if client != nil { break }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        guard sourceRequests.accepts(sourceToken) else { return false }
        if command == "stop" { endPlayback(); return true }
        guard !loadPending, !checkingStream, commandContinuation == nil else { return false }
        guard let client, ownsCurrentMedia else {
            if !connected { message = "Ricollego i controlli alla TV…" }
            return false
        }
        let request: GCKRequest
        switch command {
        case "play": request = client.play()
        case "pause": request = client.pause()
        case "stop": endPlayback(); return true
        case "toggle": request = playWhenReady ? client.play() : client.pause()
        case let value where value == "back" || value == "forward" || value.hasPrefix("seek:"):
            let current = timeline.target ?? lastGoodPosition
            guard current.isFinite, current >= 0 else { return false }
            guard var target = CastWire.seekTarget(command,current:current,duration:duration,step:PlaybackPreferences.seekStep()) else { return false }
            timeline.begin(at:target); position = target; lastGoodPosition = target
            updateActivity(status:"Caricamento")
            if localProcessing {
                if duration > 0 { target = min(target,max(0,duration-1)) }
                startPlayback(requestedPosition:target,autoplay:playWhenReady)
                await streamCheckTask?.value
                guard sourceRequests.accepts(sourceToken) else { return false }
                return loadPending || (ownsCurrentMedia && abs(position-target) < 2)
            }
            let opts = GCKMediaSeekOptions()
            opts.interval = max(0, duration > 0 ? min(target, duration) : target)
            request = client.seek(with: opts)
        default: return false
        }
        return await withCheckedContinuation { continuation in
            commandAction=command;commandGeneration=controlRequests.generation
            commandContinuation = continuation; commandRequest = request; request.delegate = self
            PlaybackDiagnostics.record(.command,requestFields(request,phase:"send"))
            commandTimeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !Task.isCancelled else { return }
                self?.finishCommand(false)
            }
        }
    }
    private func finishCommand(_ success: Bool) {
        guard let continuation = commandContinuation else { return }
        if !success,let generation=commandGeneration,controlRequests.accepts(generation) { playbackIntent.reset();intentCorrection=nil }
        commandGeneration=nil;commandAction="none"
        commandContinuation = nil; commandRequest = nil
        commandTimeout?.cancel(); commandTimeout = nil
        continuation.resume(returning: success)
        if success { updateStatus() }
    }
    private func resetPlayback(preserveAutoplay:Bool=false) {
        backgroundServiceStopped=false
        syncStremioProgress(force:true)
        if !preserveAutoplay{episodeAutoplay=nil}
        work?.cancel();work=nil;busy=false
        episodeRequest=UUID();episodeBusy=false
        sourceRevision = UUID()
        trackChangePending = false
        stopCaptionDelivery()
        independentCaptions.clearSource();loadedAudioKey="";loadedSourceInput=nil
        processingDetail = "Automatico"
        sourceRequests.invalidate(); streamRequests.invalidate(); controlRequests.invalidate(); playbackIntent.reset()
        recovery.reset();progress.reset();lastConfirmedPosition=nil;confirmedChoice=nil;intentCorrection=nil
        transferCheckpoint=nil
        intentCorrectionRequest?.cancel();intentCorrectionRequest=nil
        wantsPlayback = false; reconnectTask?.cancel(); reconnectTask = nil
        trackApplyTask?.cancel(); trackApplyTask = nil; lockScreen.clear()
        embeddedCaptionTask?.cancel(); embeddedCaptionTask = nil
        seekDispatchTask?.cancel(); seekDispatchTask = nil
        streamCheckTask?.cancel(); streamCheckTask = nil; checkingStream = false; playbackIssue = nil
        subtitleStyleWork?.cancel()
        directCaptureTask?.cancel(); directCaptureKey = nil; CastDirectControl.clear()
        capturePosition()
        stopLocalProcessing(); forceLocalPlayback = false; localFallbackLevel = 0
        captionCache.removeAll(); captionFailures.removeAll()
        if let positionKey, lastGoodPosition > 0 { UserDefaults.standard.set(lastGoodPosition, forKey: positionKey) }
        positionKey = nil
        finishCommand(false)
        loadTimeout?.cancel(); loadPending = false; loading = false; loadAccepted = false; loadRequest = nil; bufferingSince = nil
        expectedContentID = nil; loadedSignature = nil; loadedSubtitle = nil; loadedStreamGeneration = nil;loadedMediaSessionID=nil
        subtitleRequest = nil; pendingSubtitle = nil
        UserDefaults.standard.removeObject(forKey: "cast.session.content")
        UserDefaults.standard.removeObject(forKey: "cast.session.positionKey")
        UserDefaults.standard.removeObject(forKey: "cast.session.duration")
        lastGoodPosition = 0; position = 0; duration = 0
        timeline.reset(); playWhenReady = true; playing = false; transportRetries = 0
    }
    private func updateActivity(status: String) {
        if wantsPlayback && (hasLoaded || loadPending || localProcessing) {
            lockScreen.update(title:displayTitle,device:deviceName,position:lastGoodPosition,duration:duration,playing:playing,loading:loading || timeline.target != nil || timeline.queuedTarget != nil,local:localProcessing)
        }
    }
}



