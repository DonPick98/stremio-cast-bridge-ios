import SwiftUI
import UIKit

enum CastPalette {
    static let background = Color(red:0.045,green:0.052,blue:0.065)
    static let surface = Color(red:0.078,green:0.089,blue:0.108)
    static let accent = Color(red:0.65,green:0.87,blue:0.79)
}

struct ContentView: View {
    @EnvironmentObject private var cast: CastController
    @State private var showTrackOptions = false
    @State private var showSubtitleAppearance = false
    @State private var showOnlineSubtitles = false
    @State private var diagnosticsCopied = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    header
                    HStack(alignment:.top,spacing:10) {
                        if cast.busy || cast.loading { ProgressView().controlSize(.small).padding(.top,2) }
                        Text(cast.message).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                    if cast.subtitleDownloadBusy {
                        HStack(spacing:8){ProgressView().controlSize(.small);Text(cast.subtitlePreparation).font(.footnote).foregroundStyle(.secondary)}
                            .frame(maxWidth:.infinity,alignment:.leading)
                    }
                    if let issue = cast.playbackIssue {
                        Label(issue,systemImage:"exclamationmark.circle").font(.subheadline).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true).castCard()
                    }
                    if let warning = cast.subtitlePlaybackWarning {
                        Button { showTrackOptions = true } label: {
                            Label(warning,systemImage:"captions.bubble").font(.subheadline).foregroundStyle(.orange).multilineTextAlignment(.leading).fixedSize(horizontal:false,vertical:true).castCard()
                        }.buttonStyle(.plain)
                    }
                    if let source = cast.selectedSource { sourceCard(source) }
                    else if !cast.sources.isEmpty { sourcesCard }
                    else { emptyState }
                    if cast.hasLoaded || cast.playing || (cast.loading && cast.duration > 0) { playerCard }
                    if let media = cast.prepared {
                        optionsCard(media)
                        if !cast.hasLoaded { playButton }
                    }
                }.padding(.horizontal,22).padding(.top,20).padding(.bottom,32)
                    .frame(maxWidth:600).frame(maxWidth:.infinity)
            }.background(CastPalette.background).toolbar(.hidden,for:.navigationBar)
        }.preferredColorScheme(.dark).tint(CastPalette.accent)
            .sheet(isPresented:$cast.showSetup) { AddonSetupView().environmentObject(cast) }
            .sheet(isPresented:$showTrackOptions) { TrackOptionsView().environmentObject(cast) }
            .sheet(isPresented:$showSubtitleAppearance) { SubtitleAppearanceView().environmentObject(cast) }
            .sheet(isPresented:$showOnlineSubtitles) { SubtitleBrowserView().environmentObject(cast) }
            .onChange(of:cast.sourceRevision) { _ in
                showTrackOptions = false; showSubtitleAppearance = false; showOnlineSubtitles = false
            }
            .alert("Diagnostica copiata",isPresented:$diagnosticsCopied) {
                Button("OK",role:.cancel) { }
            } message: {
                Text("Incollala nella chat con Codex. Contiene gli ultimi 10 minuti, senza link personali o credenziali.")
            }
    }
    private var header: some View {
        HStack(spacing:12) {
            VStack(alignment:.leading,spacing:6) {
                Text("Cast Bridge").font(.title2.weight(.semibold)).tracking(-0.6)
                HStack(spacing:6) {
                    Circle().fill(cast.connected ? CastPalette.accent : Color.gray).frame(width:5,height:5)
                    Text(cast.connected ? cast.deviceName : cast.hasLoaded ? "Ricollego i controlli…" : "Collega una TV").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                cast.copyDiagnostics(); diagnosticsCopied = true
            } label: {
                Image(systemName:"terminal").font(.system(size:17)).frame(width:44,height:44).background(.white.opacity(0.045),in:Circle())
            }.foregroundStyle(.white).accessibilityLabel("Codex: copia diagnostica")
            Menu {
                Button { showSubtitleAppearance = true } label: { Label("Aspetto sottotitoli",systemImage:"textformat.size") }
                Button { cast.showSetup = true } label: { Label("Configura sorgenti",systemImage:"link") }
                Link("Componenti open source",destination:URL(string:"https://github.com/DonPick98/stremio-cast-bridge-ios/blob/main/THIRD_PARTY_NOTICES.md")!)
            } label: {
                Image(systemName:"slider.horizontal.3").font(.system(size:17)).frame(width:44,height:44).background(.white.opacity(0.045),in:Circle())
            }.foregroundStyle(.white).accessibilityLabel("Impostazioni")
            CastButton().frame(width:44,height:44).accessibilityLabel("Connetti Chromecast")
        }
    }
    private func sourceCard(_ source: AddonStream) -> some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.firstTextBaseline) { sectionLabel("Sorgente"); Spacer(); sizeBadge(source) }
            Text(sourceTitle(source)).font(.headline.weight(.medium)).lineLimit(3).lineSpacing(3)
            HStack {
                Text(source.name ?? "Sorgente selezionata").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button { cast.changeSource() } label: { HStack(spacing:5) { Text("Cambia"); Image(systemName:"chevron.right").font(.system(size:9,weight:.semibold)) } }.font(.caption.weight(.medium))
            }
        }.castCard()
    }
    private var sourcesCard: some View {
        VStack(alignment:.leading,spacing:4) {
            HStack { sectionLabel("Scegli la sorgente"); Spacer(); Text("\(cast.sources.count)").font(.caption).foregroundStyle(.tertiary) }.padding(.bottom,10)
            ForEach(Array(cast.sources.enumerated()),id:\.offset) { item in
                Button { cast.choose(item.element) } label: {
                    HStack(spacing:12) {
                        VStack(alignment:.leading,spacing:5) {
                            Text(sourceTitle(item.element)).font(.subheadline.weight(.medium)).lineLimit(3).multilineTextAlignment(.leading)
                            Text(item.element.name ?? "Sorgente").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength:0)
                        sizeBadge(item.element).frame(width:90,alignment:.trailing)
                        Image(systemName:"chevron.right").font(.system(size:10,weight:.semibold)).foregroundStyle(.tertiary)
                    }.padding(.vertical,12).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if item.offset < cast.sources.count-1 { Divider().overlay(.white.opacity(0.03)) }
            }
        }.castCard()
    }
    private var playerCard: some View {
        VStack(spacing:20) {
            HStack { sectionLabel("Sulla tua TV"); Spacer(); Text(cast.playing ? "In riproduzione" : "TV collegata").font(.caption).foregroundStyle(.secondary) }
            VStack(spacing:0) {
                Slider(value:Binding(get:{ min(max(0,cast.position),max(1,cast.duration)) },set:{ cast.position = $0 }),in:0...max(1,cast.duration),onEditingChanged:{ editing in
                    cast.userSeeking = editing
                    if !editing { cast.seek(to:cast.position) }
                }).disabled(cast.duration <= 0)
                HStack { Text(playbackTime(cast.position)); Spacer(); Text(playbackTime(cast.duration)) }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing:36) {
                Button { cast.seek(to:cast.position-30) } label: { Image(systemName:"gobackward.30").font(.system(size:24)).frame(width:48,height:48) }.accessibilityLabel("Indietro di 30 secondi")
                Button { cast.togglePlayback() } label: {
                    Image(systemName:cast.playing ? "pause.fill" : "play.fill").font(.system(size:24,weight:.semibold)).foregroundStyle(CastPalette.background)
                        .frame(width:70,height:70).background(Color.white,in:Circle())
                }.accessibilityLabel(cast.playing ? "Pausa" : "Riprendi")
                Button { cast.seek(to:cast.position+30) } label: { Image(systemName:"goforward.30").font(.system(size:24)).frame(width:48,height:48) }.accessibilityLabel("Avanti di 30 secondi")
            }.foregroundStyle(.white).buttonStyle(.plain)
            HStack(spacing:12) {
                Image(systemName:"speaker.fill").font(.caption2).foregroundStyle(.secondary)
                Slider(value:$cast.volume,in:0...1,onEditingChanged:{ editing in
                    cast.userAdjustingVolume = editing
                    if !editing { cast.setVolume(cast.volume) }
                }).tint(.white.opacity(0.55))
                Image(systemName:"speaker.wave.3.fill").font(.caption2).foregroundStyle(.secondary)
            }
            if cast.deviceMuted {
                Button { cast.unmuteDevice() } label: { Label("Riattiva audio Chromecast",systemImage:"speaker.slash") }.font(.subheadline)
            }
            HStack {
                if !cast.localProcessing { Button("Controlli TV") { cast.openControls() } }
                Spacer()
                Button("Interrompi") { cast.stopPlayback() }
            }.font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }.castCard()
    }
    private func optionsCard(_ media: RDPreparedMedia) -> some View {
        VStack(spacing:0) {
            HStack(spacing:16) {
                Menu {
                    Picker("Audio",selection:Binding(get:{cast.selectedAudio},set:{cast.selectAudio($0)})) {
                        ForEach(media.audio) { Text(trackLabel($0,in:media.audio)).tag($0.key) }
                    }
                } label: { quickTrackLabel("Audio",selection:audioSummary(media),icon:"waveform") }
                Divider().frame(height:40)
                Menu {
                    Picker("Sottotitoli",selection:Binding(get:{cast.selectedSubtitle},set:{cast.selectSubtitle($0)})) {
                        Text("Disattivati").tag("none")
                        if cast.externalSubtitleURL != nil { Text(cast.externalSubtitleLabel + " · esterni").tag("external") }
                        if cast.hasExtractedCaption { Text(cast.embeddedSubtitleLabel).tag("embedded") }
                        ForEach(media.subtitles) { Text(trackLabel($0,in:media.subtitles) + " · nel file").tag($0.key) }
                    }
                    Button { showOnlineSubtitles = true } label: { Label("Stremio e OpenSubtitles",systemImage:"magnifyingglass") }
                    Button { showTrackOptions = true } label: { Label("Sincronizza sottotitoli",systemImage:"clock") }
                } label: { quickTrackLabel("Sottotitoli",selection:subtitleSummary(media),icon:"captions.bubble") }
            }.padding(.vertical,18).id(cast.sourceRevision)
            Button { showTrackOptions = true } label: { optionRow(icon:"slider.horizontal.3",title:"Opzioni tracce",detail:"Sincronizzazione e dettagli") }.buttonStyle(.plain)
            Divider().padding(.leading,38)
            Button { showSubtitleAppearance = true } label: { optionRow(icon:"textformat.size",title:"Aspetto sottotitoli",detail:"Anteprima e preferenze") }.buttonStyle(.plain)
            Divider()
            VStack(alignment:.leading,spacing:6) {
                Text("Sorgente · \(media.videoDescription)")
                Label(cast.processingDetail,systemImage:cast.localProcessing ? "iphone" : "play.tv")
            }.font(.footnote).foregroundStyle(.secondary).padding(.vertical,14).frame(maxWidth:.infinity,alignment:.leading)
        }.padding(.horizontal,20).background(CastPalette.surface,in:RoundedRectangle(cornerRadius:24))
    }
    private var playButton: some View {
        Button { cast.load(preservePosition:cast.hasLoaded) } label: {
            HStack(spacing:9) { Image(systemName:"play.rectangle"); Text(cast.loading ? "Attendo la TV…" : "Riproduci sulla TV") }.font(.subheadline.weight(.semibold)).frame(maxWidth:.infinity).padding(.vertical,17)
        }.buttonStyle(.plain).foregroundStyle(CastPalette.background).background(Color.white,in:RoundedRectangle(cornerRadius:18))
            .opacity(!cast.connected || cast.busy || cast.loading ? 0.45 : 1).disabled(!cast.connected || cast.busy || cast.loading || cast.selectedAudio.isEmpty)
    }
    private func quickTrackLabel(_ title:String,selection:String,icon:String) -> some View {
        VStack(alignment:.leading,spacing:7) {
            Label(title,systemImage:icon).font(.subheadline.weight(.medium))
            HStack(spacing:4) {
                Text(selection).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength:0)
                Image(systemName:"chevron.down").font(.caption2)
            }.font(.caption).foregroundStyle(CastPalette.accent)
        }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
            .accessibilityElement(children:.combine)
    }
    private var emptyState: some View {
        VStack(spacing:16) {
            Image(systemName:"tv").font(.system(size:38,weight:.ultraLight)).foregroundStyle(CastPalette.accent).padding(.top,15)
            VStack(spacing:7) {
                Text("Apri un film da Stremio").font(.headline.weight(.medium))
                Text("La sorgente e i controlli compariranno qui.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }.padding(.vertical,26).frame(maxWidth:.infinity).castCard()
    }
    private func sizeBadge(_ source: AddonStream) -> some View {
        Text(source.fileSizeLabel == "Dimensione non disponibile" ? "Non disponibile" : source.fileSizeLabel)
            .font(.caption.monospacedDigit().weight(.medium)).foregroundStyle(CastPalette.accent).multilineTextAlignment(.trailing).accessibilityLabel("Dimensione: " + source.fileSizeLabel)
    }
    private func optionRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing:14) {
            Image(systemName:icon).font(.system(size:17)).foregroundStyle(.secondary).frame(width:22)
            VStack(alignment:.leading,spacing:4) { Text(title).font(.subheadline.weight(.medium)); Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            Spacer(minLength:4)
            Image(systemName:"chevron.right").font(.system(size:10,weight:.semibold)).foregroundStyle(.tertiary)
        }.padding(.vertical,18).contentShape(Rectangle())
    }
    private func sectionLabel(_ title: String) -> some View { Text(title.uppercased()).font(.system(size:10,weight:.semibold)).tracking(1.3).foregroundStyle(.secondary) }
    private func audioSummary(_ media: RDPreparedMedia) -> String {
        guard let track = media.audio.first(where:{$0.key == cast.selectedAudio}) else {
            return media.audioCodecsDescription.isEmpty ? "Audio del file" : "Audio del file · " + media.audioCodecsDescription
        }
        return trackLanguage(track)
    }
    private func subtitleSummary(_ media: RDPreparedMedia) -> String {
        if cast.selectedSubtitle == "none" { return "Sottotitoli disattivati" }
        if cast.selectedSubtitle == "embedded" { return cast.embeddedSubtitleLabel }
        if cast.selectedSubtitle == "external" { return cast.externalSubtitleLabel }
        return media.subtitles.first(where:{$0.key == cast.selectedSubtitle}).map(trackLanguage) ?? "Sottotitoli"
    }
}

private struct TrackOptionsView: View {
    @EnvironmentObject private var cast: CastController
    @Environment(\.dismiss) private var dismiss
    @State private var showAppearance = false
    @State private var showOnline = false
    var body: some View {
        NavigationStack {
            Form {
                if let media = cast.prepared {
                    Section {
                        Picker("Audio",selection:Binding(get:{cast.selectedAudio},set:{cast.selectAudio($0)})) { ForEach(media.audio) { Text(trackLabel($0,in:media.audio)).tag($0.key) } }
                    } header: { Text("Audio") }
                    Section("Sottotitoli") {
                        Picker("Traccia",selection:Binding(get:{cast.selectedSubtitle},set:{cast.selectSubtitle($0)})) {
                            Text("Disattivati").tag("none")
                            if cast.externalSubtitleURL != nil { Text(cast.externalSubtitleLabel + " · esterni").tag("external") }
                            if cast.hasExtractedCaption { Text(cast.embeddedSubtitleLabel).tag("embedded") }
                            ForEach(media.subtitles) { Text(trackLabel($0,in:media.subtitles) + " · nel file").tag($0.key) }
                        }
                        Button { showAppearance = true } label: { Label("Aspetto e anteprima",systemImage:"textformat.size") }
                        Button { showOnline = true } label: { Label("Scegli da Stremio e OpenSubtitles",systemImage:"captions.bubble") }
                        if cast.supportsOriginalSubtitleStyle,media.subtitles.contains(where:{["ssa","ass"].contains($0.codec.lowercased())}){
                            Toggle("Mantieni lo stile originale della traccia",isOn:Binding(get:{cast.preservesOriginalSubtitleStyle},set:{cast.setOriginalSubtitleStyle($0)}))
                        }
                        if cast.subtitleDownloadBusy { HStack { ProgressView(); Text(cast.subtitlePreparation).font(.footnote) } }
                        if let issue = cast.subtitleIssue {
                            Text(issue).font(.footnote).foregroundStyle(.orange)
                            Button("Riprova sottotitoli"){cast.retryIndependentCaptions()}
                        }
                        if media.subtitles.isEmpty { Text("Nessuna traccia incorporata rilevata.").font(.footnote).foregroundStyle(.secondary) }
                    }
                    if cast.selectedSubtitle != "none" {
                        Section("Sincronizzazione") {
                            SubtitleSyncControls()
                            if cast.loading { Button("Disattiva sottotitoli e riprendi") { cast.disableSubtitlesAndResume() } }
                        }
                    }
                    Section {
                        Label("Formato automatico",systemImage:"wand.and.stars")
                        Text(cast.processingDetail).font(.footnote).foregroundStyle(.secondary)
                    } header: { Text("Riproduzione") } footer: { Text("L’app adatta audio, contenitore e video quando necessario. Durante l’adattamento l’iPhone deve restare collegato alla rete Wi-Fi della TV.") }
                    Section {
                        DisclosureGroup("Dettagli sorgente") {
                            Text(cast.selectedSource?.displayName ?? "Sorgente").font(.caption).textSelection(.enabled)
                            Text(media.videoDescription).font(.caption).foregroundStyle(.secondary)
                            if let source = cast.selectedSource { LabeledContent("Dimensione",value:source.fileSizeLabel) }
                            Button("Esporta sottotitoli dal file") { cast.extractEmbeddedSubtitles() }.disabled(cast.busy || cast.loading)
                            if let file = cast.subtitleFile { ShareLink("Condividi sottotitoli",item:file) }
                        }
                    }
                }
            }.navigationTitle("Audio e sottotitoli").navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge:.bottom) {
                    if !cast.hasLoaded {
                    Button { cast.load(preservePosition:cast.hasLoaded); dismiss() } label: {
                        Text(cast.loading ? "Verifica e caricamento…" : cast.hasLoaded ? "Applica modifiche" : "Riproduci sulla TV").font(.subheadline.weight(.semibold)).frame(maxWidth:.infinity).padding(.vertical,15)
                    }.buttonStyle(.plain).foregroundStyle(.black).background(.white,in:RoundedRectangle(cornerRadius:16))
                        .opacity(!cast.connected || cast.busy || cast.loading ? 0.45 : 1)
                        .disabled(!cast.connected || cast.busy || cast.loading || cast.selectedAudio.isEmpty)
                        .padding(.horizontal,20).padding(.vertical,12).background(.ultraThinMaterial)
                    }
                }
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Chiudi") { dismiss() } } }
        }.preferredColorScheme(.dark).tint(CastPalette.accent)
            .sheet(isPresented:$showAppearance) { SubtitleAppearanceView().environmentObject(cast) }
            .sheet(isPresented:$showOnline) { SubtitleBrowserView().environmentObject(cast) }
            .onChange(of:cast.sourceRevision) { _ in showAppearance = false; showOnline = false; dismiss() }
    }
}

