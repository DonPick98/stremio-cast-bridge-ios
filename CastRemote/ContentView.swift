import SwiftUI

import ActivityKit

struct ContentView: View {

    @EnvironmentObject private var cast: CastController

    @State private var showTrackOptions = false
    @State private var showSubtitleAppearance = false

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

Text(cast.message).font(.subheadline).foregroundStyle(.secondary)

                    if cast.busy { ProgressView().tint(.mint) }

                    if !cast.sources.isEmpty {

                        if let source = cast.selectedSource {

                            VStack(alignment:.leading,spacing:8) {

                                HStack(alignment:.firstTextBaseline) {
                                    Text("Sorgente").font(.headline)
                                    Spacer()
                                    Text(source.fileSizeLabel).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                                }

                                Text(source.displayName).font(.caption).lineLimit(5).textSelection(.disabled)

                                Button("Cambia sorgente") { cast.changeSource() }

                            }.card()

                        } else {

                            VStack(alignment:.leading,spacing:10) {

                                Text("Scegli il file").font(.headline)

                                ForEach(Array(cast.sources.enumerated()), id:\.offset) { entry in

                                    Button { cast.choose(entry.element) } label: {

                                        HStack(alignment:.center,spacing:12) {
                                            Text(entry.element.displayName).font(.caption).multilineTextAlignment(.leading).lineLimit(4)
                                            Spacer(minLength:4)
                                            Text(entry.element.fileSizeLabel).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary).multilineTextAlignment(.trailing).frame(width:94,alignment:.trailing)
                                            Image(systemName:"chevron.right")
                                        }

                                    }.buttonStyle(.plain).padding(.vertical,8)

                                    Divider()

                                }

                            }.card()

                        }

                    }

                    if let prepared = cast.prepared {

                        VStack(alignment:.leading,spacing:14) {

                            Button(cast.hasLoaded ? "Applica le tracce" : "Riproduci sulla TV") { cast.load(preservePosition:cast.hasLoaded) }

                                .buttonStyle(.borderedProminent).tint(.mint).disabled(!cast.connected || cast.busy || cast.loading || cast.selectedAudio.isEmpty)
                            if cast.loading { ProgressView("Attendo la TV…").tint(.mint) }

                            if !cast.connected { Text("Collega il Chromecast con il pulsante in alto.").font(.caption).foregroundStyle(.secondary) }

                            Text(prepared.videoDescription).font(.caption).foregroundStyle(.secondary)
                            Toggle("Modalità compatibilità", isOn:$cast.compatibilityMode)
                                .disabled(prepared.availableQualities.isEmpty || cast.loading)
                                .onChange(of: cast.compatibilityMode) { enabled in
                                    if !enabled { cast.selectedAudio = prepared.defaultAudioKey; if !["external","embedded"].contains(cast.selectedSubtitle) { cast.selectedSubtitle = "none" } }
                                }
                            Text(cast.compatibilityMode ? "Conversione Real-Debrid: permette di scegliere audio e sottotitoli incorporati; può richiedere più tempo." : "File originale: qualità della sorgente, senza conversione.").font(.caption).foregroundStyle(.secondary)
                            if prepared.availableQualities.isEmpty { Text("Conversione non disponibile per questo file.").font(.caption).foregroundStyle(.secondary) }
                            if !cast.compatibilityMode && !prepared.directCompatible {
                                Text("Compatibilità del file originale non confermata: se non si avvia, usa la modalità compatibilità.").font(.caption).foregroundStyle(.secondary)
                            }
                            Text("Se i controlli dalla schermata di blocco non rispondono, apri l’app e riconnetti la TV.").font(.caption).foregroundStyle(.secondary)
                            DisclosureGroup(isExpanded:$showTrackOptions) {

                                VStack(alignment:.leading,spacing:10) {

                                    Picker("Audio nel file", selection:$cast.selectedAudio) {

                                        ForEach(prepared.audio) { track in Text(trackName(track)).tag(track.key) }

                                    }.onChange(of:cast.selectedAudio) { value in
                                        if !cast.compatibilityMode && value != prepared.defaultAudioKey {
                                            if !prepared.availableQualities.isEmpty { cast.compatibilityMode = true }
                                            else { cast.selectedAudio = prepared.defaultAudioKey; cast.message = "Questa traccia richiede una conversione, non disponibile per il file." }
                                        }
                                    }
                                    if !cast.compatibilityMode && prepared.audio.count > 1 { Text("Scegliere un altro audio attiva la conversione Real-Debrid.").font(.caption).foregroundStyle(.secondary) }

                                    Picker("Sottotitoli", selection:$cast.selectedSubtitle) {

                                        Text("Disattivati").tag("none")

                                        ForEach(prepared.subtitles) { track in Text(trackName(track) + " · conversione").tag(track.key) }

                                        if cast.externalSubtitleURL != nil { Text("\(cast.externalSubtitleLabel) · esterni").tag("external") }
                                        if cast.embeddedSubtitleURL != nil { Text("\(cast.externalSubtitleLabel) · estratti dal file").tag("embedded") }

                                    }.onChange(of:cast.selectedSubtitle) { value in
                                        if !["none","external","embedded"].contains(value) && !cast.compatibilityMode {
                                            if !prepared.availableQualities.isEmpty { cast.compatibilityMode = true }
                                            else { cast.selectedSubtitle = "none"; cast.message = "Per questa traccia usa l’estrazione; la conversione non è disponibile." }
                                        }
                                    }
                                    if prepared.subtitles.isEmpty { Text("Real-Debrid non segnala sottotitoli incorporati per questa sorgente. Puoi comunque provare l’estrazione.").font(.caption).foregroundStyle(.secondary) }
                                    Button("Estrai sottotitoli dal file") { cast.extractEmbeddedSubtitles() }
                                    Button("Aspetto sottotitoli · anteprima") { showSubtitleAppearance = true }
                                        .disabled(cast.busy || cast.loading)
                                    if let file = cast.subtitleFile { ShareLink("Esporta WebVTT",item:file) }
                                    Text("Estrazione per MKV con indice e sottotitoli testuali. Gli effetti ASS complessi non vengono conservati; verifica che il testo sia completo.").font(.caption).foregroundStyle(.secondary)

                                    if cast.compatibilityMode { Picker("Qualità conversione", selection:$cast.selectedQuality) {

                                        ForEach(prepared.availableQualities, id:\.self) { quality in

                                            Text(qualityName(quality)).tag(quality)

                                        }

                                    } }

                                    Text("Premi Applica le tracce per confermare. I sottotitoli esterni si cambiano senza ricaricare il video. Per cambiare audio o sottotitoli incorporati usa la modalità compatibilità.").font(.caption).foregroundStyle(.secondary)

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
            .sheet(isPresented:$showSubtitleAppearance) { SubtitleAppearanceView().environmentObject(cast) }

    }

    private func trackName(_ track: RDTrack) -> String {

        let language = Locale(identifier:"it").localizedString(forLanguageCode:track.language) ?? track.label

        return "\(language.capitalized) · \(track.key) · \(track.codec.uppercased())"

    }

    private func qualityName(_ quality: RDQuality) -> String {

        switch quality {

        case .medium: return "720p"

        case .high: return "1080p"

        case .original: return "Originale (conversione)"

        }

    }

    private func audioSummary(_ prepared: RDPreparedMedia) -> String {

        if !cast.compatibilityMode { return "Audio predefinito del file" }
        guard let track = prepared.audio.first(where: { $0.key == cast.selectedAudio }) else { return "Audio da scegliere" }

        return "Audio: \(track.label)"

    }

    private func subtitleSummary(_ prepared: RDPreparedMedia) -> String {

        if cast.selectedSubtitle == "none" { return "Sottotitoli: disattivati" }

        if cast.selectedSubtitle == "external" { return "Sottotitoli: \(cast.externalSubtitleLabel)" }
        if cast.selectedSubtitle == "embedded" { return "Sottotitoli dal file: \(cast.externalSubtitleLabel)" }

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
    @State private var subtitleEndpoint = ""
    @State private var subtitleToken = ""

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

                Section("Sottotitoli estratti · servizio facoltativo") {
                    TextField("Indirizzo HTTPS del servizio",text:$subtitleEndpoint).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("Chiave del servizio",text:$subtitleToken).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Serve per rendere il testo estratto disponibile al Chromecast a telefono bloccato. Il servizio riceve solo il WebVTT; il link del film resta sull’iPhone. Lascia vuoto per mantenere la configurazione salvata.").font(.footnote).foregroundStyle(.secondary)
                }
                Button("Salva") {

                    if cast.saveConfigurations(torrentio:torrentio,comet:comet,subtitleEndpoint:subtitleEndpoint,subtitleToken:subtitleToken) {

                        torrentio = ""; comet = ""; dismiss()

                    }

                }

            }.navigationTitle("Configura add-on")

                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Chiudi") { dismiss() } } }

        }

    }

}


