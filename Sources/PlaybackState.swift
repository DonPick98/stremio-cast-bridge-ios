import Foundation
import CryptoKit

enum PlaybackResume {
    static func validated(_ value:Double,duration:Double) -> Double {
        guard value.isFinite, value > 0 else { return 0 }
        guard duration.isFinite, duration > 0 else { return value }
        // An out-of-range or completed resume must restart, never clamp to
        // the final second and generate an unplayably short replacement stream.
        guard value < max(0,duration-min(10,duration*0.02)) else { return 0 }
        return value
    }
}

enum PlaybackReadiness {
    static func progressed(actual:Double,start:Double,paused:Bool) -> Bool {
        paused || (actual.isFinite && start.isFinite && actual >= start+0.25)
    }
}

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

/// A trailing-edge debounce. A newer tap invalidates both the old timer and
/// its eventual transport/preparation completion, even after dispatch.
struct PlaybackSeekIntent {
    private(set) var generation = UUID()
    private var deadline:TimeInterval = 0
    private(set) var pending = false
    mutating func submit(now:TimeInterval) {
        generation=UUID();deadline=now+0.3;pending=true
    }
    func accepts(_ token:UUID)->Bool {token==generation}
    func delay(for token:UUID,now:TimeInterval)->TimeInterval? {
        guard accepts(token),pending,now.isFinite else{return nil}
        return max(0,min(0.3,deadline-now))
    }
    mutating func dispatched(_ token:UUID) {
        guard accepts(token) else{return};pending=false
    }
    mutating func cancel() {generation=UUID();pending=false}
}