private struct SubtitleSyncControls:View {
    @EnvironmentObject private var cast:CastController
    @State private var draft:Double = 0
    @State private var editing = false
    var body:some View {
        VStack(spacing:14) {
            HStack {
                Button("−0,5 s") { cast.changeSubtitleDelay(cast.subtitleDelay-0.5) }.accessibilityLabel("Anticipa di mezzo secondo")
                Spacer()
                Text(String(format:"%+.1f s",locale:Locale.current,editing ? draft : cast.subtitleDelay)).monospacedDigit()
                Spacer()
                Button("+0,5 s") { cast.changeSubtitleDelay(cast.subtitleDelay+0.5) }.accessibilityLabel("Ritarda di mezzo secondo")
            }.buttonStyle(.borderless)
            Slider(value:$draft,in:-300...300,step:0.5,onEditingChanged:{ active in editing = active; if !active { cast.changeSubtitleDelay(draft) } })
            HStack { Button("−5 s") { cast.changeSubtitleDelay(cast.subtitleDelay-5) }; Spacer(); Button("Azzera") { cast.changeSubtitleDelay(0) }; Spacer(); Button("+5 s") { cast.changeSubtitleDelay(cast.subtitleDelay+5) } }.buttonStyle(.borderless)
            Text("Se il testo arriva dopo la voce, anticipalo con −. Se arriva prima, ritardalo con +. La regolazione resta salvata per questo file e sottotitolo.").font(.footnote).foregroundStyle(.secondary)
        }.onAppear { draft = cast.subtitleDelay }.onChange(of:cast.subtitleDelay) { value in if !editing { draft = value } }
    }
}

