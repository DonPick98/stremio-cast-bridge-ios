import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

@main
struct CastLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CastActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Text(context.attributes.title).font(.headline).lineLimit(1)
                Text(isStale(context) ? "Stato non aggiornato · apri Cast Bridge" : context.state.status).font(.subheadline)
                Text("Aggiornato \(context.state.updatedAt, style: .relative) fa").font(.caption2)
                if context.state.duration > 0 {
                    ProgressView(value: min(max(0, context.state.position), context.state.duration), total: context.state.duration)
                }
                if #available(iOS 17.0, *) {
                    HStack {
                        Button(intent: CastBackIntent()) { Image(systemName: "gobackward.30") }
                        Spacer()
                        Button(intent: CastToggleIntent()) { Image(systemName: context.state.playing ? "pause.fill" : "play.fill") }
                        Spacer()
                        Button(intent: CastForwardIntent()) { Image(systemName: "goforward.30") }
                    }.buttonStyle(.plain)
                }
                Link("Apri Cast Bridge", destination: URL(string: "stremiocast://controls")!).font(.caption)
            }.padding()
             .widgetURL(URL(string: "stremiocast://controls"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "tv") }
                DynamicIslandExpandedRegion(.center) { Text(context.attributes.title).lineLimit(1) }
                DynamicIslandExpandedRegion(.bottom) { Text(isStale(context) ? "Stato non aggiornato" : context.state.status) }
            } compactLeading: { Image(systemName: "tv") }
              compactTrailing: { Image(systemName: isStale(context) ? "questionmark" : (context.state.playing ? "play.fill" : "pause.fill")) }
              minimal: { Image(systemName: "tv") }
        }
    }

    private func isStale(_ context: ActivityViewContext<CastActivityAttributes>) -> Bool {
        if #available(iOS 16.2, *) { return context.isStale }
        return Date().timeIntervalSince(context.state.updatedAt) >= 60
    }
}
