import Foundation
import Network
import Security
import CryptoKit
import ActivityKit



/// All mutable socket state is confined to one serial queue. A connection lives
/// only for a command; it is never used to stream video or keep iOS awake.
final class CastCommandSocket: @unchecked Sendable {
    private let queue = DispatchQueue(label:"app.castbridge.command")
    private let source = "sender-castbridge-" + UUID().uuidString
    private let host: String
    private let pin: String?
    private var connection: NWConnection?
    private var buffer = Data()
    private var serial = 1
    private var opening: CheckedContinuation<String,Error>?
    private var pending: [Int:CheckedContinuation<[String:Any],Error>] = [:]
    private var fingerprint: String?
    init(host: String, pin: String?) { self.host = host; self.pin = pin }
    func connect() async throws -> String {
        guard CastWire.localIPv4(host) else { throw CastDirectError.invalid }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.opening = continuation
                let tls = NWProtocolTLS.Options()
                sec_protocol_options_set_verify_block(tls.securityProtocolOptions,{ [weak self] _, trust, complete in
                    guard let self else { complete(false); return }
                    let reference = sec_trust_copy_ref(trust).takeRetainedValue()
                    guard let chain = SecTrustCopyCertificateChain(reference) as? [SecCertificate], let certificate = chain.first else { complete(false); return }
                    let bytes = SecCertificateCopyData(certificate) as Data
                    let hash = SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
                    // First-use capture happens only while Google's SDK is
                    // connected to the device explicitly selected by the user.
                    guard self.pin == nil || self.pin == hash else { complete(false); return }
                    self.fingerprint = hash; complete(true)
                },self.queue)
                let connection = NWConnection(host:NWEndpoint.Host(self.host),port:8009,using:NWParameters(tls:tls,tcp:NWProtocolTCP.Options()))
                self.connection = connection
                connection.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        guard let pin = self.fingerprint else { self.fail(CastDirectError.certificate); return }
                        let continuation = self.opening; self.opening = nil
                        self.send(["type":"CONNECT","origin":[:]],namespace:CastWire.connection,to:"receiver-0")
                        self.receive(); continuation?.resume(returning:pin)
                    case .failed, .cancelled: self.fail(CastDirectError.unavailable)
                    default: break
                    }
                }
                connection.start(queue:self.queue)
                self.queue.asyncAfter(deadline:.now()+6) { if self.opening != nil { self.fail(CastDirectError.timeout) } }
            }
        }
    }
    func close() { queue.async { self.fail(CastDirectError.unavailable) } }
    private func fail(_ error: Error) {
        let opening = self.opening; self.opening = nil; opening?.resume(throwing:error)
        let waiting = pending; pending.removeAll(); waiting.values.forEach{$0.resume(throwing:error)}
        connection?.stateUpdateHandler = nil; connection?.cancel(); connection = nil
    }
    func join(_ destination: String) async {
        await withCheckedContinuation { done in queue.async { self.send(["type":"CONNECT","origin":[:]],namespace:CastWire.connection,to:destination); done.resume() } }
    }
    func request(_ body: [String:Any], namespace: String, destination: String = "receiver-0") async throws -> [String:Any] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.connection != nil else { continuation.resume(throwing:CastDirectError.unavailable); return }
                let id = self.serial; self.serial += 1
                self.pending[id] = continuation
                var body = body; body["requestId"] = id
                self.send(body,namespace:namespace,to:destination)
                self.queue.asyncAfter(deadline:.now()+4) { self.pending.removeValue(forKey:id)?.resume(throwing:CastDirectError.timeout) }
            }
        }
    }
    private func send(_ body: [String:Any], namespace: String, to: String) {
        do {
            let data = try CastWire.encode(source:source,destination:to,namespace:namespace,body:body)
            connection?.send(content:data,completion:.contentProcessed{[weak self] error in if let error { self?.fail(error) }})
        } catch { fail(error) }
    }
    private func receive() {
        connection?.receive(minimumIncompleteLength:1,maximumLength:65536) { [weak self] data,_,complete,error in
            guard let self else { return }
            if let data { self.buffer.append(data) }
            do {
                while self.buffer.count >= 4 {
                    let length = self.buffer.prefix(4).reduce(0){($0 << 8)|Int($1)}
                    guard length > 0, length <= 1_048_576 else { throw CastDirectError.invalid }
                    guard self.buffer.count >= length+4 else { break }
                    let frame = Data(self.buffer.dropFirst(4).prefix(length)); self.buffer = Data(self.buffer.dropFirst(length+4))
                    let (source,ns,body) = try CastWire.decode(frame)
                    if ns == CastWire.heartbeat && body["type"] as? String == "PING" { self.send(["type":"PONG"],namespace:ns,to:source) }
                    else if let id = body["requestId"] as? Int, let continuation = self.pending.removeValue(forKey:id) { continuation.resume(returning:body) }
                }
            } catch { self.fail(error); return }
            if complete || error != nil { self.fail(CastDirectError.unavailable) } else { self.receive() }
        }
    }
}

