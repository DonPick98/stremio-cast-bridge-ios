import Foundation
@main struct PlayableStreamHeaderTests {
    static func main()throws {
        func element(_ id:[UInt8],_ payload:Data)->Data {
            precondition(payload.count<127)
            return Data(id+[UInt8(0x80|payload.count)])+payload
        }
        func webm(video:String?="V_VP8",audio:String?="A_VORBIS",channels:UInt8=2)->Data {
            var entries=Data()
            if let video{entries += element([0xae],element([0x83],Data([1]))+element([0x86],Data(video.utf8)))}
            if let audio{entries += element([0xae],element([0x83],Data([2]))+element([0x86],Data(audio.utf8))+element([0xe1],element([0x9f],Data([channels]))))}
            return element([0x1a,0x45,0xdf,0xa3],Data())+Data([0x18,0x53,0x80,0x67,0xff])+element([0x16,0x54,0xae,0x6b],entries)
        }
        for audio in ["A_VORBIS","A_OPUS"] {
            let data=webm(audio:audio)
            let ready=try PlayableStreamHeader.check(data,contentType:"video/webm");precondition(ready)
            for n in 0..<data.count {
                let partial=try PlayableStreamHeader.check(Data(data.prefix(n)),contentType:"video/webm")
                precondition(!partial,"A partial Tracks element must not become ready")
            }
        }
        let bad:[(Data,StreamHeaderRejection)]=[
            (webm(video:"V_VP9"),.videoCodec),(webm(audio:"A_AAC"),.audioCodec),
            (webm(channels:6),.audioChannels),(webm(channels:0),.audioChannels),
            (webm(audio:nil),.missingAudio),(webm(video:nil),.missingVideo)]
        for (data,expected) in bad {
            do{_ = try PlayableStreamHeader.check(data,contentType:"video/webm");fatalError("Unsupported stream accepted")}
            catch StreamHeaderError.rejected(let reason){precondition(reason==expected)}
        }
        print("Stream headers passed: WebM VP8 with Vorbis/Opus, incremental Tracks readiness and exact codec/channel/missing-track rejection")
    }
}
