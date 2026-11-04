import Foundation
import CryptoKit

enum CastDirectError: Error { case unavailable, invalid, timeout, certificate, differentMedia }

enum CastWire {
    static let connection = "urn:x-cast:com.google.cast.tp.connection"
    static let heartbeat = "urn:x-cast:com.google.cast.tp.heartbeat"
    static let receiver = "urn:x-cast:com.google.cast.receiver"
    static let media = "urn:x-cast:com.google.cast.media"
    static func varint(_ value: Int) -> Data {
        var v = value, out = Data()
        repeat { out.append(UInt8(v & 127) | (v > 127 ? 128 : 0)); v >>= 7 } while v > 0
        return out
    }
    static func field(_ n: Int, _ text: String) -> Data {
        let bytes = Data(text.utf8)
        return varint(n*8+2) + varint(bytes.count) + bytes
    }
    static func encode(source: String, destination: String, namespace: String, body: [String:Any]) throws -> Data {
        let json = try JSONSerialization.data(withJSONObject:body)
        let payload = Data([8,0]) + field(2,source) + field(3,destination) + field(4,namespace) + Data([40,0]) + field(6,String(decoding:json,as:UTF8.self))
        guard payload.count <= 1_048_576 else { throw CastDirectError.invalid }
        let n = UInt32(payload.count)
        return Data([UInt8(n >> 24),UInt8((n >> 16)&255),UInt8((n >> 8)&255),UInt8(n&255)]) + payload
    }
    static func decode(_ data: Data) throws -> (String,String,[String:Any]) {
        let b = Array(data); var p = 0, fields: [Int:String] = [:]
        func integer() throws -> Int {
            var n = 0, shift = 0
            while p < b.count && shift <= 49 {
                let byte = b[p]; p += 1; n |= Int(byte&127) << shift
                if byte&128 == 0 { return n }; shift += 7
            }
            throw CastDirectError.invalid
        }
        while p < b.count {
            let tag = try integer(), type = tag&7, field = tag >> 3
            if type == 0 { _ = try integer() }
            else if type == 2 {
                let n = try integer(); guard n >= 0, n <= b.count-p else { throw CastDirectError.invalid }
                fields[field] = String(decoding:b[p..<p+n],as:UTF8.self); p += n
            } else { throw CastDirectError.invalid }
        }
        guard let source = fields[2], let ns = fields[4], let json = fields[6]?.data(using:.utf8),
              let body = try JSONSerialization.jsonObject(with:json) as? [String:Any] else { throw CastDirectError.invalid }
        return (source,ns,body)
    }
    static func digest(_ value: String) -> String { SHA256.hash(data:Data(value.utf8)).map{String(format:"%02x",$0)}.joined() }
    static func localIPv4(_ host: String) -> Bool {
        let p = host.split(separator:".").compactMap{Int($0)}
        guard p.count == 4, p.allSatisfy({(0...255).contains($0)}) else { return false }
        return p[0] == 10 || (p[0] == 192 && p[1] == 168) || (p[0] == 172 && (16...31).contains(p[1]))
    }
    static func seekTarget(_ command: String, current: Double, duration: Double,step:Double = 30) -> Double? {
        guard step.isFinite,step>0,step<=120 else{return nil}
        let value: Double
        if command == "back" { value = current-step }
        else if command == "forward" { value = current+step }
        else if command.hasPrefix("seek:"), let parsed = Double(command.dropFirst(5)) { value = parsed }
        else { return nil }
        guard value.isFinite, current.isFinite else { return nil }
        return max(0,duration.isFinite && duration > 0 ? min(value,duration) : value)
    }
}


