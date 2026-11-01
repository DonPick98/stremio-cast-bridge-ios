import Foundation
import CryptoKit

/// The resume point belongs to the film/episode, independently of the file,
/// quality, torrent, add-on or expiring download link selected for it.
struct PlaybackContent: Equatable {
    let type: String
    let id: String
    var positionKey: String {
        let digest = SHA256.hash(data:Data((type + "|" + id).utf8)).map { String(format:"%02x",$0) }.joined()
        return "cast.position.content." + digest
    }
}

/// A cancelled preparation must never publish progress or errors into its successor.
struct PlaybackRequestState {
    private(set) var generation = UUID()
    mutating func invalidate() { generation = UUID() }
    func accepts(_ value: UUID) -> Bool { value == generation }
}

struct PlaybackIntent {
    private(set) var pending: Bool?
    mutating func request(_ playing:Bool) { pending = playing }
    mutating func accepts(_ playing:Bool) -> Bool {
        if let pending, pending != playing { return false }
        pending = nil; return true
    }
    mutating func reset() { pending = nil }
}

/// Keep the requested original-media position until the receiver confirms it.
/// An old status or a zero position during LOAD is not a seek confirmation.
struct PlaybackTimeline {
    private(set) var target: Double?
    private(set) var queuedTarget: Double?
    mutating func queue(at value:Double) { if value.isFinite { queuedTarget = max(0,value) } }
    mutating func consumeQueued() -> Double? { let value = queuedTarget; queuedTarget = nil; return value }
    mutating func cancelActive() { target = nil }
    mutating func begin(at value: Double) {
        guard value.isFinite else { return }
        target = max(0,value)
    }
    mutating func observe(_ value: Double, ready: Bool) -> Bool {
        guard ready, value.isFinite, value >= 0 else { return false }
        if let target {
            guard abs(value-target) <= 3 else { return false }
            self.target = nil
        }
        return true
    }
    mutating func reset() { target = nil; queuedTarget = nil }
}
