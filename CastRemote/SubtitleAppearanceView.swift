import SwiftUI
import GoogleCast

extension SubtitleAppearance {
    var textColor: Color {
        switch color { case "yellow": return .yellow; case "cyan": return .cyan; case "green": return .green; default: return .white }
    }
    var castStyle: GCKMediaTextTrackStyle {
        let style = GCKMediaTextTrackStyle()
        style.fontScale = CGFloat(scale)
        style.foregroundColor = GCKColor(uiColor:UIColor(textColor))
        style.backgroundColor = GCKColor(red:0,green:0,blue:0,alpha:CGFloat(background))
        style.edgeType = outline ? .outline : .none
        style.edgeColor = GCKColor(red:0,green:0,blue:0,alpha:1)
        style.fontFamily = font == "serif" ? "Georgia" : font == "mono" ? "Courier New" : "Arial"
        return style
    }
}

struct SubtitleAppearanceView: View {
    @EnvironmentObject private var cast: CastController
    @Environment(\.dismiss) private var dismiss
    @State private var settings = SubtitleAppearance.load()
    var body: some View {
        NavigationStack {
            Form {
                Section("Anteprima") {
                    ZStack(alignment:.bottom) {
                        LinearGradient(colors:[.indigo.opacity(0.5),.black],startPoint:.topLeading,endPoint:.bottomTrailing)
                        Image(systemName:"mountain.2.fill").font(.system(size:65)).foregroundStyle(.gray.opacity(0.25)).frame(maxHeight:.infinity)
                        Text("Il viaggio continua.\nThe journey continues.")
                            .font(.system(size:18*settings.scale,design:settings.font == "mono" ? .monospaced : settings.font == "serif" ? .serif : .default))
                            .multilineTextAlignment(.center).foregroundStyle(settings.textColor)
                            .padding(.horizontal,6).padding(.vertical,3)
                            .background(.black.opacity(settings.background))
                            .shadow(color:settings.outline ? .black : .clear,radius:1,x:1,y:1)
                            .padding(.bottom,16)
                    }.frame(height:185).clipShape(RoundedRectangle(cornerRadius:12))
                    Text("Anteprima indicativa: il carattere finale dipende dal Chromecast.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Aspetto") {
                    HStack { Text("Dimensione"); Spacer(); Text("\(Int(settings.scale*100))%").monospacedDigit() }
                    Slider(value:$settings.scale,in:0.6...2,step:0.05)
                    Picker("Colore",selection:$settings.color) {
                        Text("Bianco").tag("white"); Text("Giallo").tag("yellow"); Text("Ciano").tag("cyan"); Text("Verde").tag("green")
                    }
                    Picker("Carattere",selection:$settings.font) { Text("Semplice").tag("sans"); Text("Con grazie").tag("serif"); Text("Monospazio").tag("mono") }
                    Toggle("Contorno nero",isOn:$settings.outline)
                    Text("Sfondo nero · \(Int(settings.background*100))%")
                    Slider(value:$settings.background,in:0...1,step:0.05)
                    Button("Ripristina predefiniti") { settings = SubtitleAppearance() }
                }
                Section {
                    Text("Le preferenze si salvano automaticamente e vengono applicate alle prossime sessioni. Puoi modificarle anche durante il video.")
                    Text("Funziona con i sottotitoli esterni. Il testo già impresso nell’immagine non può essere modificato.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Aspetto sottotitoli")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Fine") { dismiss() } } }
                .onChange(of:settings) { value in value.save(); cast.applySubtitleAppearance() }
        }
    }
}