@MainActor enum CastDirectControl {
    struct Context: Codable { let host: String; let pin: String; let contentDigest: String; let storedAt: Date }
    private static let key = "cast.direct.context"
    private static var busy = false
    static func capture(host: String, contentDigest: String) async throws {
        let socket = CastCommandSocket(host:host,pin:nil)
        defer { socket.close() }
        let pin = try await socket.connect()
        try Task.checkCancellation()
        let data = try JSONEncoder().encode(Context(host:host,pin:pin,contentDigest:contentDigest,storedAt:Date()))
        UserDefaults.standard.set(data,forKey:key)
    }
    static func clear() { UserDefaults.standard.removeObject(forKey:key) }
    static func perform(_ command: String,offset:Double = 0,originalDuration:Double? = nil,onStatus:((Double,Double,Bool)->Void)? = nil) async -> Bool {
        guard !busy, let data = UserDefaults.standard.data(forKey:key),
              let ctx = try? JSONDecoder().decode(Context.self,from:data), Date().timeIntervalSince(ctx.storedAt) < 86400 else { return false }
        busy = true; defer { busy = false }
        let socket = CastCommandSocket(host:ctx.host,pin:ctx.pin)
        defer { socket.close() }
        do {
            _ = try await socket.connect()
            let receiver = try await socket.request(["type":"GET_STATUS"],namespace:CastWire.receiver)
            guard let status = receiver["status"] as? [String:Any], let apps = status["applications"] as? [[String:Any]],
                  let app = apps.first(where:{$0["appId"] as? String == "CC1AD845"}), let transport = app["transportId"] as? String else { return false }
            await socket.join(transport)
            let response = try await socket.request(["type":"GET_STATUS"],namespace:CastWire.media,destination:transport)
            guard let mediaStatus = (response["status"] as? [[String:Any]])?.first, let media = mediaStatus["media"] as? [String:Any],
                  let session = mediaStatus["mediaSessionId"] as? Int,
                  [media["contentUrl"] as? String,media["contentId"] as? String].compactMap({$0}).contains(where:{CastWire.digest($0) == ctx.contentDigest}) else { throw CastDirectError.differentMedia }
            let current = (mediaStatus["currentTime"] as? NSNumber)?.doubleValue ?? 0
            let duration = (media["duration"] as? NSNumber)?.doubleValue ?? 0
            var body: [String:Any] = ["mediaSessionId":session]
            if command == "toggle" { body["type"] = mediaStatus["playerState"] as? String == "PLAYING" ? "PAUSE" : "PLAY" }
            else if ["play","pause","stop"].contains(command) { body["type"] = command.uppercased() }
            else if let target = CastWire.seekTarget(command,current:current,duration:duration) { body["type"] = "SEEK"; body["currentTime"] = target }
            else { return false }
            let result = try await socket.request(body,namespace:CastWire.media,destination:transport)
            guard result["type"] as? String == "MEDIA_STATUS", let actual = (result["status"] as? [[String:Any]])?.first else { return false }
            let actualPosition = ((actual["currentTime"] as? NSNumber)?.doubleValue ?? current) + offset
            let actualDuration = originalDuration ?? (((actual["media"] as? [String:Any])?["duration"] as? NSNumber)?.doubleValue ?? duration)
            let playing = actual["playerState"] as? String == "PLAYING"
            onStatus?(actualPosition,actualDuration,playing)
            for activity in Activity<CastActivityAttributes>.activities {
                let state = CastActivityAttributes.ContentState(status:playing ? "In riproduzione" : "In pausa",playing:playing,position:actualPosition,duration:actualDuration,updatedAt:Date())
                if #available(iOS 16.2, *) { await activity.update(ActivityContent(state:state,staleDate:Date().addingTimeInterval(60))) }
                else { await activity.update(using:state) }
            }
            if let positionKey = UserDefaults.standard.string(forKey:"cast.session.positionKey") { UserDefaults.standard.set(actualPosition,forKey:positionKey) }
            return true
        } catch { return false }
    }
}
