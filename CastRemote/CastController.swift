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
    private var activity: Activity<CastActivityAttributes>?
    private var lastActivityState = ""
    private var lastActivityUpdate = Date.distantPast
    private var lastPositionSave = Date.distantPast
    private var positionKey: String?
    private var bufferingSince: Date?
    private var expectedContentID: String?
    private var loadedSignature: String?
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
    private var wantsPlayback = false
    var displayTitle: String { MediaDisplayTitle.clean(selectedSource?.filename ?? selectedSource?.descriptionText.components(separatedBy:.newlines).first ?? "Video da Stremio") }
    var deviceName: String { castSession?.device.friendlyName ?? lastDevice?.friendlyName ?? "Chromecast" }

    override init() {
        super.init()
        activity = Activity<CastActivityAttributes>.activities.first
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
        guard ownsCurrentMedia, !loadPending, let client,
              let state = client.mediaStatus?.playerState, state == .playing || state == .paused || state == .buffering else { return }
        let value = client.approximateStreamPosition() + streamOffset
        guard value.isFinite, value >= 0, state != .buffering || value > 0 else { return }
        lastGoodPosition = value
        if let positionKey { UserDefaults.standard.set(value, forKey: positionKey) }
    }
    func savePlaybackPosition() { capturePosition() }
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
        guard wantsPlayback else { return }
        connected = false; message = "Ricollego i controlli alla TV…"
        reconnectControls()
    }
    func sessionManager(_ manager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) {
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
        guard let session = castSession, let client = session.remoteMediaClient, connected else {
            if wantsPlayback { reconnectControls(); updateActivity(status:"Ricollego i controlli…") }
            return
        }
        reconnectTask?.cancel(); reconnectTask = nil
        if !userAdjustingVolume { volume = Double(session.currentDeviceVolume) }
        deviceMuted = session.currentDeviceMuted
        if let status = client.mediaStatus {
            // Receivers can reuse mediaSessionID across LOAD calls. Match the
            // expected content instead; never copy another video's position.
            guard ownsCurrentMedia else {
                if hasLoaded && !loadPending && !checkingStream { stopLocalProcessing(); hasLoaded = false; wantsPlayback = false; lockScreen.clear(); message = "La TV sta riproducendo un altro contenuto." }
                playing = false; return
            }
            if checkingStream && status.playerState == .idle {
                if status.idleReason == .cancelled { streamCheckTask?.cancel(); checkingStream = false; loading = false; stopLocalProcessing(); hasLoaded = false }
                return
            }
            if loadPending && !loadAccepted { return }
            playing = status.playerState == .playing
            if status.playerState == .paused || status.playerState == .playing { nativeEngine?.setReceiverPaused(status.playerState == .paused) }
            if status.playerState != .buffering { bufferingSince = nil }
            let observed = client.approximateStreamPosition() + streamOffset
            if !loadPending && observed.isFinite && observed >= 0 && (status.playerState == .playing || status.playerState == .paused) {
                lastGoodPosition = observed
                if let positionKey, observed > 0, Date().timeIntervalSince(lastPositionSave) >= 10 {
                    UserDefaults.standard.set(observed, forKey: positionKey); lastPositionSave = Date()
                }
                if !userSeeking { position = observed }
            }
            let reported = status.mediaInformation?.streamDuration ?? 0
            let known = prepared?.duration ?? UserDefaults.standard.double(forKey:"cast.session.duration")
            let d = localProcessing ? known : (reported.isFinite && reported > 0 ? reported : known)
            duration = d.isFinite && d > 0 ? d : 0
            let currentLoad = !loadPending || loadAccepted
            if (status.playerState == .playing || status.playerState == .paused) && currentLoad {
                hasLoaded = true; wantsPlayback = true
                if loadPending { loadPending = false; loading = false; loadTimeout?.cancel(); hasLoaded = true }
                if !checkingStream { message = playing ? "In riproduzione sulla TV." : "In pausa sulla TV." }
                updateActivity(status: playing ? "In riproduzione" : "In pausa")
                prepareDirectControls()
            } else if status.playerState == .buffering {
                if bufferingSince == nil { bufferingSince = Date() }
                let stalled = Date().timeIntervalSince(bufferingSince!) >= 45
                if stalled && recoverPlayback() { return }
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
                if let positionKey { UserDefaults.standard.removeObject(forKey: positionKey) }
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
        if url.scheme == "stremiocast" && url.host == "controls" {
            if client == nil { message = "Riconnetti Chromecast per usare i controlli." }
            return
        }
        work?.cancel()
        resetPlayback()
        sources = []; selectedSource = nil; prepared = nil; handoff = nil; configuration = nil; originalURL = nil; hasLoaded = false; lastGoodPosition = 0
        do {
            let ticket = try BridgeClient.shared.ticket(from:url)
            busy = true; message = "Apro la sorgente…"
            work = Task {
                do {
                    let data = try await BridgeClient.shared.handoff(ticket:ticket)
                    try Task.checkCancellation()
                    handoff = data; work = nil
                    beginSources(data)
                } catch is CancellationError { } catch {
                    if Task.isCancelled { return }
                    busy = false
                    message = (error as? BridgeError)?.localizedDescription ?? "Non riesco ad aprire il collegamento. Riprova da Stremio."
                }
            }
        } catch { busy = false; message = (error as? BridgeError)?.localizedDescription ?? "Collegamento non valido." }
    }
    private func beginSources(_ data: BridgeHandoff) {
        work?.cancel()
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
                    try Task.checkCancellation()
                    sources = found; busy = false; work = nil
                    if let wanted = data.selection, let selected = found.first(where: { $0.identity == wanted }) {
                        choose(selected)
                    } else {
                        message = data.selection == nil ? "Scegli una sorgente." : "La sorgente è cambiata: scegli un file dall’elenco aggiornato."
                    }
                } catch is CancellationError { } catch {
                    if Task.isCancelled { return }
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
        resetPlayback()
        work?.cancel(); work = nil; busy = false; selectedSource = nil; prepared = nil; hasLoaded = false
        message = "Scegli una sorgente."
    }
    func choose(_ source: AddonStream) {
        resetPlayback()
        wantsPlayback = true
        work?.cancel(); subtitleFile = nil; embeddedSubtitleURL = nil; selectedSource = source; prepared = nil; originalURL = nil; hasLoaded = false; lastGoodPosition = 0
        guard let handoff else { message = "Riapri la sorgente da Stremio."; return }
        let identity = handoff.provider + "|" + source.identity
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        positionKey = "cast.position." + digest
        lastGoodPosition = max(0, UserDefaults.standard.double(forKey: positionKey!))
        position = lastGoodPosition
        busy = true; message = "Leggo audio e sottotitoli del file…"
        work = Task {
            do {
                guard let key = configuration?.realDebridKey, !key.isEmpty else { throw BridgeError.cannotResolve }
                let resolver = RDNativeResolver(apiKey:key, session:URLSession(configuration:.ephemeral))
                let result: RDPreparedMedia
                let cacheKey = contentDigest(key + "|" + handoff.id + "|" + source.identity)
                if let (saved,time) = preparedCache[cacheKey], Date().timeIntervalSince(time) < 120 {
                    result = saved
                } else {
                    let direct: URL?
                    do { direct = try await BridgeClient.shared.resolveDirect(source) }
                    catch BridgeError.cannotResolve { direct = nil }
                    try Task.checkCancellation()
                    if let direct {
                        let file = try await resolver.originalFile(directLink:direct)
                        originalURL = file.download
                        result = try await EmbeddedMediaEngine.inspect(file.download)
                    } else if let hash = source.torrentHash, let filename = source.filename {
                        let link = try await resolver.resolveTorrentLink(torrentHash:hash, filename:filename, videoSize:source.behaviorHints?.videoSize,onProgress:{ [weak self] state,progress in
                            guard let self else { return }
                            await self.showPreparationStatus(state,progress:progress)
                        })
                        let file = try await resolver.originalFile(directLink:link)
                        originalURL = file.download
                        result = try await EmbeddedMediaEngine.inspect(file.download)
                    } else { throw BridgeError.cannotResolve }
                    if preparedCache.count >= 8, let oldest = preparedCache.min(by:{$0.value.1 < $1.value.1})?.key { preparedCache[oldest] = nil }
                    preparedCache[cacheKey] = (result,Date())
                }
                try Task.checkCancellation()
                guard !result.audio.isEmpty else { throw BridgeError.cannotResolve }
                prepared = result; selectedAudio = PlaybackPreferences.audio(result.audio,fallback:result.defaultAudioKey)
                selectedQuality = result.availableQualities.contains(.high) ? .high : (result.availableQualities.first ?? .high)
                compatibilityMode = false
                selectedSubtitle = PlaybackPreferences.subtitle(result.subtitles,external:externalSubtitleURL != nil,handoff:handoff.subtitleLanguage)
                busy = false
                message = "Video pronto. Collega la TV per iniziare."
                if connected && wantsPlayback { load() }
            } catch is CancellationError { } catch {
                if Task.isCancelled { return }
                busy = false
                message = (error as? RDResolverError)?.localizedDescription ?? (error as? BridgeError)?.localizedDescription ?? "Non riesco a leggere le tracce di questo file. Scegli un’altra sorgente."
            }
        }
    }
    private func showPreparationStatus(_ state: String, progress: Int?) {
        guard !Task.isCancelled else { return }
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
        startPlayback(requestedPosition:nil,autoplay:hasLoaded ? playing : true)
    }
    private func startPlayback(requestedPosition: Double?, autoplay: Bool) {
        guard let prepared, client != nil else { message = "Collega prima il Chromecast e scegli un file."; return }
        guard !loading, !loadPending, subtitleRequest == nil else { return }
        capturePosition()
        let audio = selectedAudio, subtitle = selectedSubtitle
        let burnedSubtitle = subtitle.hasPrefix("vlc_") ? subtitle : "none"
        let needsLocal = forceLocalPlayback || !prepared.directCompatible || audio != prepared.defaultAudioKey || burnedSubtitle != "none"
        if !needsLocal {
            stopLocalProcessing(); compatibilityMode = false; processingDetail = "Originale · diretto"
            sendLoad(preservePosition:true,autoplay:autoplay)
            return
        }
        let appearance = burnedSubtitle == "none" ? SubtitleAppearance() : SubtitleAppearance.load()
        let selection = NativeSelection(input:prepared.directURL,audio:audio,subtitle:burnedSubtitle,appearance:appearance,external:externalSubtitleURL,extracted:embeddedSubtitleURL)
        let requiredCaption = subtitle == "external" ? 1 : subtitle == "embedded" ? 2 : nil
        if requestedPosition == nil, selection == nativeSelection, let engine = nativeEngine, engine.running, let url = engine.streamURL, requiredCaption == nil || engine.captionURLs[requiredCaption!] != nil {
            sendLoad(preservePosition:false,urlOverride:url,contentTypeOverride:engine.contentType,autoplay:autoplay)
            return
        }
        guard let host = castSession?.device.ipAddress, CastWire.localIPv4(host) else { playbackIssue = EmbeddedMediaError.address.localizedDescription; return }
        let start = requestedPosition ?? lastGoodPosition
        checkingStream = true; loading = true; playbackIssue = nil
        message = "Preparo il flusso sull’iPhone…"
        streamCheckTask = Task { [weak self] in
            let background = UIApplication.shared.beginBackgroundTask(withName:"Prepare Cast stream")
            defer { if background != .invalid { UIApplication.shared.endBackgroundTask(background) } }
            do {
                guard let self else { return }
                var captions: [Int:String] = [:]
                for (id,url) in [(1,selection.external),(2,selection.extracted)] {
                    if id == requiredCaption, let url, let text = await self.readCaption(url) { captions[id] = text }
                    try Task.checkCancellation()
                }
                if let requiredCaption, captions[requiredCaption] == nil {
                    let languages = self.handoff?.subtitleLanguage == "ita" ? ["it","ita"] : ["en","eng"]
                    self.selectedSubtitle = prepared.subtitles.first(where:{languages.contains($0.language.lowercased())})?.key ?? "none"
                    self.checkingStream = false; self.loading = false
                    self.startPlayback(requestedPosition:start,autoplay:autoplay)
                    return
                }
                let convertVideo = prepared.requiresVideoConversion || burnedSubtitle != "none"
                let modes = EmbeddedMediaEngine.modes(requiresVideo:convertVideo,fallbackLevel:self.localFallbackLevel)
                var lastError: Error = EmbeddedMediaError.encoder
                for mode in modes {
                    try Task.checkCancellation()
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
                        let url = try await engine.start(input:prepared.directURL,deviceIP:host,start:start,videoMode:mode,audioID:audioID,subtitleID:subtitleID,style:appearance,copyAudio:copyAudio,repairAudio:repairAudio,audioIndex:audioIndex,subtitleIndex:subtitleIndex,captions:captions)
                        try Task.checkCancellation()
                        guard self.prepared?.directURL == prepared.directURL, self.selectedAudio == audio, self.selectedSubtitle == subtitle else { engine.stop(); self.checkingStream = false; self.loading = false; return }
                        self.nativeEngine?.stop()
                        self.nativeEngine = engine; self.nativeSelection = selection
                        engine.refreshBackground()
                        self.localProcessing = true; self.compatibilityMode = true; CastActivityCommands.usesLocalStream = true
                        self.localFallbackLevel = mode == .copy ? 0 : mode == .hardwareH264 ? 1 : 2
                        self.processingDetail = mode == .copy ? (copyAudio ? "Contenitore adattato · audio e video originali" : "Video originale · audio AAC stereo") : mode == .hardwareH264 ? "Video H.264 · audio compatibile" : "Video VP8 · audio Vorbis stereo"
                        engine.onFailure = { [weak self, weak engine] in
                            guard let self, self.nativeEngine === engine else { return }
                            if !self.recoverPlayback() { self.playbackIssue = "Il motore integrato ha interrotto la conversione. La posizione è conservata." }
                        }
                        self.lastGoodPosition = max(0,start); self.position = self.lastGoodPosition
                        self.checkingStream = false; self.loading = false
                        self.sendLoad(preservePosition:false,urlOverride:url,contentTypeOverride:engine.contentType,autoplay:autoplay)
                        return
                    } catch {
                        engine.stop(); lastError = error
                        try Task.checkCancellation()
                    }
                }
                throw lastError
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.checkingStream = false; self.loading = false
                self.playbackIssue = (error as? EmbeddedMediaError)?.localizedDescription ?? "Il motore integrato non ha preparato questa sorgente."
                self.message = "Preparazione del flusso non riuscita."
            }
        }
    }
    private func sendLoad(preservePosition: Bool, urlOverride: URL? = nil, contentTypeOverride: String? = nil, autoplay: Bool = true) {
        guard let prepared, let client else { message = "Collega prima il Chromecast e scegli un file."; return }
        guard !loadPending, subtitleRequest == nil else { return }
        if urlOverride == nil { capturePosition() }
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
                if self.recoverPlayback() { return }
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
        guard hasLoaded, !loadPending, !loading, value.isFinite else { return }
        let target = min(duration > 0 ? max(0,duration-(localProcessing ? 1 : 0)) : value,max(0,value))
        Task { _ = await handleCommand("seek:\(target)") }
    }
    func stopPlayback() {
        Task { if !(await handleCommand("stop")) { endPlayback() } }
    }
    private func endPlayback() {
        if ownsCurrentMedia { client?.stop() }
        resetPlayback(); hasLoaded = false; playing = false; message = "Riproduzione interrotta."
    }
    private func stopLocalProcessing() {
        nativeEngine?.stop(); nativeEngine = nil; nativeSelection = nil
        localProcessing = false; CastActivityCommands.usesLocalStream = false
    }
    @discardableResult private func recoverPlayback() -> Bool {
        guard !checkingStream, let prepared, connected else { return false }
        if localProcessing {
            guard localFallbackLevel < 2 else { return false }
            localFallbackLevel += 1
        } else { guard !forceLocalPlayback else { return false }; forceLocalPlayback = true }
        loadPending = false; loading = false; loadTimeout?.cancel(); loadRequest = nil; hasLoaded = false
        lastGoodPosition = max(lastGoodPosition,position)
        message = "Adatto automaticamente il formato per la TV…"
        startPlayback(requestedPosition:lastGoodPosition,autoplay:true)
        return prepared.directURL == self.prepared?.directURL
    }
    func setVolume(_ value: Double) { castSession?.setDeviceVolume(Float(min(1,max(0,value)))) }
    func unmuteDevice() { castSession?.setDeviceMuted(false) }
    func openControls() { if connected { GCKCastContext.sharedInstance().presentDefaultExpandedMediaControls() } }
    func requestDidComplete(_ request: GCKRequest) {
        if request == subtitleRequest { loadedSubtitle = pendingSubtitle; subtitleRequest = nil; pendingSubtitle = nil; message = "Sottotitoli aggiornati sulla TV."; return }
        if request == commandRequest { finishCommand(true); return }
        if request == loadRequest { loadAccepted = true; message = "Attendo l’avvio sulla TV…"; loadRequest = nil }
    }
    func request(_ request: GCKRequest, didFailWithError error: GCKError) {
        if request == subtitleRequest { subtitleRequest = nil; pendingSubtitle = nil; message = "Cambio sottotitoli non riuscito. Riprova."; return }
        if request == commandRequest { finishCommand(false); return }
        if request == loadRequest { loadPending = false; loading = false; loadTimeout?.cancel(); loadRequest = nil; if recoverPlayback() { return }; message = "Errore Cast \(error.code): il formato non è stato riprodotto dopo l’adattamento automatico."; playbackIssue = message; updateActivity(status: "Apri l’app per riprovare") }
    }
    func request(_ request: GCKRequest, didAbortWith abortReason: GCKRequestAbortReason) {
        if request == subtitleRequest { subtitleRequest = nil; pendingSubtitle = nil; message = "Cambio sottotitoli interrotto. Riprova."; return }
        if request == commandRequest { finishCommand(false); return }
        if request == loadRequest {
            loadPending = false; loading = false; loadTimeout?.cancel(); loadRequest = nil
            message = "Impossibile verificare l’avvio. Riprova: la posizione è conservata."
            updateActivity(status: "Apri l’app per riprovare")
        }
    }
    private func handleCommand(_ command:String) async -> Bool {
        let canUseDirect = !localProcessing || ["toggle","play","pause","stop"].contains(command)
        if canUseDirect && (UIApplication.shared.applicationState != .active || !connected) {
            if await directCommand(command) { return true }
        }
        if await performActivityCommand(command) { return true }
        return canUseDirect ? await directCommand(command) : false
    }
    private func directCommand(_ command:String) async -> Bool {
        let success = await CastDirectControl.perform(command,offset:streamOffset,originalDuration:localProcessing ? duration : nil) { [weak self] position,duration,playing in
            guard let self else { return }
            self.position = position; self.lastGoodPosition = position; self.duration = duration; self.playing = playing
            self.nativeEngine?.setReceiverPaused(!playing)
            self.updateActivity(status:playing ? "In riproduzione" : "In pausa")
        }
        if success && command == "stop" { resetPlayback(); hasLoaded = false; playing = false; message = "Riproduzione interrotta." }
        return success
    }
    private func performActivityCommand(_ command: String) async -> Bool {
        if client == nil || !connected { reconnectControls() }
        for _ in 0..<20 {
            if client != nil { break }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        guard let client, ownsCurrentMedia, !loadPending, commandContinuation == nil else {
            message = "Riconnetti Chromecast per usare i controlli."
            return false
        }
        let request: GCKRequest
        switch command {
        case "play": request = client.play()
        case "pause": request = client.pause()
        case "stop": endPlayback(); return true
        case "toggle": request = client.mediaStatus?.playerState == .playing ? client.pause() : client.play()
        case let value where value == "back" || value == "forward" || value.hasPrefix("seek:"):
            let current = client.approximateStreamPosition() + streamOffset
            guard current.isFinite, current >= 0 else { return false }
            guard var target = CastWire.seekTarget(command,current:current,duration:duration) else { return false }
            if localProcessing {
                if duration > 0 { target = min(target,max(0,duration-1)) }
                startPlayback(requestedPosition:target,autoplay:client.mediaStatus?.playerState == .playing)
                await streamCheckTask?.value
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
        wantsPlayback = false; reconnectTask?.cancel(); reconnectTask = nil
        trackApplyTask?.cancel(); trackApplyTask = nil; lockScreen.clear()
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
        expectedContentID = nil; loadedSignature = nil; loadedSubtitle = nil
        subtitleRequest = nil; pendingSubtitle = nil
        UserDefaults.standard.removeObject(forKey: "cast.session.content")
        UserDefaults.standard.removeObject(forKey: "cast.session.positionKey")
        lastGoodPosition = 0; position = 0; duration = 0
        if let old = activity {
            activity = nil; lastActivityState = ""
            Task {
                if #available(iOS 16.2, *) { await old.end(nil, dismissalPolicy: .immediate) }
                else { await old.end(dismissalPolicy: .immediate) }
            }
        }
    }
    private func updateActivity(status: String) {
        if wantsPlayback && (hasLoaded || loadPending || localProcessing) {
            lockScreen.update(title:displayTitle,device:deviceName,position:lastGoodPosition,duration:duration,playing:playing,loading:loading,local:localProcessing)
        }
        guard hasLoaded || loadPending || activity != nil else { return }
        let stateKey = "\(status)|\(Int(lastGoodPosition / 10))|\(Int(duration))"
        let age = Date().timeIntervalSince(lastActivityUpdate)
        guard (stateKey != lastActivityState && (age >= 5 || status != lastActivityState.components(separatedBy: "|").first)) || age >= 30 else { return }
        lastActivityState = stateKey; lastActivityUpdate = Date()
        let state = CastActivityAttributes.ContentState(status: status, playing: playing, position: lastGoodPosition, duration: duration, updatedAt: Date())
        if activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled {
            let attributes = CastActivityAttributes(title: displayTitle)
            if #available(iOS 16.2, *) { activity = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(60)), pushType: nil) }
            else { activity = try? Activity.request(attributes: attributes, contentState: state, pushType: nil) }
        } else if let activity {
            Task {
                if #available(iOS 16.2, *) { await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(60))) }
                else { await activity.update(using: state) }
            }
        }
    }
}
