import ActivityKit
import WidgetKit
import SwiftUI
@main
struct CastLiveActivity: Widget {
 var body: some WidgetConfiguration {
  ActivityConfiguration(for: CastActivityAttributes.self) { context in
   HStack { Image(systemName: "tv"); VStack(alignment: .leading) { Text(context.attributes.title).font(.headline); Text(context.state.status).font(.subheadline) }; Spacer() }.padding()
  } dynamicIsland: { context in
   DynamicIsland {
    DynamicIslandExpandedRegion(.leading) { Image(systemName: "tv") }
    DynamicIslandExpandedRegion(.center) { Text(context.attributes.title) }
    DynamicIslandExpandedRegion(.bottom) { Text(context.state.status) }
   } compactLeading: { Image(systemName: "tv") } compactTrailing: { Text("Test") } minimal: { Image(systemName: "tv") }
  }
 }
}
