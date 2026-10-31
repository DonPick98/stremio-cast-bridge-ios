import SwiftUI
import ActivityKit

struct ContentView: View {
    @EnvironmentObject private var cast: CastController
    @State private var showTrackOptions = false
    @State private var activityMessage = "Prova la visualizzazione sulla schermata di blocco."
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading, spacing:22) {
                    HStack {
                        VStack(alignment:.leading, spacing:4) {
                            Text("CAST BRIDGE").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.mint)
                            Text("La tua TV, pronta.").font(.largeTitle.bold())
                        }
                        Spacer()
                        Button { cast.showSetup = true } label: { Image(systemName:"gearshape").font(.title2).frame(width:40,height:44) }
                            .accessibilityLabel("Configura add-on")
                        CastButton().frame(width:44,height:44).accessibilityLabel("Connetti Chromecast")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Test Live Activity").font(.headline)
                        Text(activityMessage).font(.caption).foregroundStyle(.secondary)
                        HStack { Button("Avvia test") { startActivity() }; Button("Termina test") { endActivities() } }.buttonStyle(.bordered)
                    }.card()
                    Text(cast.message).font(.subheadline).foregroundStyle(.secondary)
                    if cast.busy { ProgressView().tint(.mint) }
                    if !cast.sources.isEmpty {
                        if let source = cast.selectedSource {
                            VStack(alignment:.leading,spacing:8) {
                                Text("Sorgente").font(.headline)
                                Text(source.displayName).font(.caption).lineLimit(5).textSelection(.disabled)
                                Button("Cambia sorgente") { cast.changeSource() }
                            }.card()
                        } else {
                            VStack(alignment:.leading,spacing:10) {
                                Text("Scegli il file").font(.headline)
                                ForEach(Array(cast.sources.enumerated()), id:\.offset) { entry in
                                    Button { cast.choose(entry.element) } label: {
                                        HStack { Text(entry.element.displayName).font(.caption).multilineTextAlignment(.leading).lineLimit(4); Spacer(); Image(systemName:"chevron.right") }
                                    }.buttonStyle(.plain).padding(.vertical,8)
                                    Divider()
                                }
                            }.card()
                        }
                    }
                    if let prepared = cast.prepared {
                        VStack(alignment:.leading,spacing:14) {
                            Button(cast.hasLoaded ? "Applica le tracce" : "Riproduci sulla TV") { cast.load(preservePosition:cast.hasLoaded) }
                                .buttonStyle(.borderedProminent).tint(.mint).disabled(!cast.connected || cast.busy || cast.selectedAudio.isEmpty)
                            if !cast.connected { Text("Collega il Chromecast con il pulsante in alto.").font(.caption).foregroundStyle(.secondary) }
                            DisclosureGroup(isExpanded:$showTrackOptions) {
                                VStack(alignment:.leading,spacing:10) {
                                    Picker("Audio", selection:$cast.selectedAudio) {
                                        ForEach(prepared.audio) { track in Text(trackName(track)).tag(track.key) }
                                    }
                                    Picker("Sottotitoli", selection:$cast.selectedSubtitle) {
                                        Text("Disattivati").tag("none")
                                        ForEach(prepared.subtitles) { track in Text(trackName(track)).tag(track.key) }
                                        if cast.externalSubtitleURL != nil { Text("\(cast.externalSubtitleLabel) · esterni").tag("external") }
                                    }
                                    Picker("Qualità", selection:$cast.selectedQuality) {
                                        ForEach(prepared.availableQualities, id:\.self) { quality in
                                            Text(qualityName(quality)).tag(quality)
                                        }
                                    }
                                    Text("I sottotitoli incorporati vengono preparati nel video. Se cambi traccia durante la riproduzione, premi Applica le tracce.").font(.caption).foregroundStyle(.secondary)
                                }
                            } label: {
                                VStack(alignment:.leading,spacing:4) {
                                    Text("Audio e sottotitoli").font(.headline)
                                    Text("\(audioSummary(prepared)) · \(subtitleSummary(prepared))").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.card()
                    }
                    if cast.connected {
                        VStack(alignment:.leading,spacing:14) {
                            Text("Controlli").font(.headline)
                            HStack {
                                Button { cast.togglePlayback() } label: { Image(systemName:cast.playing ? "pause.fill" : "play.fill").font(.title2).frame(width:44,height:44) }
                                Text(time(cast.position)).monospacedDigit().font(.caption)
                                Slider(value:$cast.position, in:0...max(1,cast.duration), onEditingChanged:{ editing in
                                    cast.userSeeking = editing
                                    if !editing { cast.seek(to:cast.position) }
                                }).disabled(cast.duration <= 0)
                                Text(time(cast.duration)).monospacedDigit().font(.caption)
                            }
                            HStack {
                                Image(systemName:"speaker.fill")
                                Slider(value:$cast.volume, in:0...1, onEditingChanged:{ editing in
                                    cast.userAdjustingVolume = editing
                                    if !editing { cast.setVolume(cast.volume) }
                                })
                                Image(systemName:"speaker.wave.3.fill")
                            }
                            Button("Apri controlli completi") { cast.openControls() }.font(.subheadline)
                        }.card()
                    }
                }.padding(20)
            }.background(Color(red:0.06,green:0.08,blue:0.11)).foregroundStyle(.white)
                .navigationBarHidden(true)
        }.preferredColorScheme(.dark)
            .sheet(isPresented:$cast.showSetup) { AddonSetupView().environmentObject(cast) }
    }
    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { activityMessage = "Le Attività in tempo reale sono disattivate nelle impostazioni."; return }
        guard Activity<CastActivityAttributes>.activities.isEmpty else { activityMessage = "Test già avviato: blocca l’iPhone per visualizzarlo."; return }
        do {
            let attributes = CastActivityAttributes(title: "Cast Bridge")
            let state = CastActivityAttributes.ContentState(status: "Test Live Activity attivo")
            if #available(iOS 16.2, *) { _ = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil), pushType: nil) }
            else { _ = try Activity.request(attributes: attributes, contentState: state, pushType: nil) }
            activityMessage = "Test avviato: blocca l’iPhone per visualizzarlo."
        } catch { activityMessage = "Impossibile avviare il test: \(error.localizedDescription)" }
    }
    private func endActivities() {
        Task {
            for activity in Activity<CastActivityAttributes>.activities {
                if #available(iOS 16.2, *) { await activity.end(nil, dismissalPolicy: .immediate) }
                else { await activity.end(dismissalPolicy: .immediate) }
            }
            await MainActor.run { activityMessage = "Test terminato." }
        }
    }
    private func trackName(_ track: RDTrack) -> String {
        let language = Locale(identifier:"it").localizedString(forLanguageCode:track.language) ?? track.label
        return "\(language.capitalized) · \(track.key) · \(track.codec.uppercased())"
    }
    private func qualityName(_ quality: RDQuality) -> String {
        switch quality {
        case .medium: return "720p"
        case .high: return "1080p"
        case .original: return "Originale"
        }
    }
    private func audioSummary(_ prepared: RDPreparedMedia) -> String {
        guard let track = prepared.audio.first(where: { $0.key == cast.selectedAudio }) else { return "Audio da scegliere" }
        return "Audio: \(track.label)"
    }
    private func subtitleSummary(_ prepared: RDPreparedMedia) -> String {
        if cast.selectedSubtitle == "none" { return "Sottotitoli: disattivati" }
        if cast.selectedSubtitle == "external" { return "Sottotitoli: \(cast.externalSubtitleLabel)" }
        guard let track = prepared.subtitles.first(where: { $0.key == cast.selectedSubtitle }) else { return "Sottotitoli: disattivati" }
        return "Sottotitoli: \(track.label)"
    }
    private func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let value = Int(seconds); return String(format:"%d:%02d", value / 60, value % 60)
    }
}
private extension View {
    func card() -> some View { self.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(Color.white.opacity(0.07), in:RoundedRectangle(cornerRadius:18)) }
}


private struct AddonSetupView: View {
    @EnvironmentObject private var cast: CastController
    @Environment(\.dismiss) private var dismiss
    @State private var torrentio = ""
    @State private var comet = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(cast.setupMessage)
                    Text("Incolla i collegamenti personali degli add-on già configurati con il tuo account Real-Debrid. Le informazioni restano nel portachiavi di questo iPhone.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Collegamenti add-on") {
                    SecureField("Torrentio",text:$torrentio)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("Comet",text:$comet)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Text("Puoi configurare uno o entrambi. Lascia vuoto un campo per mantenere la configurazione già salvata.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button("Salva") {
                    if cast.saveConfigurations(torrentio:torrentio,comet:comet) {
                        torrentio = ""; comet = ""; dismiss()
                    }
                }
            }.navigationTitle("Configura add-on")
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Chiudi") { dismiss() } } }
        }
    }
}
