import Foundation
import GoogleCast
import SwiftUI
import ActivityKit
import CryptoKit
import UIKit

@MainActor final class CastController: NSObject, ObservableObject, GCKRequestDelegate, GCKSessionManagerListener, GCKRemoteMediaClientListener {
    @Published var showSetup = false
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
    private var sourceResume: (content:PlaybackContent,position:Double,duration:Double,playing:Bool)?
    private var lastPositionSave = Date.distantPast
    private var positionKey: String?
    private var bufferingSince: Date?
    private var expectedContentID: String?
    private var loadedSignature: String?
    private var loadedStreamGeneration: UUID?
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
    }
    private var nativeSelection: NativeSelection?
    private var streamOffset: Double { nativeEngine?.offset ?? 0 }
    private var forceLocalPlayback = false
    private var localFallbackLevel = 0
    private var commandRequest: GCKRequest?
    private var commandContinuation: CheckedContinuation<Bool, Never>?
    private var commandTimeout: Task<Void, Never>?
    private let lockScreen = LockScreenPlayback()
    private var lastDevice: GCKDevice?
    private var reconnectTask: Task<Void,Never>?
    private var trackApplyTask: Task<Void,Never>?
    private var seekDispatchTask: Task<Void,Never>?
    private var wantsPlayback = false
    private var lastDiagnosticSnapshot = Date.distantPast
    var displayTitle: String { MediaDisplayTitle.clean(selectedSource?.filename ?? selectedSource?.descriptionText.components(separatedBy:.newlines).first ?? "Video da Stremio") }
    var deviceName: String { castSession?.device.friendlyName ?? lastDevice?.friendlyName ?? "Chromecast" }

    override init() {
        super.init()
        PlaybackDiagnostics.record(.app,["phase":"launch"])
        // Keep only the system media card, including after an upgrade from 0.6.0.
        Task {
            for old in Activity<CastActivityAttributes>.activities {
                if #available(iOS 16.2, *) { await old.end(nil,dismissalPolicy:.immediate) }
                else { await old.end(dismissalPolicy:.immediate) }
            }
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
        if let positionKey { UserDefaults.standard.set(value, forKey: positionKey) }
    }
    func savePlaybackPosition() { capturePosition(); PlaybackDiagnostics.record(.app,["phase":"background","position":PlaybackDiagnostics.number(lastGoodPosition)]); PlaybackDiagnostics.shared.flush() }
    func copyDiagnostics() {
        PlaybackDiagnostics.record(.snapshot,["phase":"copy","connected":String(connected),"local":String(localProcessing),"position":PlaybackDiagnostics.number(position),"duration":PlaybackDiagnostics.number(duration),"pending":String(loading || loadPending || checkingStream)])
        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic:PlaybackDiagnostics.shared.report()]],options:[.localOnly:true,.expirationDate:Date().addingTimeInterval(3600)])
    }
    func refreshConnection() {
        let manager = GCKCastContext.sharedInstance().sessionManager
        if !listenersAttached { manager.add(self); listenersAttached = true }
        if observedClient !== client {
            observedClient?.remove(self); observedClient = client; client?.add(self)
        }
        client?.requestStatus()
        if let device = castSession?.device { lastDevice = device }
        updateStatus()
        if connected && wantsPlayback && prepared != nil && !busy && !loading && !hasLoaded && !loadPending { load() }
    }
    func sessionManager(_ manager: GCKSessionManager, didStart session: GCKSession) { refreshConnection() }
    func sessionManager(_ manager: GCKSessionManager, didResumeSession session: GCKSession) { refreshConnection() }
    func sessionManager(_ manager:GCKSessionManager,didSuspend session:GCKSession,withReason reason:GCKConnectionSuspendReason) {
        PlaybackDiagnostics.record(.cast,["phase":"suspend","code":String(reason.rawValue)])
        guard wantsPlayback else { return }
        connected = false; message = "Ricollego i controlli alla TV…"
        reconnectControls()
    }
    func sessionManager(_ manager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) {
        PlaybackDiagnostics.record(.cast,["phase":"end","result":error == nil ? "normal" : "error"])
        if error != nil && wantsPlayback && (hasLoaded || localProcessing) {
            connected = false; finishCommand(false)
            message = "Ricollego i controlli alla TV…"
            reconnectControls(); return
        }
        wantsPlayback = false; reconnectTask?.cancel(); reconnectTask = nil; lockScreen.clear()
        streamCheckTask?.cancel(); checkingStream = false; loading = false
        capturePosition(); stopLocalProcessing(); connected = false; playing = false; finishCommand(false)
    }
    func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus?) { updateStatus() }
    private func updateStatus() {
        guard UIApplication.shared.applicationState == .active || localProcessing || lockScreen.active else { return }
        connected = GCKCastContext.sharedInstance().sessionManager.hasConnectedCastSession()
        PlaybackDiagnostics.shared.changed("connection",event:.cast,["connected":String(connected)])
        guard let session = castSession, let client = session.remoteMediaClient, connected else {
            if wantsPlayback { reconnectControls(); updateActivity(status:"Ricollego i controlli…") }
            return
        }
        reconnectTask?.cancel(); reconnectTask = nil
        if !userAdjustingVolume { volume = Double(session.currentDeviceVolume) }
        deviceMuted = session.currentDeviceMuted
        if let status = client.mediaStatus {
            PlaybackDiagnostics.shared.changed("receiver",event:.cast,["status":String(status.playerState.rawValue),"idle":String(status.idleReason.rawValue),"owned":String(ownsCurrentMedia),"pending":String(loadPending),"local":String(localProcessing)])
            if Date().timeIntervalSince(lastDiagnosticSnapshot) >= 15 {
                lastDiagnosticSnapshot = Date()
                PlaybackDiagnostics.record(.snapshot,["position":PlaybackDiagnostics.number(position),"offset":PlaybackDiagnostics.number(streamOffset),"duration":PlaybackDiagnostics.number(duration),"target":PlaybackDiagnostics.number(timeline.target ?? -1)])
            }
            // This status still belongs to the stream being replaced. Keep the
            // requested position, autoplay intent and any new preparation intact.
            if checkingStream { return }
            if let loadedStreamGeneration, !streamRequests.accepts(loadedStreamGeneration) { return }
            // Receivers can reuse mediaSessionID across LOAD calls. Match the
            // expected content instead; never copy another video's position.
            guard ownsCurrentMedia else {
                if hasLoaded && !loadPending && !checkingStream { stopLocalProcessing(); hasLoaded = false; wantsPlayback = false; lockScreen.clear(); message = "La TV sta riproducendo un altro contenuto." }
                if !loadPending && timeline.target == nil { playing = false }
                return
            }
            if loadPending && !loadAccepted { return }
            if loadPending && status.playerState == .idle && status.idleReason != .error { return }
            if (status.playerState == .playing || status.playerState == .paused) && !playbackIntent.accepts(status.playerState == .playing) {
                _ = playWhenReady ? client.play() : client.pause()
                return
            }
            playing = status.playerState == .playing
            if (status.playerState == .playing && (!loadPending || playWhenReady)) || (status.playerState == .paused && (!loadPending || !playWhenReady)) { nativeEngine?.setReceiverPaused(status.playerState == .paused) }
            if loadPending && loadAccepted && playWhenReady && status.playerState == .paused { _ = client.play() }
            if loadPending && loadAccepted && !playWhenReady && status.playerState == .playing { _ = client.pause() }
            if status.playerState != .buffering { bufferingSince = nil }
            let observed = client.approximateStreamPosition() + streamOffset
            let ready = (status.playerState == .playing && (!loadPending || playWhenReady)) || (status.playerState == .paused && (!loadPending || !playWhenReady))
            let confirmed = timeline.observe(observed,ready:ready && (!loadPending || loadAccepted))
            if confirmed && timeline.queuedTarget == nil {
                lastGoodPosition = observed
                if let positionKey, observed > 0, Date().timeIntervalSince(lastPositionSave) >= 10 {
                    UserDefaults.standard.set(observed, forKey: positionKey); lastPositionSave = Date()
                }
                if !userSeeking { position = observed }
            }
            let reported = status.mediaInformation?.streamDuration ?? 0
            let known = prepared?.duration ?? UserDefaults.standard.double(forKey:"cast.session.duration")
            let d = localProcessing ? (known > 0 ? known : (reported > 0 ? reported + streamOffset : duration)) : (reported.isFinite && reported > 0 ? reported : (known > 0 ? known : duration))
            if d.isFinite && d > 0 { duration = d }
            let currentLoad = !loadPending || loadAccepted
            if ready && confirmed && currentLoad {
                if loadPending || !hasLoaded { playbackIssue = nil }
                hasLoaded = true; wantsPlayback = true
                playWhenReady = playing
                if loadPending { loadPending = false; loading = false; loadTimeout?.cancel(); hasLoaded = true }
                if !checkingStream { message = playing ? "In riproduzione sulla TV." : "In pausa sulla TV." }
                updateActivity(status: playing ? "In riproduzione" : "In pausa")
                prepareDirectControls()
                flushQueuedSeek()
            } else if status.playerState == .buffering {
                if bufferingSince == nil { bufferingSince = Date() }
                let stalled = Date().timeIntervalSince(bufferingSince!) >= 45
                message = stalled ? "Buffering prolungato. Riprova dal punto conservato o cambia sorgente." : "Caricamento sulla TV…"
                updateActivity(status: stalled ? "Buffering: apri l’app per riprovare" : "Caricamento")
            } else if status.playerState == .idle && currentLoad && status.idleReason == .error {
                loadPending = false; loading = false; loadTimeout?.cancel(); loadRequest = nil
                if recoverPlayback() { return }
                message = "La riproduzione si è interrotta. Riprova: la posizione è conservata."
                updateActivity(status: "Errore: apri l’app per riprovare")
            } else if status.playerState == .idle && currentLoad && status.idleReason == .finished {
                wantsPlayback = false; lockScreen.clear()
                loadPending = false; loading = false; loadTimeout?.cancel()
                message = "Riproduzione terminata."
                if let positionKey { UserDefaults.standard.set(0,forKey:positionKey) }
                sourceResume = nil
                hasLoaded = false; lastGoodPosition = duration
                stopLocalProcessing()
                updateActivity(status: "Riproduzione terminata")
                lastGoodPosition = 0
            } else if status.playerState == .idle && currentLoad && status.idleReason == .cancelled {
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
        work?.cancel()
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
    func changeSource() {
        PlaybackDiagnostics.record(.source,["phase":"chooser","position":PlaybackDiagnostics.number(position)])
        captureSourceResume()
        resetPlayback()
        work?.cancel(); work = nil; busy = false; selectedSource = nil; prepared = nil; hasLoaded = false
        message = "Scegli una sorgente."
    }
    func choose(_ source: AddonStream) {
        if selectedSource != nil { captureSourceResume() }
        resetPlayback()
        wantsPlayback = true
        work?.cancel(); subtitleFile = nil; embeddedSubtitleURL = nil; selectedSource = source; prepared = nil; originalURL = nil; hasLoaded = false; lastGoodPosition = 0
        guard let handoff else { message = "Riapri la sorgente da Stremio."; return }
        let identity = handoff.provider + "|" + source.identity
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let content = PlaybackContent(type:handoff.type,id:handoff.id)
        let legacyKey = "cast.position." + digest
        positionKey = content.positionKey
        let stored = UserDefaults.standard.object(forKey:content.positionKey) != nil ? UserDefaults.standard.double(forKey:content.positionKey) : UserDefaults.standard.double(forKey:legacyKey)
        let resume = sourceResume?.content == content ? sourceResume : nil
        lastGoodPosition = max(0,resume?.position ?? stored)
        duration = resume?.duration ?? 0
        playWhenReady = resume?.playing ?? true
        UserDefaults.standard.set(lastGoodPosition,forKey:content.positionKey)
        position = lastGoodPosition
        let sourceToken = sourceRequests.generation
        PlaybackDiagnostics.record(.source,["phase":"choose","generation":String(sourceToken.uuidString.prefix(8)),"position":PlaybackDiagnostics.number(lastGoodPosition)])
        busy = true; message = "Leggo audio e sottotitoli del file…"
        work = Task {
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
                prepared = result; selectedAudio = PlaybackPreferences.audio(result.audio,fallback:result.defaultAudioKey)
                PlaybackDiagnostics.record(.metadata,["codec":result.video?.codec ?? "unknown","width":String(result.video?.width ?? 0),"height":String(result.video?.height ?? 0),"fps":PlaybackDiagnostics.number(result.video?.frameRate ?? 0),"duration":PlaybackDiagnostics.number(result.duration),"tracks":String(result.audio.count),"subtitle":String(result.subtitles.count)])
                selectedQuality = result.availableQualities.contains(.high) ? .high : (result.availableQualities.first ?? .high)
                compatibilityMode = false
                selectedSubtitle = PlaybackPreferences.subtitle(result.subtitles,external:externalSubtitleURL != nil,handoff:handoff.subtitleLanguage)
                busy = false
                if result.duration > 0 {
                    duration = result.duration
                    lastGoodPosition = min(lastGoodPosition,max(0,duration-1))
                    position = lastGoodPosition
                }
                playbackIssue = nil
                message = "Video pronto. Collega la TV per iniziare."
                if connected && wantsPlayback { load() }
            } catch is CancellationError { } catch {
                if Task.isCancelled || !sourceRequests.accepts(sourceToken) { return }
                PlaybackDiagnostics.record(.error,["phase":"resolve","kind":String(describing:type(of:error)),"code":String((error as NSError).code)])
                busy = false
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
        wantsPlayback = true
        transportRetries = 0
        startPlayback(requestedPosition:nil,autoplay:playWhenReady)
    }
    private func startPlayback(requestedPosition: Double?, autoplay: Bool) {
        guard let prepared, client != nil else { message = "Collega prima il Chromecast e scegli un file."; return }
        guard !loading, !loadPending, subtitleRequest == nil else { return }
        capturePosition()
        let requested = timeline.consumeQueued() ?? requestedPosition
        let audio = selectedAudio, subtitle = selectedSubtitle
        PlaybackDiagnostics.record(.prepare,["phase":"request","audio":audio,"subtitle":subtitle,"position":PlaybackDiagnostics.number(requested ?? lastGoodPosition)])
        let burnedSubtitle = subtitle.hasPrefix("vlc_") ? subtitle : "none"
        let needsLocal = forceLocalPlayback || !prepared.directCompatible || audio != prepared.defaultAudioKey || burnedSubtitle != "none"
        if !needsLocal {
            let target = requested ?? timeline.target ?? lastGoodPosition
            timeline.begin(at:target); position = target; lastGoodPosition = target
            stopLocalProcessing(); compatibilityMode = false; processingDetail = "Video originale · \(prepared.video?.label ?? prepared.videoDescription)"
            sendLoad(preservePosition:true,autoplay:playWhenReady)
            return
        }
        let appearance = burnedSubtitle == "none" ? SubtitleAppearance() : SubtitleAppearance.load()
        let selection = NativeSelection(input:prepared.directURL,audio:audio,subtitle:burnedSubtitle,appearance:appearance,external:externalSubtitleURL,extracted:embeddedSubtitleURL)
        // Burning a subtitle is not a permanent reason to re-encode the movie.
        // Re-evaluate the original-video route when the selected tracks change.
        if selection != nativeSelection { localFallbackLevel = 0 }
        let requiredCaption = subtitle == "external" ? 1 : subtitle == "embedded" ? 2 : nil
        if requested == nil, hasLoaded, ownsCurrentMedia, selection == nativeSelection, let engine = nativeEngine, engine.running, let url = engine.streamURL, requiredCaption == nil || engine.captionURLs[requiredCaption!] != nil {
            sendLoad(preservePosition:false,urlOverride:url,contentTypeOverride:engine.contentType,autoplay:playWhenReady)
            return
        }
        guard let host = castSession?.device.ipAddress, CastWire.localIPv4(host) else { playbackIssue = EmbeddedMediaError.address.localizedDescription; return }
        let start = requested ?? timeline.target ?? lastGoodPosition
        let sourceToken = sourceRequests.generation
        streamRequests.invalidate()
        let streamToken = streamRequests.generation
        timeline.begin(at:start); position = start; lastGoodPosition = start
        // Freeze the old stream while replacing its audio/subtitle pipeline.
        // Its late statuses must not move the new original-media timeline.
        if hasLoaded && ownsCurrentMedia {
            nativeEngine?.setReceiverPaused(true)
            _ = client?.pause()
        }
        checkingStream = true; loading = true; playbackIssue = nil
        processingDetail = "Preparazione del flusso…"
        message = "Preparo il flusso sull’iPhone…"
        updateActivity(status:"Caricamento")
        streamCheckTask = Task { [weak self] in
            let background = UIApplication.shared.beginBackgroundTask(withName:"Prepare Cast stream")
            defer { if background != .invalid { UIApplication.shared.endBackgroundTask(background) } }
            do {
                guard let self else { return }
                var captions: [Int:String] = [:]
                for (id,url) in [(1,selection.external),(2,selection.extracted)] {
                    if id == requiredCaption, let url, let text = await self.readCaption(url) { captions[id] = text }
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
                let modes = EmbeddedMediaEngine.modes(requiresVideo:convertVideo,fallbackLevel:self.localFallbackLevel,video:prepared.video,burn:burnedSubtitle != "none")
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
                        let url = try await engine.start(input:prepared.directURL,deviceIP:host,start:start,videoMode:mode,audioID:audioID,subtitleID:subtitleID,style:appearance,copyAudio:copyAudio,repairAudio:repairAudio,audioIndex:audioIndex,subtitleIndex:subtitleIndex,captions:captions,video:prepared.video)
                        try self.validateStream(source:sourceToken,stream:streamToken)
                        guard self.prepared?.directURL == prepared.directURL, self.selectedAudio == audio, self.selectedSubtitle == subtitle,
                              burnedSubtitle == "none" || SubtitleAppearance.load() == appearance else {
                            engine.stop()
                            self.checkingStream = false; self.loading = false
                            self.startPlayback(requestedPosition:start,autoplay:self.playWhenReady)
                            return
                        }
                        self.nativeEngine?.stop()
                        self.nativeEngine = engine; self.nativeSelection = selection
                        PlaybackDiagnostics.record(.prepare,["phase":"ready","mode":String(describing:mode)])
                        engine.refreshBackground()
                        self.localProcessing = true; self.compatibilityMode = true; CastActivityCommands.usesLocalStream = true
                        self.localFallbackLevel = mode == .copy ? 0 : mode == .softwareVP8 ? 2 : 1
                        let rate = prepared.video.map { format in
                            format.conversionFrameRate.map { "\(Int($0)) fps" } ?? format.frameRateLabel
                        } ?? "fps originali"
                        let format = prepared.video
                        let scale = format.map{ min(1,min(1920 / Double(max(1,$0.width)),1080 / Double(max(1,$0.height)))) } ?? 1
                        let dimensions = format.map{ "\(Int(Double($0.width)*scale)/2*2)×\(Int(Double($0.height)*scale)/2*2)" } ?? "dimensioni adattate"
                        self.processingDetail = mode == .copy ? "Video originale · \(prepared.video?.label ?? prepared.videoDescription) · \(copyAudio ? "audio originale" : "audio AAC stereo")" : "Video convertito \(mode == .softwareVP8 ? "VP8" : "H.264") · \(dimensions) · \(rate)"
                        engine.onFailure = { [weak self, weak engine] in
                            guard let self, let engine, self.nativeEngine === engine, self.sourceRequests.accepts(sourceToken), self.streamRequests.accepts(streamToken), !self.checkingStream, !self.loadPending else { return }
                            if !self.recoverPlayback() { self.playbackIssue = "Il motore integrato ha interrotto la conversione. La posizione è conservata." }
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
                self.hasLoaded = false
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
            let signature = url.absoluteString + "|" + (externalSubtitleURL?.absoluteString ?? "") + "|" + (embeddedSubtitleURL?.absoluteString ?? "")
            // Text tracks are attached even when disabled, so selecting one
            // later does not need to reload the movie or recreate its buffer.
            if hasLoaded && ownsCurrentMedia && loadedSignature == signature && loadedSubtitle != selectedSubtitle {
                let ids: [NSNumber] = selectedSubtitle == "external" ? [1] : selectedSubtitle == "embedded" ? [2] : []
                if selectedSubtitle == "external" && externalSubtitleURL == nil { return }
                let request = client.setActiveTrackIDs(ids)
                subtitleRequest = request; request.delegate = self
                pendingSubtitle = selectedSubtitle
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
            let load = GCKMediaLoadRequestDataBuilder()
            load.autoplay = NSNumber(value:autoplay)
            var textTracks: [GCKMediaTrack] = []
            let externalTrack = urlOverride == nil ? externalSubtitleURL : nativeEngine?.captionURLs[1]
            let extractedTrack = urlOverride == nil ? embeddedSubtitleURL : nativeEngine?.captionURLs[2]
            if let external = externalTrack {
                if let track = GCKMediaTrack(identifier:1, contentIdentifier:external.absoluteString, contentType:"text/vtt", type:.text, textSubtype:.subtitles, name:externalSubtitleLabel, languageCode:(handoff?.subtitleLanguage == "ita" ? "it" : "en"), customData:nil) {
                    textTracks.append(track)
                    load.activeTrackIDs = selectedSubtitle == "external" ? [1] : []
                }
            }
            if let embedded = extractedTrack, let track = GCKMediaTrack(identifier:2, contentIdentifier:embedded.absoluteString, contentType:"text/vtt",type:.text,textSubtype:.subtitles,name:externalSubtitleLabel + " · dal file",languageCode:(handoff?.subtitleLanguage == "ita" ? "it" : "en"),customData:nil) { textTracks.append(track) }
            info.mediaTracks = textTracks
            if selectedSubtitle == "embedded" { load.activeTrackIDs = [2] }
            load.mediaInformation = info.build()
            if urlOverride != nil { load.startTime = 0 }
            else if preservePosition || lastGoodPosition > 0 { load.startTime = max(0, lastGoodPosition) }
            loadPending = true
            playbackIssue = nil
            loading = true
            hasLoaded = false
            loadAccepted = false
            expectedContentID = url.absoluteString
            loadedSignature = signature
            loadedStreamGeneration = streamRequests.generation
            loadedSubtitle = selectedSubtitle
            UserDefaults.standard.set(contentDigest(url.absoluteString), forKey: "cast.session.content")
            UserDefaults.standard.set(prepared.duration, forKey:"cast.session.duration")
            if let positionKey { UserDefaults.standard.set(positionKey, forKey: "cast.session.positionKey") }
            let request = client.loadMedia(with:load.build())
            loadRequest = request; request.delegate = self
            message = "Invio il video al Chromecast…"
            updateActivity(status: "Caricamento")
            loadTimeout?.cancel()
            loadTimeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled, let self, self.loadPending else { return }
                self.loadPending = false; self.loading = false; self.loadRequest = nil
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
        } catch { if !Task.isCancelled { captionFailures[url] = Date() }; return nil }
    }
    var externalSubtitleLabel: String { handoff?.subtitleLanguage == "ita" ? "Italiano" : "English" }
    var externalSubtitleURL: URL? {
        guard handoff?.subtitleLanguage != "off" else { return nil }
        let tracks = selectedSource?.subtitles ?? []
        let languages = handoff?.subtitleLanguage == "ita" ? ["it", "ita", "italian"] : ["en", "eng", "english"]
        for track in tracks where languages.contains((track.lang ?? "").lowercased()) {
            if let url = URL(string:track.url), url.scheme == "https", url.user == nil, url.password == nil, url.pathExtension.lowercased() == "vtt" { return url }
        }
        if handoff?.subtitleLanguage != "ita", let url = handoff?.externalSubtitleURL,
           url.scheme == "https", url.host == "stremio-chromecast-bridge.donotpeek.chatgpt.site",
           url.path.hasPrefix("/api/bridge/subtitle/"), url.pathExtension == "vtt" { return url }
        return nil
    }
    func togglePlayback() { Task { _ = await handleCommand("toggle") } }
    func tracksChanged(audio:Bool) {
        PlaybackDiagnostics.record(.tracks,["kind":audio ? "audio" : "subtitle","audio":selectedAudio,"subtitle":selectedSubtitle,"position":PlaybackDiagnostics.number(position)])
        guard let prepared, !busy else { return }
        if audio { PlaybackPreferences.remember(audio:prepared.audio.first(where:{$0.key == selectedAudio}),subtitle:nil) }
        else {
            let language = selectedSubtitle == "none" ? "none" : ["external","embedded"].contains(selectedSubtitle) ? handoff?.subtitleLanguage : prepared.subtitles.first(where:{$0.key == selectedSubtitle})?.language
            PlaybackPreferences.remember(audio:nil,subtitle:language)
        }
        trackApplyTask?.cancel()
        trackApplyTask = Task {
            try? await Task.sleep(nanoseconds:400_000_000)
            guard !Task.isCancelled, hasLoaded, !loading else { return }
            load(preservePosition:true)
        }
    }
    func applySubtitleAppearance() {
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
              !loading, !loadPending, !checkingStream, commandContinuation == nil, hasLoaded,
              connected || !localProcessing else { return }
        let sourceToken = sourceRequests.generation
        seekDispatchTask = Task {
            try? await Task.sleep(nanoseconds:150_000_000)
            guard !Task.isCancelled, sourceRequests.accepts(sourceToken) else { return }
            guard !loading, !loadPending, !checkingStream, commandContinuation == nil,
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
        if ownsCurrentMedia { client?.stop() }
        resetPlayback(); sourceResume = nil; hasLoaded = false; playing = false; message = "Riproduzione interrotta."
    }
    private func stopLocalProcessing() {
        nativeEngine?.stop(); nativeEngine = nil; nativeSelection = nil
        localProcessing = false; CastActivityCommands.usesLocalStream = false
    }
    @discardableResult private func recoverPlayback(allowVideoConversion:Bool = true) -> Bool {
        PlaybackDiagnostics.record(.recovery,["attempt":String(transportRetries),"position":PlaybackDiagnostics.number(lastGoodPosition)])
        guard !checkingStream, let prepared, connected else { return false }
        if !allowVideoConversion {
            guard transportRetries < 1 else { return false }
            transportRetries += 1
            if !localProcessing { forceLocalPlayback = true }
        } else if localProcessing {
            guard localFallbackLevel < 2 else { return false }
            localFallbackLevel += 1
        } else { guard !forceLocalPlayback else { return false }; forceLocalPlayback = true }
        loadPending = false; loading = false; loadTimeout?.cancel(); loadRequest = nil; hasLoaded = false
        lastGoodPosition = timeline.consumeQueued() ?? timeline.target ?? lastGoodPosition
        message = "Adatto automaticamente il formato per la TV…"
        startPlayback(requestedPosition:lastGoodPosition,autoplay:playWhenReady)
        return prepared.directURL == self.prepared?.directURL
    }
    func setVolume(_ value: Double) { castSession?.setDeviceVolume(Float(min(1,max(0,value)))) }
    func unmuteDevice() { castSession?.setDeviceMuted(false) }
    func openControls() { if connected { GCKCastContext.sharedInstance().presentDefaultExpandedMediaControls() } }
    func requestDidComplete(_ request: GCKRequest) {
        PlaybackDiagnostics.record(.load,["phase":"ack","kind":request == loadRequest ? "load" : request == subtitleRequest ? "subtitle" : "command"])
        if request == subtitleRequest { loadedSubtitle = pendingSubtitle; subtitleRequest = nil; pendingSubtitle = nil; message = "Sottotitoli aggiornati sulla TV."; return }
        if request == commandRequest { finishCommand(true); return }
        if request == loadRequest { loadAccepted = true; message = "Attendo l’avvio sulla TV…"; loadRequest = nil }
    }
    func request(_ request: GCKRequest, didFailWithError error: GCKError) {
        PlaybackDiagnostics.record(.error,["phase":"cast_request","code":String(error.code),"kind":request == loadRequest ? "load" : request == subtitleRequest ? "subtitle" : "command"])
        if request == subtitleRequest { subtitleRequest = nil; pendingSubtitle = nil; message = "Cambio sottotitoli non riuscito. Riprova."; return }
        if request == commandRequest { finishCommand(false); return }
        if request == loadRequest { loadPending = false; loading = false; loadTimeout?.cancel(); loadRequest = nil; if recoverPlayback() { return }; message = "Errore Cast \(error.code): il formato non è stato riprodotto dopo l’adattamento automatico."; playbackIssue = message; updateActivity(status: "Apri l’app per riprovare") }
    }
    func request(_ request: GCKRequest, didAbortWith abortReason: GCKRequestAbortReason) {
        PlaybackDiagnostics.record(.error,["phase":"cast_abort","code":String(abortReason.rawValue)])
        if request == subtitleRequest { subtitleRequest = nil; pendingSubtitle = nil; message = "Cambio sottotitoli interrotto. Riprova."; return }
        if request == commandRequest { finishCommand(false); return }
        if request == loadRequest {
            loadPending = false; loading = false; loadTimeout?.cancel(); loadRequest = nil
            message = "Impossibile verificare l’avvio. Riprova: la posizione è conservata."
            updateActivity(status: "Apri l’app per riprovare")
        }
    }
    private func handleCommand(_ command:String) async -> Bool {
        PlaybackDiagnostics.record(.command,["kind":command,"connected":String(connected),"local":String(localProcessing),"position":PlaybackDiagnostics.number(position)])
        if let target = CastWire.seekTarget(command,current:timeline.queuedTarget ?? lastGoodPosition,duration:duration) {
            seek(to:target); return true
        }
        var action = command
        if ["play","pause","toggle"].contains(command) {
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
            guard var target = CastWire.seekTarget(command,current:current,duration:duration) else { return false }
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
            commandContinuation = continuation; commandRequest = request; request.delegate = self
            commandTimeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !Task.isCancelled else { return }
                self?.finishCommand(false)
            }
        }
    }
    private func finishCommand(_ success: Bool) {
        guard let continuation = commandContinuation else { return }
        commandContinuation = nil; commandRequest = nil
        commandTimeout?.cancel(); commandTimeout = nil
        continuation.resume(returning: success)
        if success { updateStatus() }
    }
    private func resetPlayback() {
        processingDetail = "Automatico"
        sourceRequests.invalidate(); streamRequests.invalidate(); controlRequests.invalidate(); playbackIntent.reset()
        wantsPlayback = false; reconnectTask?.cancel(); reconnectTask = nil
        trackApplyTask?.cancel(); trackApplyTask = nil; lockScreen.clear()
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
        expectedContentID = nil; loadedSignature = nil; loadedSubtitle = nil; loadedStreamGeneration = nil
        subtitleRequest = nil; pendingSubtitle = nil
        UserDefaults.standard.removeObject(forKey: "cast.session.content")
        UserDefaults.standard.removeObject(forKey: "cast.session.positionKey")
        lastGoodPosition = 0; position = 0; duration = 0
        timeline.reset(); playWhenReady = true; playing = false; transportRetries = 0
    }
    private func updateActivity(status: String) {
        if wantsPlayback && (hasLoaded || loadPending || localProcessing) {
            lockScreen.update(title:displayTitle,device:deviceName,position:lastGoodPosition,duration:duration,playing:playing,loading:loading || timeline.target != nil || timeline.queuedTarget != nil,local:localProcessing)
        }
    }
}
