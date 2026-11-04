import Foundation

@main struct ControlPreferencesTests {
    static func main() throws {
        let encoded = try CastWire.encode(source:"sender-test",destination:"receiver-0",namespace:CastWire.receiver,body:["type":"GET_STATUS","requestId":1])
        let length = encoded.prefix(4).reduce(0){($0 << 8)|Int($1)}
        precondition(length == encoded.count-4)
        let (source,ns,body) = try CastWire.decode(Data(encoded.dropFirst(4)))
        precondition(source == "sender-test" && ns == CastWire.receiver && body["type"] as? String == "GET_STATUS")
        do { _ = try CastWire.decode(Data([18,255,255])); fatalError("Truncated envelope accepted") } catch CastDirectError.invalid {}
        precondition(CastWire.localIPv4("192.168.68.61"))
        precondition(CastWire.localIPv4("172.16.0.5"))
        precondition(!CastWire.localIPv4("8.8.8.8"))
        precondition(!CastWire.localIPv4("192.168.999.1"))
        precondition(CastWire.seekTarget("back",current:10,duration:100) == 0)
        precondition(CastWire.seekTarget("forward",current:90,duration:100) == 100)
        precondition(CastWire.seekTarget("seek:45.5",current:20,duration:100) == 45.5)
        precondition(CastWire.seekTarget("seek:nan",current:20,duration:100) == nil)
        let suite = "castbridge.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        var settings = SubtitleAppearance()
        settings.scale = 1.5; settings.color = "yellow"; settings.font = "mono"; settings.save(defaults:defaults)
        precondition(SubtitleAppearance.load(defaults:defaults) == settings)
        settings.scale = 99; settings.background = -1; settings.font = "invalid"; settings.save(defaults:defaults)
        let bounded = SubtitleAppearance.load(defaults:defaults)
        precondition(bounded.scale == 2 && bounded.background == 0 && bounded.font == "sans")
        precondition(SourceFileSize.label(bytes:1_000_000_000,description:"wrong 9 GB") != nil)
        precondition(SourceFileSize.label(bytes:nil,description:"File 2.61 / 24.6 GB") == "2.61 GB")
        precondition(SourceFileSize.label(bytes:nil,description:"File 719 MB / 6.8 GB") == "719 MB")
        precondition(SourceFileSize.label(bytes:nil,description:"File 1080p H264") == nil)
        precondition(CastWire.seekTarget("forward",current:20,duration:100,step:15)==35)
        precondition(CastWire.seekTarget("back",current:20,duration:100,step:60)==0)
        precondition(CastWire.seekTarget("forward",current:90,duration:100,step:15)==100)
        precondition(CastWire.seekTarget("forward",current:20,duration:100,step:.nan)==nil)
        print("Control/preferences tests passed: Cast envelopes, LAN scope, seek bounds, persistence, size metadata")
    }
}

