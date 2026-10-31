import ActivityKit
struct CastActivityAttributes: ActivityAttributes {
 struct ContentState: Codable, Hashable { var status: String }
 var title: String
}
