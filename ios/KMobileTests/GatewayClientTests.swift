import Foundation
import Testing
@testable import KMobile

struct GatewayClientTests {
    private func client() throws -> GatewayClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GatewayStub.self]
        return GatewayClient(profile: ConnectionProfile(id: UUID(), name: "Test",
            origin: try ConnectionProfile.validatedOrigin("https://test.invalid"), kind: .computer),
            token: "test-token", configuration: config)
    }

    @Test func sendsBearerAndDisablesCache() async throws {
        let client = try client()
        defer { client.cancel() }
        // The stub only returns success when all transport assertions hold.
        let response = try await client.get("/api/hello", as: GatewayModels.Hello.self)
        #expect(response.device.control == "view")
    }

    @Test func serviceUnavailableThrowsInsteadOfCreatingConnection() async throws {
        let client = try client()
        defer { client.cancel() }
        await #expect(throws: GatewayError.self) {
            try await client.get("/unavailable", as: GatewayModels.Hello.self)
        }
    }

    @Test func rateLimitUsesHTTPHeader() async throws {
        let client = try client()
        defer { client.cancel() }
        do {
            let _ = try await client.get("/limited", as: GatewayModels.Hello.self)
            Issue.record("Expected rate limit")
        } catch GatewayError.rateLimited(let seconds, _) { #expect(seconds == 120) }
    }

    @Test func htmlLoginCannotBecomeAPIData() async throws {
        let client = try client()
        defer { client.cancel() }
        await #expect(throws: GatewayError.self) {
            try await client.get("/login", as: GatewayModels.Hello.self)
        }
    }

    @Test func rejectsCrossOriginTokenForwarding() async throws {
        let client = try client()
        defer { client.cancel() }
        await #expect(throws: GatewayError.self) {
            try await client.get("//other.invalid/api/hello", as: GatewayModels.Hello.self)
        }
    }
}

private final class GatewayStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        var status = 200
        var contentType = "application/json"
        var body = #"{"device":{"id":"phone","name":"Test phone","control":"view","kind":"phone"}}"#
        if request.value(forHTTPHeaderField: "Authorization") != "Bearer test-token"
            || request.value(forHTTPHeaderField: "Cache-Control") != "no-store"
            || request.cachePolicy != .reloadIgnoringLocalAndRemoteCacheData {
            status = 400
            body = #"{"error":"Transport invariant failed"}"#
        } else if url.path == "/unavailable" {
            status = 503
            body = #"{"error":"Local preview has no backend","retry_after":15}"#
        } else if url.path == "/limited" {
            status = 429
            body = #"{"error":"Wait before trying another code","state":"limited"}"#
        } else if url.path == "/login" {
            contentType = "text/html"
            body = "<html>Log in</html>"
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": contentType, "Retry-After": "120"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
