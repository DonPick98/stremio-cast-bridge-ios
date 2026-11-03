import Foundation
import Darwin

@main struct MediaOutputChannelTests {
    static func port() throws -> UInt16 {
        let fd = Darwin.socket(AF_INET,SOCK_STREAM,0)
        guard fd >= 0 else { throw LocalStreamError.address }
        defer { Darwin.close(fd) }
        var addr = sockaddr_in(); addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); addr.sin_family = sa_family_t(AF_INET)
        inet_pton(AF_INET,"127.0.0.1",&addr.sin_addr)
        let bound = withUnsafePointer(to:&addr) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { Darwin.bind(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0 else { throw LocalStreamError.address }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to:&addr) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { Darwin.getsockname(fd,$0,&length) } }
        guard named == 0 else { throw LocalStreamError.address }
        return UInt16(bigEndian:addr.sin_port)
    }
    static func main() async throws {
        let channel = try MediaOutputChannel(), port = try port()
        defer { channel.stop() }
        try await channel.start(port:port,path:"/test-stream",type:"video/mp4")
        let expected = Data((0..<2_000_000).map { UInt8($0 & 255) })
        DispatchQueue.global().async {
            expected.withUnsafeBytes { raw in
                var offset = 0
                while offset < expected.count {
                    let n = Darwin.send(channel.writer,raw.baseAddress!.advanced(by:offset),expected.count-offset,0)
                    precondition(n > 0,"Socket writer failed")
                    offset += n
                }
            }
            Task {
                let drained = await channel.waitForDrain()
                precondition(drained,"Output did not drain before producer teardown")
                channel.endWriting()
            }
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5; config.timeoutIntervalForResource = 10
        let session = URLSession(configuration:config)
        let (actual,response) = try await session.data(from:URL(string:"http://127.0.0.1:\(port)/test-stream")!)
        session.invalidateAndCancel()
        precondition((response as? HTTPURLResponse)?.statusCode == 200 && actual == expected,"Media bytes lost or reordered")
        // VLC duplicates the fd before emitting a header and announces its
        // logical end before flushing the trailer. Closing our original must
        // neither signal premature EOF nor discard a late, backpressured tail.
        for _ in 0..<8 {
            let retained = try MediaOutputChannel(), p = try Self.port()
            try await retained.start(port:p,path:"/drain",type:"video/mp4")
            let duplicate = Darwin.dup(retained.writer)
            precondition(duplicate >= 0)
            retained.endWriting()
            DispatchQueue.global().async {
                defer { Darwin.close(duplicate) }
                expected.withUnsafeBytes { raw in
                    var offset = 0
                    while offset < expected.count {
                        if offset >= expected.count - 65_536 { Thread.sleep(forTimeInterval:0.01) }
                        let count = min(16_384,expected.count-offset)
                        let n = Darwin.send(duplicate,raw.baseAddress!.advanced(by:offset),count,0)
                        precondition(n > 0)
                        offset += n
                    }
                }
            }
            let client = URLSession(configuration:config)
            let (drained,_) = try await client.data(from:URL(string:"http://127.0.0.1:\(p)/drain")!)
            client.invalidateAndCancel()
            precondition(drained == expected,"Duplicate writer trailer lost")
            retained.stop()
        }
        let blocked = try MediaOutputChannel()
        try await blocked.start(port:try Self.port(),path:"/blocked",type:"video/mp4")
        let released = DispatchSemaphore(value:0)
        DispatchQueue.global().async {
            var data = [UInt8](repeating:1,count:65_536)
            while Darwin.send(blocked.writer,&data,65_536,0) > 0 {}
            released.signal()
        }
        try await Task.sleep(nanoseconds:200_000_000)
        blocked.stop()
        precondition(released.wait(timeout:.now()+2) == .success,"Stopping did not unblock encoder")
        print("Media output channel passed: 2 MB byte-exact transfer, EOF and cancellation of a blocked encoder")
    }
}

