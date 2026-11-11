import Foundation

final class GatewayClient: Sendable {
    let profile: ConnectionProfile
    private let token: String?
    private let session: URLSession
    private let trust: ServerTrust
    var certificateDigest: String? { trust.certificateDigest }

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
    }

    deinit { session.invalidateAndCancel() }
    func cancel() { session.invalidateAndCancel() }

    func get<T: Decodable & Sendable>(_ path: String, as type: T.Type) async throws -> T {
        try await request(path, body: nil, as: type)
    }

    func post<T: Decodable & Sendable>(_ path: String, body: [String: String], as type: T.Type) async throws -> T {
        try await request(path, body: JSONEncoder().encode(body), as: type)
    }

    func decide(_ decision: GatewayModels.Companion.Decision, allow: Bool) async throws -> GatewayModels.Receipt {
        struct Body: Encodable { let id: String; let decision: String; let allow: Bool }
        return try await request("/api/companion/agent", body: JSONEncoder().encode(
            Body(id: decision.id, decision: decision.decision, allow: allow)), as: GatewayModels.Receipt.self)
    }

    private func request<T: Decodable & Sendable>(_ path: String, body: Data?, as type: T.Type) async throws -> T {
        guard path.hasPrefix("/"), !path.hasPrefix("//"),
              let url = URL(string: path, relativeTo: profile.origin)?.absoluteURL,
              url.scheme == profile.origin.scheme, url.host == profile.origin.host,
              url.port == profile.origin.port else { throw GatewayError.invalidAddress }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            if trust.didRejectCertificate { throw GatewayError.certificateMismatch }
            throw error
        }
        guard let response = response as? HTTPURLResponse else { throw GatewayError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            let failure = try? JSONDecoder().decode(GatewayModels.Failure.self, from: data)
            let message = failure?.error ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            if response.statusCode == 429 {
                let seconds = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init) ?? failure?.retry_after ?? 600
                throw GatewayError.rateLimited(max(1, seconds), message)
            }
            throw GatewayError.http(response.statusCode, message)
        }
        guard response.mimeType == "application/json" else { throw GatewayError.invalidResponse }
        return try JSONDecoder().decode(type, from: data)
    }
}