private struct SubtitleBrowserView:View {
    @EnvironmentObject private var cast:CastController
    @Environment(\.dismiss) private var dismiss
    @State private var language = "en"
    @State private var query = ""
    @State private var chosenID:String?
    private var languages:[String] { Array(Set(["it","en",cast.defaultSubtitleLanguage]+(cast.onlineSubtitles+cast.sourceSubtitleOptions).map{SubtitleLanguage.code($0.lang)})).filter{!["none","off"].contains($0)}.sorted { SubtitleLanguage.name($0) < SubtitleLanguage.name($1) } }
    private func visible(_ values:[OnlineSubtitle]) -> [OnlineSubtitle] { values.filter{SubtitleLanguage.code($0.lang) == language && (query.isEmpty || ($0.title+" "+$0.detail).localizedCaseInsensitiveContains(query))} }
    var body:some View {
        NavigationStack {
            List {
                Section {
                    Picker("Lingua",selection:$language) { ForEach(languages,id:\.self) { Text(SubtitleLanguage.name($0)).tag($0) } }
                    if let media = cast.prepared { Text("Il tuo video · "+media.videoDescription).font(.footnote).foregroundStyle(.secondary) }
                }
                if !visible(cast.sourceSubtitleOptions).isEmpty {
                    Section("Forniti dalla sorgente Stremio") { ForEach(visible(cast.sourceSubtitleOptions)) { subtitleRow($0) } }
                }
                Section {
                    if cast.subtitleSearchBusy { HStack { ProgressView(); Text("Cerco le versioni disponibili…") } }
                    if let issue = cast.subtitleIssue { Text(issue).font(.footnote).foregroundStyle(.orange) }
                    ForEach(visible(cast.onlineSubtitles)) { subtitleRow($0) }
                    if !cast.subtitleSearchBusy && visible(cast.onlineSubtitles).isEmpty { Text("Nessuna versione in questa lingua. Prova un’altra lingua o aggiorna l’elenco.").font(.footnote).foregroundStyle(.secondary) }
                } header: { Text("OpenSubtitles") } footer: { Text("Lo stesso add-on ufficiale usato da Stremio. Controlla il nome della versione; edizioni diverse possono avere tempi diversi.") }
            }.navigationTitle("Scegli sottotitoli").navigationBarTitleDisplayMode(.inline)
                .searchable(text:$query,prompt:"Cerca versione o gruppo")
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("Chiudi") { dismiss() } }
                    ToolbarItem(placement:.primaryAction) { Button { cast.searchSubtitles(refresh:true) } label: { Image(systemName:"arrow.clockwise") }.disabled(cast.subtitleSearchBusy) }
                }
                .task { let wanted = cast.defaultSubtitleLanguage; language = ["none","off"].contains(wanted) ? "en" : wanted; cast.searchSubtitles() }
                .onChange(of:cast.selectedOnlineSubtitleID) { id in if id == chosenID { dismiss() } }
                .onChange(of:cast.subtitleDownloadBusy) { active in if !active, chosenID != nil, cast.selectedOnlineSubtitleID == chosenID, cast.subtitleIssue == nil { dismiss() } }
        }.preferredColorScheme(.dark).tint(CastPalette.accent)
    }
    private func subtitleRow(_ subtitle:OnlineSubtitle) -> some View {
        Button { chosenID = subtitle.id; cast.pickSubtitle(subtitle) } label: {
            HStack(spacing:12) {
                VStack(alignment:.leading,spacing:5) {
                    Text(subtitle.title).font(.subheadline).foregroundStyle(.primary).lineLimit(3)
                    if !subtitle.detail.isEmpty { Text(subtitle.detail).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                }
                Spacer(minLength:0)
                if cast.subtitleDownloadBusy && chosenID == subtitle.id { ProgressView() }
                else if cast.selectedOnlineSubtitleID == subtitle.id { Image(systemName:"checkmark").foregroundStyle(CastPalette.accent) }
            }.padding(.vertical,5)
        }.buttonStyle(.plain)
    }
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
                Section { Text(cast.setupMessage).font(.subheadline).foregroundStyle(.secondary) }
                Section {
                    SecureField("Collegamento Torrentio",text:$torrentio).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("Collegamento Comet",text:$comet).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                } header: { Text("Sorgenti") } footer: { Text("Usa i collegamenti dei tuoi add-on Real-Debrid. Restano nel portachiavi di questo iPhone. Lascia vuoto un campo per mantenere quello salvato.") }
                Section {
                    DisclosureGroup("Servizio per i sottotitoli estratti") {
                        TextField("Indirizzo HTTPS",text:$subtitleEndpoint).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        SecureField("Chiave del servizio",text:$subtitleToken).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text("Facoltativo. Rende il testo estratto disponibile alla TV anche con l’iPhone bloccato. Riceve solo i sottotitoli; il collegamento al film resta sull’iPhone.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }.navigationTitle("Sorgenti").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("Chiudi") { dismiss() } }
                    ToolbarItem(placement:.confirmationAction) {
                        Button("Salva") {
                            if cast.saveConfigurations(torrentio:torrentio,comet:comet,subtitleEndpoint:subtitleEndpoint,subtitleToken:subtitleToken) { torrentio = ""; comet = ""; dismiss() }
                        }.fontWeight(.semibold)
                    }
                }
        }.preferredColorScheme(.dark).tint(CastPalette.accent)
    }
}

