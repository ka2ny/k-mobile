import Foundation
import XCTest
import SwiftUI
import UIKit
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

    func testAssistantAcknowledgementCannotClearAnotherComputersDraft() async throws {
        let (app, gateway) = try fixture(stall: "/app/assistant/do")
        defer { gateway.cancel() }
        let assistant = AssistantModel(app: app, gateway: gateway)
        let request = Task { await assistant.startTask("Keep my draft") }
        try await waitUntil { WorkflowServer.hasPending }
        app.select(nil)
        WorkflowServer.release(body: ["ok": true])
        let acknowledged = await request.value
        XCTAssertFalse(acknowledged)
        XCTAssertFalse(WorkflowServer.paths.contains("/app/assistant"))
    }

    func testAssistantStopDiscardsLateMemory() async throws {
        let (app, gateway) = try fixture(stall: "/app/assistant")
        defer { gateway.cancel() }
        let assistant = AssistantModel(app: app, gateway: gateway)
        let request = Task { await assistant.loadMemory("helper") }
        try await waitUntil { WorkflowServer.hasPending }
        assistant.stop()
        WorkflowServer.release(body: ["memory": ["facts": [["text": "Stale memory"]]]])
        await request.value
        XCTAssertNil(assistant.memory)
        XCTAssertTrue(assistant.busy.isEmpty)
    }

    func testBoundedAttachmentReaderRejectsOversizedFile() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 42, count: 65).write(to: url)
        XCTAssertThrowsError(try AssistantAttachment.read(url, limit: 64))
        XCTAssertEqual(try AssistantAttachment.read(url, limit: 65).count, 65)
    }

    func testFileBackedImportCleansPartialSelection() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "hello.txt")
        try Data("hello".utf8).write(to: file)
        let copied = try BeamImport.copyFiles([file])
        XCTAssertEqual(copied.first?.size, 5)
        let target = try XCTUnwrap(copied.first?.url)
        BeamImport.remove(copied)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertThrowsError(try BeamImport.copyFiles([file, folder]))
    }

    /// Fixture screenshots inspect real SwiftUI layouts. They are not live computer/device evidence.
    func testConnectedFileAndMemoryLayoutsWithFixtureServer() async throws {
        let (app, gateway) = try fixture()
        defer { gateway.cancel() }
        let beam = BeamModel(app: app, gateway: gateway)
        await beam.refresh()
        XCTAssertEqual(beam.folder.count, 4)
        await captureFixture("Fixture-Files", view: NavigationStack {
            ScrollView { BeamFilesView(beam: beam).quietPage() }.background(Design.background).navigationTitle("Files")
        })
        let assistant = AssistantModel(app: app, gateway: gateway)
        await assistant.loadHistory()
        await assistant.loadMemory("helper")
        XCTAssertEqual(assistant.memory?.facts.count, 2)
        XCTAssertEqual(assistant.memory?.howTo.count, 1)
        await captureFixture("Fixture-Assistant-Memory", view: AssistantMemoryView(assistant: assistant, persona: "helper"))
    }

    private func captureFixture<Content: View>(_ title: String, view: Content) async {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            XCTFail("No simulator window scene"); return
        }
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let controller = UIHostingController(rootView: view.environment(\.mobileAccent, .blue))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try? await Task.sleep(for: .milliseconds(500))
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = title; attachment.lifetime = .keepAlways; add(attachment)
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
        if path == "/beam/api/me" {
            reply(body: ["ok": true, "name": "Studio", "folder": true])
        } else if path == "/beam/api/inbox" {
            reply(body: ["ok": true, "items": []])
        } else if path == "/beam/api/folder" {
            reply(body: ["ok": true, "on": true, "name": "Project handoff", "files": [
                ["name": "Brand direction.pdf", "size": 3400000, "at": 1794441000, "type": "application/pdf"],
                ["name": "Product shoot.heic", "size": 5200000, "at": 1794440000, "type": "image/heic"],
                ["name": "Release notes.md", "size": 2048, "at": 1794430000, "type": "text/plain"],
                ["name": "Walkthrough.mov", "size": 84000000, "at": 1794420000, "type": "video/quicktime"]]])
        } else if path == "/app/assistant" {
            reply(body: ["now": ["running": false], "default": "helper", "assistants": [["id": "helper", "name": "Assistant"]],
                         "memory": ["facts": [["text": "Use concise release notes.", "pinned": true], ["text": "The mobile project uses SwiftUI.", "locked": true]],
                                    "notes": [["kind": "howto", "title": "Prepare a release", "body": "Review changes, run checks and prepare the handoff.", "used": 3]]]])
        } else if path.contains("/changes/") {
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
