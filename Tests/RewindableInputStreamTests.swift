import Foundation

@main struct RewindableInputStreamTests {
    static func main() {
        let stream = RewindableInputStream(capacity:128,history:32)
        stream.open(); stream.receive(Data(0..<96))
        var buffer = [UInt8](repeating:0,count:64)
        precondition(stream.read(&buffer,maxLength:64) == 64 && buffer == Array(0..<64))
        precondition(stream.setProperty(NSNumber(value:16),forKey:.fileCurrentOffsetKey))
        precondition(stream.read(&buffer,maxLength:16) == 16 && Array(buffer.prefix(16)) == Array(16..<32))
        precondition(stream.setProperty(NSNumber(value:80),forKey:.fileCurrentOffsetKey))
        precondition(stream.read(&buffer,maxLength:16) == 16 && Array(buffer.prefix(16)) == Array(80..<96))
        precondition(!stream.setProperty(NSNumber(value:0),forKey:.fileCurrentOffsetKey))
        stream.complete(); precondition(stream.read(&buffer,maxLength:64) == 0)
        stream.close(); precondition(!stream.setProperty(NSNumber(value:96),forKey:.fileCurrentOffsetKey))

        let long = RewindableInputStream(capacity:128,history:32)
        let input = Data((0..<8192).map{UInt8($0%251)})
        long.open()
        let producer = DispatchSemaphore(value:0)
        DispatchQueue.global().async { long.receive(input); long.complete(); producer.signal() }
        var output = Data()
        while true {
            let count = long.read(&buffer,maxLength:64)
            precondition(count >= 0)
            if count == 0 { break }; output.append(contentsOf:buffer.prefix(count))
        }
        precondition(output == input && producer.wait(timeout:.now()+2) == .success)
        long.close()

        let blocked = RewindableInputStream(capacity:16,history:4)
        blocked.open()
        let reader = DispatchSemaphore(value:0)
        DispatchQueue.global().async {
            var byte:UInt8 = 0
            precondition(blocked.read(&byte,maxLength:1) == 0); reader.signal()
        }
        Thread.sleep(forTimeInterval:0.03); blocked.close()
        precondition(reader.wait(timeout:.now()+2) == .success)

        let full = RewindableInputStream(capacity:16,history:4)
        full.open()
        let writer = DispatchSemaphore(value:0)
        DispatchQueue.global().async { full.receive(Data(repeating:1,count:32)); writer.signal() }
        Thread.sleep(forTimeInterval:0.03); full.close()
        precondition(writer.wait(timeout:.now()+2) == .success)
        print("Rewind stream passed: bounded history, rewind, forward seek, byte continuity, EOF and cancellation of blocked read/write")
    }
}