/// The receiver's relative clock belongs to its LOAD, not to the lifetime of
/// the local encoder. Releasing an encoder must not erase this mapping.
struct ReceiverPlaybackClock {
    private(set) var offset:Double = 0
    mutating func load(offset:Double) {
        self.offset=offset.isFinite ? max(0,offset):0
    }
    func capture(relative:Double,loaded:Bool,suspended:Bool)->Double? {
        guard loaded,!suspended,relative.isFinite,relative>=0 else{return nil}
        let original=relative+offset
        return original.isFinite ? original:nil
    }
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

/// Recovery intent survives a disconnected Cast socket. Only an actual start
/// consumes a retry; repeated callbacks for the same outage coalesce.
struct PlaybackRecoveryState {
    private(set) var pending = false
    private(set) var attempts = 0
    let limit = 2
    func retrySameProducer(mode:String,code:Int64?)->Bool {
        // AVERROR_EXTERNAL identifies a backend failure, not a receiver codec
        // rejection. Allow one fresh H264 producer before changing formats.
        attempts==0 && !pending && mode=="ffmpegH264" && code == -542398533
    }
    mutating func request() -> Bool {
        guard attempts < limit else { return false }
        pending = true; return true
    }
    mutating func begin(connected:Bool, blocked:Bool) -> Bool {
        guard pending, connected, !blocked, attempts < limit else { return false }
        pending = false; attempts += 1; return true
    }
    mutating func reset() { pending = false; attempts = 0 }
}

enum PlaybackCompletion {
    static func detachedEnd(finished:Bool,hasLoaded:Bool,pending:Bool,informationPresent:Bool,currentSession:Int,lastSession:Int?) -> Bool {
        guard let lastSession,lastSession>0 else { return false }
        return finished && hasLoaded && !pending && !informationPresent && currentSession==lastSession
    }
}

/// Receiver state acknowledgements do not reset a stall unless its actual
/// media clock advances. User pauses and new timelines explicitly reset it.
struct PlaybackProgressMonitor {
    private var lastPosition:Double?
    private var lastProgress:Date?
    private var healthySince:Date?
    private(set) var stable = false
    mutating func observe(position:Double, now:Date, expectedToAdvance:Bool) -> Bool {
        guard expectedToAdvance, position.isFinite, position >= 0 else { reset(); return false }
        guard let previous = lastPosition, let progress = lastProgress else {
            lastPosition = position; lastProgress = now; healthySince = now; return false
        }
        if position < previous - 3 { reset(); return observe(position:position,now:now,expectedToAdvance:true) }
        if position >= previous + 0.25 {
            if now.timeIntervalSince(progress) > 5 { healthySince = now }
            lastPosition = position; lastProgress = now
            stable = now.timeIntervalSince(healthySince ?? now) >= 15
            return false
        }
        if now.timeIntervalSince(progress) > 5 { healthySince = nil; stable = false }
        return now.timeIntervalSince(progress) >= 20
    }
    mutating func reset() { lastPosition = nil; lastProgress = nil; healthySince = nil; stable = false }
}

/// Keep the requested original-media position until the receiver confirms it.
/// An old status or a zero position during LOAD is not a seek confirmation.
struct PlaybackTimeline {
    private(set) var target: Double?
    private(set) var queuedTarget: Double?
    mutating func queue(at value:Double) { if value.isFinite { queuedTarget = max(0,value) } }
    mutating func consumeQueued() -> Double? { let value = queuedTarget; queuedTarget = nil; return value }
    mutating func cancelActive() { target = nil }
    func restoring(_ checkpoint:PlaybackTimeline) -> PlaybackTimeline {
        var restored=checkpoint
        // The failed replacement never reached its requested position. Accept
        // the previous receiver clock again, retaining only newer queued intent.
        restored.target=nil
        restored.queuedTarget=queuedTarget ?? checkpoint.queuedTarget
        return restored
    }
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


/// Throttle timer refreshes while immediately publishing state/title changes or
/// a real clock discontinuity. This does not keep the app executing in background.
struct LiveActivityUpdatePolicy {
    private struct Signature:Equatable {
        let title:String,status:String
        let playing:Bool
        let duration:Double,step:Double
    }
    private var signature:Signature?
    private var at:Date?
    private var position:Double=0
    private var playing=false
    mutating func accept(title:String,status:String,playing:Bool,position:Double,duration:Double,step:Double,now:Date)->Bool {
        guard position.isFinite,position>=0,duration.isFinite,duration>=0 else{return false}
        let key=Signature(title:title,status:status,playing:playing,duration:duration,step:step)
        let elapsed=at.map{max(0,now.timeIntervalSince($0))} ?? .infinity
        let expected=self.position+(self.playing && elapsed.isFinite ? elapsed:0)
        guard signature != key || elapsed>=30 || abs(position-expected)>3 else{return false}
        signature=key;at=now;self.position=position;self.playing=playing;return true
    }
}

/// Count confirmed delivery per segment, not the furthest absolute media time.
/// Replaying adds real work; a seek itself never earns completed units.
struct BackgroundPlaybackWork {
    private(set) var active=false
    private(set) var total:Int64=1
    private(set) var completed:Int64=0
    private var last:Double=0
    private var duration:Double=0
    private var delivered:Double=0
    mutating func begin(duration:Double,position:Double)->Bool {
        guard !active,duration.isFinite,duration>0,duration<=7*24*3600,
              position.isFinite,position>=0,position<duration else{return false}
        self.duration=duration;last=position;delivered=0
        total=max(1,Int64((duration-position)*1000));completed=0;active=true
        return true
    }
    mutating func rebase(duration:Double,position:Double) {
        guard active,duration.isFinite,duration>0,duration<=7*24*3600,
              position.isFinite,position>=0,position<duration else{return}
        self.duration=duration;last=position
        total=completed+max(1,Int64((duration-position)*1000))
    }
    mutating func update(position:Double?) {
        guard active,let position,position.isFinite,position>=last else{return}
        let current=min(duration,position)
        delivered=min(9_000_000_000,delivered+max(0,current-last));last=current
        // Completion is owned by the receiver's natural-end event, not a seek.
        completed=max(completed,min(total-1,Int64(delivered*1000)))
    }
    mutating func finish(){active=false}
}

/// iOS extrapolates the media clock. Health polling remains independent; only
/// redundant Now Playing IPC is coalesced between real transport changes.
struct SystemMediaPublishPolicy {
    private struct State:Equatable {
        let title:String,device:String
        let playing:Bool,loading:Bool,local:Bool,foreground:Bool
        let duration:Double,step:Double
    }
    private var previous:State?
    private var at:Date?
    private var position:Double=0
    mutating func reset(){previous=nil;at=nil}
    mutating func accept(title:String,device:String,position:Double,duration:Double,playing:Bool,loading:Bool,local:Bool,step:Double,foreground:Bool,now:Date)->Bool {
        guard position.isFinite,duration.isFinite,position>=0,duration>=0 else{return false}
        let next=State(title:title,device:device,playing:playing,loading:loading,local:local,foreground:foreground,duration:duration,step:step)
        let elapsed=at.map{now.timeIntervalSince($0)} ?? .infinity
        let running=previous.map{$0.playing && !$0.loading} ?? false
        var expected=self.position+(running && elapsed.isFinite ? max(0,elapsed):0)
        if let previous,previous.duration>0 {expected=min(expected,previous.duration)}
        let jump=abs(position-expected)>(running ? 1:0.05)
        let changed=previous != next
        let interval:Double=foreground ? 2:10
        guard changed || elapsed<0 || jump || (playing && !loading && elapsed>=interval) else{return false}
        previous=next;at=now;self.position=position;return true
    }
}

