import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    private(set) var profiles: [ConnectionProfile] = []
    private(set) var selectedID: UUID?
    private(set) var device: GatewayModels.Device?
    private(set) var hub: GatewayModels.Hub?
    private(set) var companion: GatewayModels.Companion?
    private(set) var assistant: GatewayModels.Assistant?
    private(set) var lastUpdated: Date?
    private(set) var online = false
    private(set) var busy = false
    private(set) var refreshing = false
    private(set) var connectionError: String?
    private(set) var companionError: String?
    private(set) var computerError: String?
    private(set) var assistantError: String?
    private(set) var activity: [ActivityEntry] = []
    private(set) var lastReceipt: String?
    private(set) var linkVersion: Int?
    private(set) var boardLinks: [GatewayModels.BoardLink] = []
    private(set) var linksError: String?
    private(set) var linkRetryAt: Date?
    private(set) var linkBusy = false
    var supportsBoardLink: Bool { online && selected?.kind == .computer && device?.kind == "phone" && linkVersion == 1 }
    private(set) var pairingError: String?
    private(set) var acceptedActionCount = 0
    @ObservationIgnored private var assistantRefreshing = false
    var interacting: Bool { busy || linkBusy }
    var notice: String?

    @ObservationIgnored private var client: GatewayClient?
    @ObservationIgnored private let credentials = CredentialStore()
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let defaults: UserDefaults

    var selected: ConnectionProfile? { profiles.first { $0.id == selectedID } }
    var canControl: Bool { RuntimePolicy.canControl(online: online, kind: selected?.kind, device: device, hub: hub) && !interacting }
    var canUseAssistant: Bool {
        online && device?.control == "full" && selected?.kind == .computer
            && hub?.paired == true && hub?.stopped == false && hub?.control == "full"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "native.connections") {
            do { profiles = try JSONDecoder().decode([ConnectionProfile].self, from: data) }
            catch { notice = "Saved connections could not be read. Pair your computer again." }
        }
        let saved = defaults.string(forKey: "native.selected").flatMap(UUID.init(uuidString:))
        select(profiles.first { $0.id == saved }?.id ?? profiles.first?.id)
    }

    func select(_ id: UUID?) {
        guard !busy, !linkBusy else { return }
        client?.cancel()
        client = nil
        generation = UUID()
        linkRetryAt = nil
        selectedID = id
        defaults.set(id?.uuidString, forKey: "native.selected")
        clearLiveState()
        refreshing = false
        assistantRefreshing = false
        guard let profile = selected else { return }
        do {
            let credential = try credentials.read(profile.id)
            if profile.kind == .companion && credential.certificateSHA256 == nil {
                throw GatewayError.missingCredential
            }
            client = GatewayClient(profile: profile, token: credential.token, pin: credential.certificateSHA256)
        } catch { connectionError = error.localizedDescription }
    }

    private func clearLiveState() {
        online = false
        linkVersion = nil
        boardLinks = []
        linksError = nil
        device = nil
        hub = nil
        companion = nil
        assistant = nil
        lastUpdated = nil
        connectionError = nil
        companionError = nil
        computerError = nil
        assistantError = nil
        lastReceipt = nil
    }

    func pair(name: String, address: String, kind: ConnectionProfile.Kind, pin: String, code: String) async -> Bool {
        guard !busy, !linkBusy else { return false }
        busy = true
        pairingError = nil
        defer { busy = false }
        do {
            let origin = try ConnectionProfile.validatedOrigin(address)
            guard pin.count == 6, pin.allSatisfy({ $0.isASCII && $0.isNumber }) else {
                throw GatewayError.refused("Enter the six-digit PIN shown on your computer.")
            }
            let certificateCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if kind == .companion && certificateCode.range(of: "^[A-Z2-7]{4}-[A-Z2-7]{4}$", options: .regularExpression) == nil {
                throw GatewayError.refused("Enter the certificate code as XXXX-XXXX from Settings → Remote → k-chain.")
            }
            guard !profiles.contains(where: { $0.origin == origin }) else {
                throw GatewayError.refused("This address is already saved. Select it in Connections, or forget it before pairing again.")
            }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let profile = ConnectionProfile(id: UUID(), name: trimmed.isEmpty ? "My computer" : trimmed,
                                            origin: origin, kind: kind)
            let enrollment = GatewayClient(profile: profile, enrollmentCode: kind == .companion ? certificateCode : nil)
            defer { enrollment.cancel() }
            let response = try await enrollment.post("/api/pair", body: ["pin": pin, "name": "k-hole iOS"], as: GatewayModels.Pair.self)
            guard !response.token.isEmpty, response.device.kind == (kind == .companion ? "companion" : "phone") else {
                throw GatewayError.refused("This address is for a different connection type. Check the address shown on the computer.")
            }
            let digest = enrollment.certificateDigest
            if kind == .companion && digest == nil { throw GatewayError.certificateMismatch }
            try credentials.save(.init(token: response.token, certificateSHA256: digest), for: profile.id)
            let updated = profiles + [profile]
            let data = try JSONEncoder().encode(updated)
            defaults.set(data, forKey: "native.connections")
            profiles = updated
            busy = false
            select(profile.id)
            record("Paired", "\(profile.name) accepted this phone.")
            return true
        } catch {
            pairingError = error.localizedDescription
            return false
        }
    }

    func refresh(includeCompanion: Bool = true) async {
        guard let client, !refreshing else { return }
        let current = generation
        refreshing = true
        defer { if current == generation { refreshing = false } }
        do {
            let hello = try await client.get("/api/hello", as: GatewayModels.Hello.self)
            try Task.checkCancellation()
            guard current == generation else { return }
            linkVersion = hello.companion_link
            device = hello.device
            online = true
            lastUpdated = .now
            connectionError = nil
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            clearLiveState()
            connectionError = error.localizedDescription
            return
        }

        if includeCompanion {
        do {
            // The gateway returns a complete snapshot for a cursor ahead of its sequence.
            // Full snapshots avoid retaining deleted fields from its sparse patch feed.
            let snapshot = try await client.get("/api/companion/events?since=999999999999&wait=0", as: GatewayModels.Companion.self)
            guard current == generation, !Task.isCancelled else { return }
            companion = snapshot
            companionError = nil
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            companion = nil
            companionError = error.localizedDescription
        }
        }
        if selected?.kind == .computer {
            do {
                let snapshot = try await client.get("/app/status", as: GatewayModels.Hub.self)
                guard current == generation, !Task.isCancelled else { return }
                hub = snapshot
                computerError = nil
            } catch {
                guard current == generation, !Task.isCancelled else { return }
                hub = nil
                computerError = error.localizedDescription
            }
        }
    }

    func monitor(includeCompanion: Bool, interactive: Bool) async {
        var failures = 0
        while !Task.isCancelled {
            await refresh(includeCompanion: includeCompanion)
            failures = online ? 0 : min(failures + 1, 4)
            do { try await Task.sleep(for: .seconds(RuntimePolicy.pollDelay(failures: failures, interactive: interactive))) }
            catch { return }
        }
    }

    func suspend() {
        // Invalidate every outstanding response, including manual refreshes outside the monitor task.
        generation = UUID()
        refreshing = false
        assistantRefreshing = false
        clearLiveState()
    }

    func refreshBoardLinks() async {
        guard supportsBoardLink, let client else { boardLinks = []; return }
        let current = generation
        do {
            let response = try await client.get("/api/companion/links", as: GatewayModels.BoardLinks.self)
            guard current == generation, !Task.isCancelled else { return }
            boardLinks = try response.validated()
            linksError = nil
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            boardLinks = []
            linksError = error.localizedDescription
        }
    }

    func linkBoard(code: String) async -> Bool {
        guard supportsBoardLink, !linkBusy, !busy, let client,
              linkRetryAt.map({ $0 <= .now }) ?? true else { return false }
        guard code.count == 6, code.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            linksError = "Enter the six-digit code from the board’s Phone screen."
            return false
        }
        let current = generation
        linkBusy = true
        defer { linkBusy = false }
        do {
            let response = try await client.post("/api/companion/link", body: ["code": code], as: GatewayModels.Linked.self)
            guard current == generation else { return false }
            try response.requireAssociation()
            record("Phone linked", "\(response.board.name) is associated with this phone. No control permissions were granted.")
            await refreshBoardLinks()
            return true
        } catch {
            guard current == generation else { return false }
            if case GatewayError.rateLimited(let seconds, _) = error { linkRetryAt = .now.addingTimeInterval(Double(seconds)) }
            linksError = error.localizedDescription + " Check the board before trying another code."
            return false
        }
    }

    func unlinkBoard(_ id: String) async {
        guard supportsBoardLink, !linkBusy, !busy, let client else { return }
        let current = generation
        linkBusy = true
        defer { linkBusy = false }
        do {
            let response = try await client.post("/api/companion/unlink", body: ["board": id], as: GatewayModels.Unlinked.self)
            guard current == generation else { return }
            guard response.ok, response.state == "unlinked" else { throw GatewayError.invalidResponse }
            await refreshBoardLinks()
        } catch {
            guard current == generation else { return }
            linksError = error.localizedDescription
        }
    }

    func command(_ command: CompanionCommand) async {
        guard canControl else { return }
        await perform(command.title) { client in
            try await client.post("/api/companion/command", body: ["cmd": command.rawValue], as: GatewayModels.Receipt.self)
        }
    }

    func requestControl() async {
        guard online, !busy, selected?.kind == .computer else { return }
        await perform("Control requested") { client in
            try await client.post("/api/ask-control", body: ["level": "full"], as: GatewayModels.Receipt.self)
        }
        // A request is not approval; /api/hello remains the source of permission state.
    }

    func decide(_ decision: GatewayModels.Companion.Decision, allow: Bool) async {
        guard canControl, companion?.agents?.top?.identity == decision.identity else {
            notice = "This decision changed. Refresh and review the current request."
            return
        }
        await perform(allow ? "Agent allowed" : "Agent denied") { client in
            try await client.decide(decision, allow: allow)
        }
        companion = nil
        await refresh()
    }

    func refreshAssistant() async {
        guard canUseAssistant, let client else { assistant = nil; return }
        guard !assistantRefreshing else { return }
        let current = generation
        assistantRefreshing = true
        defer { if current == generation { assistantRefreshing = false } }
        do {
            let response = try await client.get("/app/assistant", as: GatewayModels.Assistant.self)
            guard current == generation, !Task.isCancelled else { return }
            assistant = response
            assistantError = nil
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            assistant = nil
            assistantError = error.localizedDescription
        }
    }

    func assistantAction(_ action: String, text: String? = nil) async -> Bool {
        guard canUseAssistant, ["start", "stop", "show"].contains(action) else { return false }
        var body = ["action": action]
        if let text { body["text"] = text }
        let requestBody = body
        let success = await perform("Assistant: \(action)") { client in
            try await client.post("/app/assistant/do", body: requestBody, as: GatewayModels.Receipt.self)
        }
        await refreshAssistant()
        return success
    }

    @discardableResult
    private func perform(_ title: String, operation: (GatewayClient) async throws -> GatewayModels.Receipt) async -> Bool {
        guard let client, !busy, !linkBusy else { return false }
        let current = generation
        busy = true
        lastReceipt = nil
        defer { busy = false }
        do {
            let receipt = try await operation(client)
            try receipt.requireSuccess()
            guard current == generation else { return false }
            let detail = receipt.said ?? receipt.note ?? "The computer accepted the request."
            record(title, detail)
            lastReceipt = detail
            acceptedActionCount += 1
            return true
        } catch {
            guard current == generation else { return false }
            record(title, error.localizedDescription, failed: true)
            notice = error.localizedDescription + " If the connection was interrupted, check the computer before retrying."
            return false
        }
    }

    func forgetSelected() {
        guard let selected, !busy, !linkBusy else { return }
        do {
            try credentials.remove(selected.id)
            let remaining = profiles.filter { $0.id != selected.id }
            let data = try JSONEncoder().encode(remaining)
            profiles = remaining
            defaults.set(data, forKey: "native.connections")
            select(profiles.first?.id)
        } catch { notice = error.localizedDescription }
    }

    private func record(_ title: String, _ detail: String, failed: Bool = false) {
        activity.insert(ActivityEntry(title: title, detail: detail, failed: failed), at: 0)
        activity = Array(activity.prefix(60))
    }
}
