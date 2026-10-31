import Foundation
import Security

struct SubtitleHosting: Codable {
    let endpoint: URL
    let token: String
    private static let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"app.castbridge.subtitles",kSecAttrAccount as String:"hosting"]
    static func load() throws -> SubtitleHosting? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary,&result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw AddonConfigError.keychain }
        return try JSONDecoder().decode(Self.self,from:data)
    }
    static func save(endpoint: String, token: String) throws {
        guard let url = URL(string:endpoint.trimmingCharacters(in:.whitespacesAndNewlines)), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, url.port == nil,
              token.range(of:#"^[A-Za-z0-9_-]{32,150}$"#,options:.regularExpression) != nil else { throw SubtitleError.noService }
        let data = try JSONEncoder().encode(Self(endpoint:url,token:token))
        let values: [String:Any] = [kSecValueData as String:data,kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary,values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; values.forEach{item[$0.key] = $0.value}
            guard SecItemAdd(item as CFDictionary,nil) == errSecSuccess else { throw AddonConfigError.keychain }; return
        }
        guard status == errSecSuccess else { throw AddonConfigError.keychain }
    }
    func upload(_ vtt: String) async throws -> URL {
        guard vtt.hasPrefix("WEBVTT\n"), vtt.utf8.count <= 1_000_000 else { throw SubtitleError.limit }
        let session = URLSession(configuration:.ephemeral,delegate:NoSubtitleRedirect(),delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url:endpoint,timeoutInterval:25)
        request.httpMethod = "POST"; request.httpBody = Data(vtt.utf8)
        request.setValue("text/vtt; charset=utf-8",forHTTPHeaderField:"Content-Type")
        request.setValue("Bearer " + token,forHTTPHeaderField:"Authorization")
        let (data,response) = try await session.data(for:request)
        struct Result: Decodable { let url: URL; let expires: Double }
        guard let http = response as? HTTPURLResponse, http.statusCode == 201, data.count < 10000 else { throw SubtitleError.network }
        let result = try JSONDecoder().decode(Result.self,from:data)
        guard result.url.scheme == "https", result.url.host == endpoint.host, result.url.user == nil, result.url.password == nil,
              result.url.port == nil, result.url.pathExtension == "vtt", result.expires > Date().timeIntervalSince1970,
              result.expires <= Date().timeIntervalSince1970+86460 else { throw SubtitleError.network }
        return result.url
    }
}
private final class NoSubtitleRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
