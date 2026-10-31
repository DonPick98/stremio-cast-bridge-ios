import Foundation
import GoogleCast
import SwiftUI

@MainActor final class CastController: NSObject, ObservableObject, GCKRequestDelegate {
    @Published var showSetup = false
    @Published var setupMessage = "Inserisci i tuoi collegamenti personali una sola volta."
    @Published var sources: [AddonStream] = []
    @Published var selectedSource: AddonStream?
    @Published var prepared: RDPreparedMedia?
    @Published var selectedAudio = ""
    @Published var selectedSubtitle = "none"
    @Published var selectedQuality: RDQuality = .medium
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
    private var handoff: BridgeHandoff?
    private var configuration: AddonConfiguration?
    private var originalURL: URL?
    private var work: Task<Void, Never>?
    private var loadRequest: GCKRequest?
    private var timer: Timer?

    override init() {
        super.init()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateStatus() }
        }
    }
    private var castSession: GCKCastSession? { GCKCastContext.sharedInstance().sessionManager.currentCastSession }
    private var client: GCKRemoteMediaClient? { castSession?.remoteMediaClient }
    private func updateStatus() {
        connected = client != nil
        guard let session = castSession, let client = session.remoteMediaClient else { playing = false; return }
        if !userAdjustingVolume { volume = Double(session.currentDeviceVolume) }
        if let status = client.mediaStatus {
            playing = status.playerState == .playing
            if !userSeeking { position = max(0, client.approximateStreamPosition()) }
            let d = status.mediaInformation?.streamDuration ?? 0
            duration = d.isFinite && d > 0 ? d : 0
        }
    }
    func open(_ url: URL) {
        work?.cancel()
        sources = []; selectedSource = nil; prepared = nil; handoff = nil; configuration = nil; originalURL = nil; hasLoaded = false
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
        work?.cancel(); work = nil; busy = false; selectedSource = nil; prepared = nil; hasLoaded = false
        message = "Scegli una sorgente."
    }
    func choose(_ source: AddonStream) {
        work?.cancel(); selectedSource = source; prepared = nil; originalURL = nil; hasLoaded = false
        guard let handoff else { message = "Riapri la sorgente da Stremio."; return }
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
                selectedQuality = result.availableQualities.contains(.medium) ? .medium : (result.availableQualities.first ?? .medium)
                let languages = handoff.subtitleLanguage == "ita" ? ["it", "ita"] : ["en", "eng"]
                selectedSubtitle = handoff.subtitleLanguage == "off" ? "none" : (result.subtitles.first(where: { languages.contains($0.language.lowercased()) })?.key ?? (externalSubtitleURL == nil ? "none" : "external"))
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
        do {
            let chosenSubtitle: String? = ["none", "external"].contains(selectedSubtitle) ? nil : selectedSubtitle
            let url = try prepared.streamURL(audio:selectedAudio, subtitle:chosenSubtitle, quality:selectedQuality)
            let info = GCKMediaInformationBuilder(contentURL:url)
            info.streamType = .buffered
            info.contentType = "application/vnd.apple.mpegurl"
            let metadata = GCKMediaMetadata(metadataType:.movie)
            metadata.setString(selectedSource?.filename ?? "Stremio", forKey:kGCKMetadataKeyTitle)
            info.metadata = metadata
            let load = GCKMediaLoadRequestDataBuilder()
            load.autoplay = NSNumber(value: true)
            if selectedSubtitle == "external", let external = externalSubtitleURL {
                if let track = GCKMediaTrack(identifier:1, contentIdentifier:external.absoluteString, contentType:"text/vtt", type:.text, textSubtype:.subtitles, name:externalSubtitleLabel, languageCode:(handoff?.subtitleLanguage == "ita" ? "it" : "en"), customData:nil) {
                    info.mediaTracks = [track]
                    load.activeTrackIDs = [1]
                }
            }
            load.mediaInformation = info.build()
            if preservePosition { load.startTime = max(0, client.approximateStreamPosition()) }
            let request = client.loadMedia(with:load.build())
            loadRequest = request; request.delegate = self
            message = "Invio il video al Chromecast…"
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
    func togglePlayback() { guard let client else { return }; if playing { client.pause() } else { client.play() } }
    func seek(to value: Double) { guard let client else { return }; let opts = GCKMediaSeekOptions(); opts.interval = max(0,value); client.seek(with:opts) }
    func setVolume(_ value: Double) { castSession?.setDeviceVolume(Float(min(1,max(0,value)))) }
    func openControls() { if connected { GCKCastContext.sharedInstance().presentDefaultExpandedMediaControls() } }
    func requestDidComplete(_ request: GCKRequest) {
        if request == loadRequest { hasLoaded = true; message = "Comando inviato al Chromecast."; loadRequest = nil }
    }
    func request(_ request: GCKRequest, didFailWithError error: GCKError) {
        if request == loadRequest { message = "Il Chromecast non è riuscito ad aprire il video. Prova un’altra sorgente."; loadRequest = nil }
    }
}