private extension View {
    func castCard() -> some View {
        padding(20).frame(maxWidth:.infinity,alignment:.leading).background(CastPalette.surface,in:RoundedRectangle(cornerRadius:24))
            .overlay(RoundedRectangle(cornerRadius:24).strokeBorder(.white.opacity(0.035),lineWidth:1))
    }
}
private func sourceTitle(_ source: AddonStream) -> String { MediaDisplayTitle.clean(source.filename ?? source.descriptionText.components(separatedBy:.newlines).first(where:{!$0.isEmpty}) ?? source.name ?? "Sorgente") }
private func trackLanguage(_ track: RDTrack) -> String { track.language == "und" ? "Lingua non indicata" : (Locale(identifier:"it").localizedString(forLanguageCode:PlaybackPreferences.language(track.language)) ?? track.label).capitalized }
private func trackLabel(_ track: RDTrack, in tracks: [RDTrack]) -> String {
    let codec = track.channels.map { $0 > 2 ? " · Surround" : $0 == 1 ? " · Mono" : " · Stereo" } ?? ""
    let duplicates = tracks.filter{PlaybackPreferences.language($0.language) == PlaybackPreferences.language(track.language) && $0.channels == track.channels}
    let index = duplicates.count > 1 ? " · Traccia \((tracks.firstIndex(of:track) ?? 0)+1)" : ""
    return trackLanguage(track) + codec + index
}
private func qualityName(_ quality: RDQuality) -> String { switch quality { case .medium: return "720p"; case .high: return "1080p"; case .original: return "Originale" } }
private func playbackTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let n = Int(seconds)
    return n >= 3600 ? String(format:"%d:%02d:%02d",n/3600,(n/60)%60,n%60) : String(format:"%d:%02d",n/60,n%60)
}


