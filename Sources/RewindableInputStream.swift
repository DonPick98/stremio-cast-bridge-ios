import Foundation

/// A bounded rewind window for a streaming demuxer, not a movie download.
/// VLCKit advertises seek callbacks for InputStream subclasses. Matroska needs
/// short backward seeks to parse a cluster; HTTP chunked input cannot do that.
final class RewindableInputStream: InputStream, URLSessionDataDelegate, @unchecked Sendable {
    private let condition = NSCondition()
    private let url:URL?
    private let capacity:Int
    private let history:Int
    private var bytes = Data()
    private var base = 0
    private var cursor = 0
    private var opened = false
    private var closed = false
    private var finished = false
    private var failure:Error?
    private var network:URLSession?
    private var networkTask:URLSessionDataTask?
    private var suspended = false

    init(url:URL? = nil,capacity:Int = 8_388_608,history:Int = 2_097_152) {
        precondition(capacity > 0 && history >= 0 && history < capacity)
        self.url = url; self.capacity = capacity; self.history = history
        super.init(data:Data())
    }
    override func open() {
        condition.lock()
        guard !opened, !closed else { condition.unlock(); return }
        opened = true
        guard let url else { condition.unlock(); return }
        // Only connect to the private FFmpeg loopback producer. Never redirect
        // or send a movie URL, credentials or cookies through this adapter.
        guard url.scheme == "http", url.host == "127.0.0.1", url.user == nil, url.password == nil else {
            failure = URLError(.unsupportedURL); finished = true; condition.broadcast(); condition.unlock(); return
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 86400
        config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration:config,delegate:self,delegateQueue:queue)
        network = session
        let task = session.dataTask(with:url); networkTask = task
        condition.unlock()
        task.resume()
    }
    override func close() {
        condition.lock(); closed = true
        let session = network; network = nil; networkTask = nil
        bytes.removeAll(); condition.broadcast(); condition.unlock()
        session?.invalidateAndCancel()
    }
    override var streamStatus:Stream.Status {
        condition.lock(); defer { condition.unlock() }
        if closed { return .closed }; if !opened { return .notOpen }
        if failure != nil { return .error }
        return finished && cursor == base+bytes.count ? .atEnd : .open
    }
    override var streamError:Error? {
        condition.lock(); defer { condition.unlock() }; return failure
    }
    override var hasBytesAvailable:Bool {
        condition.lock(); defer { condition.unlock() }; return !closed && cursor < base+bytes.count
    }
    override func read(_ buffer:UnsafeMutablePointer<UInt8>,maxLength len:Int) -> Int {
        condition.lock(); defer { condition.unlock() }
        guard len > 0 else { return 0 }
        while !closed && !finished && cursor == base+bytes.count { condition.wait() }
        if closed { return 0 }
        let count = min(len,base+bytes.count-cursor)
        guard count > 0 else { return failure == nil ? 0 : -1 }
        let offset = cursor-base
        bytes.copyBytes(to:buffer,from:offset..<offset+count)
        cursor += count
        // Trim in chunks rather than shifting the history on every small read.
        trimHistory()
        condition.broadcast()
        return count
    }
    override func getBuffer(_ buffer:UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>,length len:UnsafeMutablePointer<Int>) -> Bool { false }
    override func property(forKey key:Stream.PropertyKey) -> Any? {
        guard key == .fileCurrentOffsetKey else { return nil }
        condition.lock(); defer { condition.unlock() }; return NSNumber(value:cursor)
    }
    override func setProperty(_ property:Any?,forKey key:Stream.PropertyKey) -> Bool {
        guard key == .fileCurrentOffsetKey, let number = property as? NSNumber,
              number.doubleValue >= 0, number.doubleValue < Double(Int.max) else { return false }
        let target = number.intValue
        condition.lock(); defer { condition.unlock() }
        guard !closed, target >= base, target-base <= capacity else { return false }
        while target > base+bytes.count && !closed && !finished { condition.wait() }
        guard !closed, target <= base+bytes.count else { return false }
        cursor = target; trimHistory(); condition.broadcast(); return true
    }
    private func trimHistory() {
        if cursor-base > history+min(524288,capacity/4) {
            let drop = cursor-base-history
            bytes.removeSubrange(0..<drop); base += drop
        }
        if suspended && bytes.count < capacity { suspended = false; networkTask?.resume() }
    }
    func receive(_ data:Data) {
        var offset = 0
        condition.lock(); defer { condition.unlock() }
        while offset < data.count && !closed {
            while bytes.count == capacity && !closed { condition.wait() }
            if closed { return }
            let count = min(capacity-bytes.count,data.count-offset)
            bytes.append(data[offset..<offset+count]); offset += count
            if bytes.count == capacity, !suspended, let task = networkTask { suspended = true; task.suspend() }
            condition.broadcast()
        }
    }
    func complete(_ error:Error? = nil) {
        condition.lock(); finished = true; failure = error
        condition.broadcast(); condition.unlock()
    }
    func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive response:URLResponse,completionHandler:@escaping (URLSession.ResponseDisposition)->Void) {
        let valid = (response as? HTTPURLResponse)?.statusCode == 200
        if !valid { complete(URLError(.badServerResponse)) }
        completionHandler(valid ? .allow : .cancel)
    }
    func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive data:Data) { receive(data) }
    func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?) { complete(error); session.finishTasksAndInvalidate() }
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void) { completionHandler(nil) }
}
