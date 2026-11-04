import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

@main
struct CastLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CastActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Text((context.state.title ?? context.attributes.title)).font(.headline).lineLimit(1)
                Text(isStale(context) ? "Stato non aggiornato · apri Cast Bridge" : context.state.status).font(.subheadline)
                timeline(context)
                if #available(iOS 17.0, *) {
                    HStack {
                        Button(intent: CastBackIntent()) { Label("\(context.state.skipSeconds ?? 30)s",systemImage:"gobackward") }
                        Spacer()
                        Button(intent: CastToggleIntent()) { Image(systemName: context.state.playing ? "pause.fill" : "play.fill") }
                        Spacer()
                        Button(intent: CastForwardIntent()) { Label("\(context.state.skipSeconds ?? 30)s",systemImage:"goforward") }
                    }.buttonStyle(.plain)
                }
                Link("Apri Cast Bridge", destination: URL(string: "stremiocast://controls")!).font(.caption)
            }.padding()
             .widgetURL(URL(string: "stremiocast://controls"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "tv") }
                DynamicIslandExpandedRegion(.center) { Text((context.state.title ?? context.attributes.title)).lineLimit(1) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing:6) {
                        Text(isStale(context) ? "Ultima posizione nota" : context.state.status).font(.caption)
                        timeline(context)
                        if #available(iOS 17.0, *) {
                            HStack {
                                Button(intent:CastBackIntent()) { Label("\(context.state.skipSeconds ?? 30)s",systemImage:"gobackward") }
                                Spacer()
                                Button(intent:CastToggleIntent()) { Image(systemName:context.state.playing ? "pause.fill" : "play.fill") }
                                Spacer()
                                Button(intent:CastForwardIntent()) { Label("\(context.state.skipSeconds ?? 30)s",systemImage:"goforward") }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            } compactLeading: { Image(systemName: "tv") }
              compactTrailing: { Image(systemName: isStale(context) ? "questionmark" : (context.state.playing ? "play.fill" : "pause.fill")) }
              minimal: { Image(systemName: "tv") }
        }
    }

    @ViewBuilder private func timeline(_ context: ActivityViewContext<CastActivityAttributes>) -> some View {
        let state = context.state
        let position = max(0,min(state.position,state.duration > 0 ? state.duration : state.position))
        let start = state.updatedAt.addingTimeInterval(-position)
        let end = start.addingTimeInterval(max(1,state.duration))
        let advancing = state.playing && !isStale(context) && state.duration > position
        VStack(spacing:4) {
            if state.duration > 0 {
                if advancing { ProgressView(timerInterval:start...end,countsDown:false).labelsHidden() }
                else { ProgressView(value:position,total:state.duration) }

            }
            HStack {
                if advancing { Text(timerInterval:start...end,countsDown:false).monospacedDigit() }
                else { Text(time(position)).monospacedDigit() }
                Spacer()
                Text(state.duration > 0 ? time(state.duration) : "Durata non disponibile").monospacedDigit()
            }.font(.caption)
            if isStale(context) { Text("Posizione non aggiornata · apri Cast Bridge").font(.caption2) }
        }
    }
    private func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let n = Int(seconds)
        return n >= 3600 ? String(format:"%d:%02d:%02d",n/3600,(n/60)%60,n%60) : String(format:"%d:%02d",n/60,n%60)
    }

    private func isStale(_ context: ActivityViewContext<CastActivityAttributes>) -> Bool {
        if #available(iOS 16.2, *) { return context.isStale }
        return Date().timeIntervalSince(context.state.updatedAt) >= 60
    }
}
