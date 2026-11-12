import Foundation

final class GatewayClient: Sendable {
    let profile: ConnectionProfile
    private let token: String?
    private let session: URLSession
    /// Long transfers (k-beam files, the ask long-poll) share the cookie jar, so the
    /// `khole_app` cookie /api/hello set reaches the /beam/ proxy here too.
    private let transfers: URLSession
    private let trust: ServerTrust
    var certificateDigest: String? { trust.certificateDigest }
    /// The device token, for the native stream's control channel (its first frame carries it).
    var deviceToken: String? { token }
    /// The pinned certificate digest, when this connection pins one (a companion).
    var pinnedDigest: String? { trust.pinnedDigest }

    init(profile: ConnectionProfile, token: String? = nil, pin: String? = nil, enrollmentCode: String? = nil,
         configuration: URLSessionConfiguration = .ephemeral) {
        self.profile = profile
        self.token = token
        trust = ServerTrust(origin: profile.origin, pin: pin, enrollmentCode: enrollmentCode)
        let config = configuration
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        // Ephemeral, per-connection cookies preserve the gateway's HttpOnly app cookie.
        config.httpCookieAcceptPolicy = .always
        session = URLSession(configuration: config, delegate: trust, delegateQueue: nil)
        let long = config.copy() as! URLSessionConfiguration
        long.httpCookieStorage = session.configuration.httpCookieStorage
        long.timeoutIntervalForRequest = 60
        long.timeoutIntervalForResource = 6 * 60 * 60
        transfers = URLSession(configuration: long, delegate: trust, delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel(); transfers.invalidateAndCancel() }
    func cancel() { session.invalidateAndCancel(); transfers.invalidateAndCancel() }

    /// GET on the long session: k-beam's ask long-poll waits up to 25 s.
    func wait<T: Decodable & Sendable>(_ path: String, as type: T.Type) async throws -> T {
        try await request(path, body: nil, as: type, on: transfers)
    }

    /// POST the rest of a file from `offset` (a resumed k-beam upload). The body is
    /// streamed from disk; Content-Length is exactly what is left, as khole-share requires.
    func uploadFile<T: Decodable & Sendable>(_ path: String, file: URL, from offset: Int64, as type: T.Type)
        async throws -> T {
        let size = try (FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard offset >= 0, offset <= size else { throw GatewayError.invalidResponse }
        let part: URL
        if offset == 0 { part = file } else {
            part = FileManager.default.temporaryDirectory.appending(path: "part-" + UUID().uuidString)
            try Self.copyTail(of: file, from: offset, to: part)
        }
        defer { if part != file { try? FileManager.default.removeItem(at: part) } }
        var request = try makeRequest(path, body: Data(), contentType: "application/octet-stream")
        request.httpBody = nil
        request.setValue(String(size - offset), forHTTPHeaderField: "Content-Length")
        let data: Data
        let response: URLResponse
        do { (data, response) = try await transfers.upload(for: request, fromFile: part) }
        catch {
            if trust.didRejectCertificate { throw GatewayError.certificateMismatch }
            throw error
        }
        return try Self.decode(response, data, as: type)
    }

    private static func copyTail(of file: URL, from offset: Int64, to target: URL) throws {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        FileManager.default.createFile(atPath: target.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let output = try FileHandle(forWritingTo: target)
        defer { try? output.close() }
        try input.seek(toOffset: UInt64(offset))
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty { try output.write(contentsOf: chunk) }
    }

    func get<T: Decodable & Sendable>(_ path: String, as type: T.Type) async throws -> T {
        try await request(path, body: nil, as: type)
    }

    func post<T: Decodable & Sendable>(_ path: String, body: [String: String], as type: T.Type) async throws -> T {
        try await request(path, body: JSONEncoder().encode(body), as: type)
    }

    /// POST any Encodable body as JSON (k-beam's prepare, Agents' replies).
    func send<B: Encodable, T: Decodable & Sendable>(_ path: String, json: B, as type: T.Type) async throws -> T {
        try await request(path, body: JSONEncoder().encode(json), as: type)
    }

    /// POST a command on the long session: an agent's command can take longer than a page read.
    func command<B: Encodable, T: Decodable & Sendable>(_ path: String, json: B, as type: T.Type) async throws -> T {
        try await request(path, body: JSONEncoder().encode(json), as: type, on: transfers)
    }

    /// scheme://host[:port], as a browser would send it.
    static func origin(of url: URL) -> String {
        let host = url.host ?? ""
        var out = (url.scheme ?? "https") + "://" + (host.contains(":") ? "[" + host + "]" : host)
        if let port = url.port { out += ":\(port)" }
        return out
    }

    /// POST raw bytes (a k-beam upload). URLSession sets Content-Length from the body, which khole-web requires.
    func upload<T: Decodable & Sendable>(_ path: String, data: Data, as type: T.Type) async throws -> T {
        try await request(path, body: data, contentType: "application/octet-stream", as: type)
    }

    /// GET a file into a temporary location the caller moves or shares.
    func download(_ path: String) async throws -> URL {
        var request = try makeRequest(path, body: nil, contentType: nil)
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        let (file, response): (URL, URLResponse)
        do { (file, response) = try await transfers.download(for: request) }
        catch {
            if trust.didRejectCertificate { throw GatewayError.certificateMismatch }
            throw error
        }
        guard let http = response as? HTTPURLResponse else { throw GatewayError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let data = (try? Data(contentsOf: file)) ?? Data()
            try? FileManager.default.removeItem(at: file)
            throw Self.failure(http, data)
        }
        let kept = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.moveItem(at: file, to: kept)
        return kept
    }

    func decide(_ decision: GatewayModels.Companion.Decision, allow: Bool) async throws -> GatewayModels.Receipt {
        struct Body: Encodable { let id: String; let decision: String; let allow: Bool }
        return try await request("/api/companion/agent", body: JSONEncoder().encode(
            Body(id: decision.id, decision: decision.decision, allow: allow)), as: GatewayModels.Receipt.self)
    }

    private func makeRequest(_ path: String, body: Data?, contentType: String?) throws -> URLRequest {
        guard path.hasPrefix("/"), !path.hasPrefix("//"),
              let url = URL(string: path, relativeTo: profile.origin)?.absoluteURL,
              url.scheme == profile.origin.scheme, url.host == profile.origin.host,
              url.port == profile.origin.port else { throw GatewayError.invalidAddress }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let body {
            // The Agents connector refuses a POST whose Origin isn't the computer's own.
            request.setValue(Self.origin(of: profile.origin), forHTTPHeaderField: "Origin")
            request.setValue(contentType ?? "application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        }
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        return request
    }

    /// khole-web answers {"error"}; khole-share {ok:false, error (a code), message (words)}: words first.
    private static func failure(_ response: HTTPURLResponse, _ data: Data) -> GatewayError {
        let failure = try? JSONDecoder().decode(GatewayModels.Failure.self, from: data)
        // The Agents connector answers {error: CODE, message}; its code decides what the phone says.
        if response.url?.path.hasPrefix("/agents/") == true, let code = failure?.error,
           code.range(of: "^[A-Z][A-Z0-9_]{1,63}$", options: .regularExpression) != nil {
            return .coded(response.statusCode, code, failure?.message ?? "")
        }
        let message = failure?.message ?? failure?.error
            ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
        if response.statusCode == 429 {
            let seconds = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init) ?? failure?.retry_after ?? 600
            return .rateLimited(max(1, seconds), message)
        }
        if failure?.pair == true { return .needsPairing(message) }
        if failure?.control == true { return .needsControl(message) }
        return .http(response.statusCode, message)
    }

    private func request<T: Decodable & Sendable>(_ path: String, body: Data?, contentType: String? = nil,
                                                  as type: T.Type, on chosen: URLSession? = nil) async throws -> T {
        let request = try makeRequest(path, body: body, contentType: contentType)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await (chosen ?? session).data(for: request) }
        catch {
            if trust.didRejectCertificate { throw GatewayError.certificateMismatch }
            throw error
        }
        return try Self.decode(response, data, as: type)
    }

    private static func decode<T: Decodable & Sendable>(_ response: URLResponse, _ data: Data, as type: T.Type) throws -> T {
        guard let response = response as? HTTPURLResponse else { throw GatewayError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw failure(response, data) }
        guard response.mimeType == "application/json" else { throw GatewayError.invalidResponse }
        return try JSONDecoder().decode(type, from: data)
    }
}
