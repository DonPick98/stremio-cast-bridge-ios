import Foundation
import GoogleCast
import SwiftUI
import ActivityKit
import CryptoKit

@MainActor final class CastController: NSObject, ObservableObject, GCKRequestDelegate {
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
    private var handoff: BridgeHandoff?
    private var configuration: AddonConfiguration?
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
    private var previousMediaSessionID = 0
    private var ignorePriorSession = false
    private var expectedContentID: String?
    private var loadedSignature: String?
    private var loadedSubtitle: String?
    private var subtitleRequest: GCKRequest?
    private var pendingSubtitle: String?
    private var commandRequest: GCKRequest?
    private var commandContinuation: CheckedContinuation<Bool, Never>?
    private var commandTimeout: Task<Void, Never>?

    override init() {
        super.init()
        activity = Activity<CastActivityAttributes>.activities.first
        CastActivityCommands.handler = { [weak self] command in
            guard let self else { return false }
            return await self.performActivityCommand(command)
        }
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
        guard let id = client?.mediaStatus?.mediaInformation?.contentID else { return false }
        if let expectedContentID { return id == expectedContentID }
        return UserDefaults.standard.string(forKey: "cast.session.content") == contentDigest(id)
    }
    private func capturePosition() {
        guard ownsCurrentMedia, !loadPending, let client,
              let state = client.mediaStatus?.playerState, state == .playing || state == .paused || state == .buffering else { return }
        let value = client.approximateStreamPosition()
        guard value.isFinite, value >= 0, state != .buffering || value > 0 else { return }
        lastGoodPosition = value
        if let positionKey { UserDefaults.standard.set(value, forKey: positionKey) }
    }
    func savePlaybackPosition() { capturePosition() }
    private func updateStatus() {
        connected = client != nil
        guard let session = castSession, let client = session.remoteMediaClient else { playing = false; updateActivity(status: "Apri l’app per riconnettere Chromecast"); return }
        if !userAdjustingVolume { volume = Double(session.currentDeviceVolume) }
        if let status = client.mediaStatus {
            // Receivers can reuse mediaSessionID across LOAD calls. Match the
            // expected content instead; never copy another video's position.
            guard ownsCurrentMedia else { playing = false; return }
            if loadPending && !loadAccepted { return }
            playing = status.playerState == .playing
            let observed = client.approximateStreamPosition()
            if !loadPending && observed.isFinite && observed >= 0 && (status.playerState == .playing || status.playerState == .paused) {
                lastGoodPosition = observed
                if let positionKey, observed > 0, Date().timeIntervalSince(lastPositionSave) >= 10 {
                    UserDefaults.standard.set(observed, forKey: positionKey); lastPositionSave = Date()
                }
                if !userSeeking { position = observed }
            }
            let d = status.mediaInformation?.streamDuration ?? 0
            duration = d.isFinite && d > 0 ? d : 0
            let currentLoad = !loadPending || loadAccepted
            if (status.playerState == .playing || status.playerState == .paused) && currentLoad {
                if loadPending { loadPending = false; loading = false; loadTimeout?.cancel(); hasLoaded = true }
                message = playing ? "In riproduzione sulla TV." : "In pausa sulla TV."
                updateActivity(status: playing ? "In riproduzione" : "In pausa")
            } else if status.playerState == .buffering {
                message = "Caricamento sulla TV…"
                updateActivity(status: "Caricamento")
            } else if status.playerState == .idle && currentLoad && status.idleReason == .error {
                loadPending = false; loading = false; loadTimeout?.cancel(); loadRequest = nil
                message = "La riproduzione si è interrotta. Riprova: la posizione è conservata."
                updateActivity(status: "Errore: apri l’app per riprovare")
            } else if status.playerState == .idle && currentLoad && status.idleReason == .finished {
                loadPending = false; loading = false; loadTimeout?.cancel()
                message = "Riproduzione terminata."
                if let positionKey { UserDefaults.standard.removeObject(forKey: positionKey) }
                lastGoodPosition = 0
                updateActivity(status: "Riproduzione terminata")
            }
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
    @discardableResult func saveConfigurations(torrentio: String, comet: String) -> Bool {
        do {
            var values: [AddonConfiguration] = []
            if !torrentio.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { values.append(try AddonConfigStore.parse(torrentio,provider:"torrentio")) }
            if !comet.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { values.append(try AddonConfigStore.parse(comet,provider:"comet")) }
            guard !values.isEmpty else { setupMessage = "Incolla almeno un collegamento personale."; return false }
            for value in values { try AddonConfigStore.save(value) }
            showSetup = false; setupMessage = "Configurazione salvata."
            if let data = handoff {
                beginSources(data)
                if showSetup { return false }
            } else { message = "Configurazione salvata. Apri una sorgente Chromecast da Stremio." }
            return true
        } catch {
            setupMessage = (error as? AddonConfigError)?.localizedDescription ?? "Non riesco a salvare la configurazione."
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
        work?.cancel(); selectedSource = source; prepared = nil; originalURL = nil; hasLoaded = false; lastGoodPosition = 0
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
                if let hash = source.torrentHash, let filename = source.filename {
                    result = try await resolver.prepare(torrentHash:hash, filename:filename, videoSize:source.behaviorHints?.videoSize)
                } else {
                    let direct = try await BridgeClient.shared.resolveDirect(source)
                    originalURL = direct
                    result = try await resolver.prepare(directLink:direct)
                }
                try Task.checkCancellation()
                guard !result.audio.isEmpty else { throw BridgeError.cannotResolve }
                prepared = result; selectedAudio = result.defaultAudioKey
                selectedQuality = result.availableQualities.contains(.high) ? .high : (result.availableQualities.first ?? .high)
                compatibilityMode = false
                selectedSubtitle = handoff.subtitleLanguage == "off" ? "none" : (externalSubtitleURL != nil ? "external" : "none")
                busy = false
                message = "Video pronto. Collega il Chromecast e premi Riproduci sulla TV."
            } catch is CancellationError { } catch {
                if Task.isCancelled { return }
                busy = false
                message = (error as? RDResolverError)?.localizedDescription ?? "Non riesco a leggere le tracce di questo file. Scegli un’altra sorgente."
            }
        }
    }
    func load(preservePosition: Bool = false) {
        guard let prepared, let client else { message = "Collega prima il Chromecast e scegli un file."; return }
        guard !loadPending else { return }
        capturePosition()
        do {
            let chosenSubtitle: String? = ["none", "external"].contains(selectedSubtitle) ? nil : selectedSubtitle
            guard compatibilityMode || chosenSubtitle == nil else { message = "Per i sottotitoli incorporati attiva la modalità compatibilità."; return }
            let url = compatibilityMode ? try prepared.streamURL(audio:selectedAudio, subtitle:chosenSubtitle, quality:selectedQuality) : prepared.directURL
            let signature = url.absoluteString
            // Text tracks are attached even when disabled, so selecting one
            // later does not need to reload the movie or recreate its buffer.
            if hasLoaded && ownsCurrentMedia && loadedSignature == signature && loadedSubtitle != selectedSubtitle {
                let ids: [NSNumber] = selectedSubtitle == "external" ? [1] : []
                if selectedSubtitle == "external" && externalSubtitleURL == nil { return }
                let request = client.setActiveTrackIDs(ids)
                subtitleRequest = request; request.delegate = self
                pendingSubtitle = selectedSubtitle
                message = "Aggiorno i sottotitoli sulla TV…"
                return
            }
            let info = GCKMediaInformationBuilder(contentURL:url)
            info.streamType = .buffered
            info.contentType = compatibilityMode ? "application/vnd.apple.mpegurl" : prepared.directContentType
            let metadata = GCKMediaMetadata(metadataType:.movie)
            metadata.setString(selectedSource?.filename ?? "Stremio", forKey:kGCKMetadataKeyTitle)
            info.metadata = metadata
            let load = GCKMediaLoadRequestDataBuilder()
            load.autoplay = NSNumber(value: true)
            if let external = externalSubtitleURL {
                if let track = GCKMediaTrack(identifier:1, contentIdentifier:external.absoluteString, contentType:"text/vtt", type:.text, textSubtype:.subtitles, name:externalSubtitleLabel, languageCode:(handoff?.subtitleLanguage == "ita" ? "it" : "en"), customData:nil) {
                    info.mediaTracks = [track]
                    load.activeTrackIDs = selectedSubtitle == "external" ? [1] : []
                }
            }
            load.mediaInformation = info.build()
            if preservePosition || lastGoodPosition > 0 { load.startTime = max(0, lastGoodPosition) }
            previousMediaSessionID = client.mediaStatus?.mediaSessionID ?? 0
            ignorePriorSession = previousMediaSessionID != 0
            loadPending = true
            loading = true
            hasLoaded = false
            loadAccepted = false
            expectedContentID = url.absoluteString
            loadedSignature = signature
            loadedSubtitle = selectedSubtitle
            UserDefaults.standard.set(contentDigest(url.absoluteString), forKey: "cast.session.content")
            let request = client.loadMedia(with:load.build())
            loadRequest = request; request.delegate = self
            message = "Invio il video al Chromecast…"
            updateActivity(status: "Caricamento")
            loadTimeout?.cancel()
            loadTimeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled, let self, self.loadPending else { return }
                self.loadPending = false; self.loading = false; self.loadRequest = nil
                self.message = "La TV non ha avviato il video. Riprova o cambia modalità; la posizione è conservata."
                self.updateActivity(status: "Apri l’app per riprovare")
            }
        } catch { message = "Non riesco a preparare il video con queste tracce." }
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
    func togglePlayback() { guard let client, ownsCurrentMedia, !loadPending else { return }; if playing { client.pause() } else { client.play() } }
    func seek(to value: Double) { guard let client, ownsCurrentMedia, !loadPending, value.isFinite else { return }; let opts = GCKMediaSeekOptions(); opts.interval = min(duration > 0 ? duration : value,max(0,value)); client.seek(with:opts) }
    func setVolume(_ value: Double) { castSession?.setDeviceVolume(Float(min(1,max(0,value)))) }
    func openControls() { if connected { GCKCastContext.sharedInstance().presentDefaultExpandedMediaControls() } }
    func requestDidComplete(_ request: GCKRequest) {
        if request == subtitleRequest { loadedSubtitle = pendingSubtitle; subtitleRequest = nil; pendingSubtitle = nil; message = "Sottotitoli aggiornati sulla TV."; return }
        if request == commandRequest { finishCommand(true); return }
        if request == loadRequest { loadAccepted = true; message = "Attendo l’avvio sulla TV…"; loadRequest = nil }
    }
    func request(_ request: GCKRequest, didFailWithError error: GCKError) {
        if request == subtitleRequest { subtitleRequest = nil; pendingSubtitle = nil; message = "Cambio sottotitoli non riuscito. Riprova."; return }
        if request == commandRequest { finishCommand(false); return }
        if request == loadRequest { loadPending = false; loading = false; loadTimeout?.cancel(); message = "Errore Cast \(error.code): riprova o cambia modalità; la posizione è conservata."; loadRequest = nil; updateActivity(status: "Apri l’app per riprovare") }
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
    private func performActivityCommand(_ command: String) async -> Bool {
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
        case "toggle": request = client.mediaStatus?.playerState == .playing ? client.pause() : client.play()
        case "back", "forward":
            let current = client.approximateStreamPosition()
            guard current.isFinite, current >= 0 else { return false }
            let target = current + (command == "back" ? -30 : 30)
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
        capturePosition()
        if let positionKey, lastGoodPosition > 0 { UserDefaults.standard.set(lastGoodPosition, forKey: positionKey) }
        positionKey = nil
        finishCommand(false)
        loadTimeout?.cancel(); loadPending = false; loading = false; loadAccepted = false; loadRequest = nil; ignorePriorSession = false
        expectedContentID = nil; loadedSignature = nil; loadedSubtitle = nil
        subtitleRequest = nil; pendingSubtitle = nil
        UserDefaults.standard.removeObject(forKey: "cast.session.content")
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
        guard hasLoaded || loadPending || activity != nil else { return }
        let stateKey = "\(status)|\(Int(lastGoodPosition / 10))|\(Int(duration))"
        let age = Date().timeIntervalSince(lastActivityUpdate)
        guard (stateKey != lastActivityState && (age >= 5 || status != lastActivityState.components(separatedBy: "|").first)) || age >= 30 else { return }
        lastActivityState = stateKey; lastActivityUpdate = Date()
        let state = CastActivityAttributes.ContentState(status: status, playing: playing, position: lastGoodPosition, duration: duration, updatedAt: Date())
        if activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled {
            let attributes = CastActivityAttributes(title: selectedSource?.filename ?? "Stremio")
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
