import Foundation
import XCTest
@testable import KMobile

/// Real feature models and URLSession transport; only the external server is replaced.
@MainActor
final class FeatureWorkflowTests: XCTestCase {
    private func fixture(stall: String? = nil) throws -> (AppModel, GatewayClient) {
        WorkflowServer.reset(stall: stall)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "workflow-tests." + UUID().uuidString))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WorkflowServer.self]
        let profile = ConnectionProfile(id: UUID(), name: "Original computer",
            origin: try ConnectionProfile.validatedOrigin("https://workflow.invalid"), kind: .computer)
        return (AppModel(defaults: defaults), GatewayClient(profile: profile, token: "test", configuration: configuration))
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The expected transport event did not arrive")
    }

    func testSuccessfulDiffShowsFilesWithoutRetryError() async throws {
        let (app, gateway) = try fixture()
        defer { gateway.cancel() }
        let agents = AgentsModel(app: app, gateway: gateway)
        let row = AgentLogic.row(.object(["id": .string("one")]), seen: [:])
        await agents.loadChanges(row)
        XCTAssertNil(agents.changesNote)
        XCTAssertFalse(agents.changesLoading)
        XCTAssertEqual(agents.changes.first?.path, "hello.swift")
        XCTAssertEqual(agents.changes.first?.added, 1)
    }

    func testTextAcknowledgementWaitsForServer() async throws {
        let (app, gateway) = try fixture(stall: "/beam/api/prepare")
        defer { gateway.cancel() }
        let beam = BeamModel(app: app, gateway: gateway)
        var acknowledged = false
        beam.send(text: "Keep this draft") { acknowledged = true }
        try await waitUntil { WorkflowServer.hasPending }
        XCTAssertFalse(acknowledged)
        XCTAssertTrue(beam.sending)
        WorkflowServer.release(body: ["done": true])
        try await waitUntil { !beam.sending }
        XCTAssertTrue(acknowledged)
    }

    func testRejectedTextDoesNotClearComposer() async throws {
        let (app, gateway) = try fixture(stall: "/beam/api/prepare")
        defer { gateway.cancel() }
        let beam = BeamModel(app: app, gateway: gateway)
        var draft = "Keep this draft"
        beam.send(text: draft) { draft = "" }
        try await waitUntil { WorkflowServer.hasPending }
        WorkflowServer.release(status: 403, body: ["error": "Declined"])
        try await waitUntil { !beam.sending }
        XCTAssertEqual(draft, "Keep this draft")
        guard case .failed = beam.sendState else { return XCTFail("Expected a failed send") }
    }

    func testBeamDoesNotFollowUpOnAnotherComputer() async throws {
        let (app, gateway) = try fixture(stall: "/beam/api/prepare")
        defer { gateway.cancel() }
        let beam = BeamModel(app: app, gateway: gateway)
        var acknowledged = false
        beam.send(text: "Old computer only") { acknowledged = true }
        try await waitUntil { WorkflowServer.hasPending }
        app.select(nil)
        WorkflowServer.release(body: ["ask": "old-request", "state": "waiting"])
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(acknowledged)
        XCTAssertFalse(WorkflowServer.paths.contains("/beam/api/ask"))
        XCTAssertTrue(app.activity.isEmpty)
        beam.stop()
    }

    func testHostSwitchWhileStampIsLoadingCannotDispatchCommand() async throws {
        let (app, gateway) = try fixture(stall: "/agents/api/status")
        defer { gateway.cancel() }
        let agents = AgentsModel(app: app, gateway: gateway)
        defer { agents.stop() }
        let row = AgentLogic.row(.object(["id": .string("one")]), seen: [:])
        let operation = Task { await agents.rename(row, to: "New name") }
        try await waitUntil { WorkflowServer.hasPending }
        await agents.pickHost("other-computer")
        WorkflowServer.release(body: ["connector": "old-connector"])
        await operation.value
        XCTAssertFalse(WorkflowServer.paths.contains { $0.hasSuffix("/commands") })
        XCTAssertNil(agents.rowNote["rename:one"])
    }

    func testLateStreamOfferCannotRestartDisconnectedScreen() async throws {
        let (app, gateway) = try fixture(stall: "/api/native/stream")
        defer { gateway.cancel() }
        let stream = RemoteStreamModel(gateway: gateway)
        let operation = Task { await stream.connect(app, screen: CGSize(width: 390, height: 844), scale: 3) }
        try await waitUntil { WorkflowServer.hasPending }
        stream.disconnect()
        WorkflowServer.release(body: ["session": "test", "codec": "h264", "w": 390, "h": 844,
            "fps": 60, "port": 8445, "key": Data(repeating: 0, count: 16).base64EncodedString(),
            "salt": Data(repeating: 0, count: 4).base64EncodedString()])
        await operation.value
        XCTAssertEqual(stream.phase, .ended)
        XCTAssertNil(stream.video)
    }
}

private final class WorkflowServer: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var pending: WorkflowServer?
    nonisolated(unsafe) private static var stall: String?
    nonisolated(unsafe) private static var requests: [String] = []
    static var paths: [String] { lock.withLock { requests } }
    static var hasPending: Bool { lock.withLock { pending != nil } }
    static func reset(stall: String?) { lock.withLock { self.stall = stall; pending = nil; requests = [] } }
    static func release(status: Int = 200, body: [String: Any]) {
        let waiting = lock.withLock { let waiting = pending; pending = nil; return waiting }
        waiting?.reply(status: status, body: body)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url?.path ?? ""
        let held = Self.lock.withLock {
            Self.requests.append(path)
            if Self.stall == path { Self.pending = self; Self.stall = nil; return true }
            return false
        }
        guard !held else { return }
        if path.contains("/changes/") {
            reply(body: ["diff": "diff --git a/hello.swift b/hello.swift\n--- a/hello.swift\n+++ b/hello.swift\n@@ -1 +1 @@\n-old\n+new\n"])
        } else if path.hasSuffix("/status") { reply(body: ["connector": "test-connector"]) }
        else { reply(body: ["ok": true, "sessions": []]) }
    }
    private func reply(status: Int = 200, body: [String: Any]) {
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]),
            let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
