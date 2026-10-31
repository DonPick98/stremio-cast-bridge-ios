import ActivityKit
import Foundation
import AppIntents

struct CastActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var playing: Bool
        var position: Double
        var duration: Double
        var updatedAt: Date
    }
    var title: String
}

@MainActor enum CastActivityCommands {
    static var handler: ((String) async -> Bool)?
    static func send(_ command: String) async -> Bool {
        for _ in 0..<20 {
            if let handler { return await handler(command) }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }
    static func perform(_ command: String) async {
        guard await send(command) else {
            for activity in Activity<CastActivityAttributes>.activities {
                var state = activity.contentState
                state.status = "Apri Cast Bridge per riconnettere"
                state.updatedAt = Date()
                if #available(iOS 16.2, *) {
                    await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(60)))
                } else { await activity.update(using: state) }
            }
            return
        }
    }
}

@available(iOS 17.0, *)
struct CastToggleIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Riproduci o metti in pausa"
    static var openAppWhenRun: Bool = false
    func perform() async throws -> some IntentResult {
        await CastActivityCommands.perform("toggle")
        return .result()
    }
}
@available(iOS 17.0, *)
struct CastBackIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Indietro di 30 secondi"
    static var openAppWhenRun: Bool = false
    func perform() async throws -> some IntentResult {
        await CastActivityCommands.perform("back")
        return .result()
    }
}
@available(iOS 17.0, *)
struct CastForwardIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Avanti di 30 secondi"
    static var openAppWhenRun: Bool = false
    func perform() async throws -> some IntentResult {
        await CastActivityCommands.perform("forward")
        return .result()
    }
}
