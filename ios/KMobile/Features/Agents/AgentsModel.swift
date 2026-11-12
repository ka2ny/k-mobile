import Foundation
import Observation

/// Agents on the phone, natively: the same /agents/api the k-hole phone app's page uses, through the
/// one pairing. Every command carries the agent's generation, so a decision or a message never lands on
/// an agent that moved on. Results are kept per control (`rowNote`, `composeNote`, `createNote`...), so
/// nothing fails out of sight.
@MainActor @Observable
final class AgentsModel {
    struct Host: Identifiable, Equatable, Sendable { let id: String; let name: String; let origin: String }
    struct Workplace: Identifiable, Equatable, Sendable { let id: String; let name: String; let path: String }

    /// What sending a message is doing now, said under the composer.
    enum ComposeState: Equatable { case idle, waiting(Int), sending, sent, failed(String) }

    private(set) var rows: [AgentRow] = []
    private(set) var listError: String?
    private(set) var unpaired = false
    private(set) var loaded = false
    private(set) var status: JSONValue?
    private(set) var hosts: [Host] = []
    private(set) var hostID: String?
    private(set) var hostNote: String?
    private(set) var replies: [AgentReply] = []
    private(set) var repliesNote: String?
    private(set) var workplaces: [Workplace] = []
    private(set) var workplacesNote: String?
    private(set) var openID: String?
    private(set) var openError: String?
    private(set) var compose: ComposeState = .idle
    private(set) var createNote: String?
    private(set) var creating = false
    private(set) var changes: [AgentDiffFile] = []
    private(set) var changesNote: String?
    private(set) var changesLoading = false
    /// Per agent (or per decision id): its own line, and what's running for it.
    private(set) var rowNote: [String: String] = [:]
    private(set) var busyRows: Set<String> = []
    /// Drafts kept per agent while you look elsewhere, and after a create that timed out.
    var drafts: [String: String] = [:]

    private let app: AppModel
    private let defaults: UserDefaults
    private var relay: (connector: String, access: JSONValue, device: String)?
    private var seen: [String: Double] = [:]
    private var listTask: Task<Void, Never>?
    private var openTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var createTask: Task<Void, Never>?

    private let originGateway: GatewayClient?
    private let originGeneration: UUID
    private var revision = UUID()
    private var hostDrafts: [String: [String: String]] = [:]
    private var gateway: GatewayClient? { app.connectionGeneration == originGeneration ? originGateway : nil }

    init(app: AppModel, defaults: UserDefaults = .standard, gateway: GatewayClient? = nil) {
        self.app = app
        self.defaults = defaults
        self.originGateway = gateway ?? app.gateway
        self.originGeneration = app.connectionGeneration
    }

    var open: AgentRow? { rows.first { $0.id == openID } }
    var hostName: String { hosts.first { $0.id == hostID }?.name ?? "This computer" }
    var summary: String { AgentLogic.summary(rows) }
    var engines: [String] { AgentLogic.createEngines(status) }
    var groups: [(state: String, title: String, rows: [AgentRow])] {
        AgentLogic.order.compactMap { state in
            let list = rows.filter { $0.state == state }
            return list.isEmpty ? nil : (state, AgentLogic.titles[state] ?? state, list)
        }
    }

    // MARK: - Paths

    private func api(_ path: String, here: Bool = false) -> String {
        guard !here, let hostID else { return "/agents/api/" + path }
        return "/agents/api/hosts/" + BeamModel.segment(hostID) + "/proxy/" + path
    }
    private var seenKey: String { "agents.seen." + (hostID ?? status?["connector"]?.string ?? "here") }

    // MARK: - Watching

    /// Reads the list until the view goes; the page's own rhythm (2.5 s relayed, 5 s here, 4 s off).
    func start() {
        guard listTask == nil else { return }
        listTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let pause: Double = self.gateway == nil ? 4 : (self.hostID == nil ? 5 : 2.5)
                try? await Task.sleep(for: .seconds(pause))
            }
        }
    }

    func stop() {
        revision = UUID()
        sendTask?.cancel(); sendTask = nil
        createTask?.cancel(); createTask = nil
        compose = .idle; creating = false; busyRows = []
        listTask?.cancel(); listTask = nil
        openTask?.cancel(); openTask = nil
    }

    func refresh() async {
        guard let gateway = gateway else {
            listError = "Connect to your computer to see your agents."
            return
        }
        let generation = app.connectionGeneration
        let current = revision
        do {
            if status == nil || hostID == nil {
                let s = try await gateway.get(api("status", here: true), as: JSONValue.self)
                guard generation == app.connectionGeneration, current == revision else { return }
                status = s
                if seen.isEmpty { loadSeen() }
            }
            let answer = try await gateway.get(api("sessions"), as: JSONValue.self)
            guard generation == app.connectionGeneration, current == revision else { return }
            let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var next = (answer["sessions"]?.array ?? []).map { AgentLogic.mergeSummary(byID[$0["id"]?.string ?? ""], $0, seen: seen) }
            // Keep a row we just made until the list knows it.
            for r in rows where creating && r.id == openID && !next.contains(where: { $0.id == r.id }) { next.append(r) }
            if hostID != nil {
                // A relayed computer's list has no decisions; read the cards of the ones that might.
                for (i, r) in next.enumerated().filter({ ["working", "needs"].contains($0.element.state) }).prefix(6) {
                    if let d = try? await gateway.get(api("sessions/" + BeamModel.segment(r.id)), as: JSONValue.self) {
                        guard current == revision, generation == app.connectionGeneration else { return }
                        next[i] = AgentLogic.applyCard(next[i], .object(["control": d, "status": d["status"] ?? .null]))
                    }
                }
                guard generation == app.connectionGeneration, current == revision else { return }
            }
            rows = AgentLogic.sortRows(next)
            listError = nil
            unpaired = false
            loaded = true
        } catch is CancellationError {
        } catch {
            guard generation == app.connectionGeneration, current == revision else { return }
            let code = AgentLogic.code(error)
            unpaired = code == "PAIR_REQUIRED" || code == "REVOKED"
            if code == "WRONG_CONNECTOR" || code == "HOST_ACCESS_CHANGED" { relay = nil; status = nil }
            listError = AgentLogic.words(error)
            loaded = true
        }
    }

    // MARK: - One agent

    func show(_ id: String?) {
        openTask?.cancel(); openTask = nil
        openID = id
        openError = nil
        compose = .idle
        changes = []; changesNote = nil
        guard let id else { return }
        markSeen(id)
        openTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.openID == id else { return }
                await self.reload(id)
                let r = self.open
                let fast = r.map { ["working", "needs"].contains($0.state) || $0.engine == "omp" } ?? false
                try? await Task.sleep(for: .seconds(fast ? 2.5 : 8))
            }
        }
    }

    func reload(_ id: String) async {
        guard let gateway = gateway else { openError = "Connect to your computer first."; return }
        let generation = app.connectionGeneration
        let current = revision
        do {
            let card = try await gateway.get(api("sessions/" + BeamModel.segment(id)), as: JSONValue.self)
            guard generation == app.connectionGeneration, current == revision, openID == id else { return }
            let control = card["control"] ?? card
            let base = rows.first { $0.id == id } ?? AgentLogic.row(card["session"] ?? card, seen: seen)
            let next = AgentLogic.applyCard(base, .object(["control": control, "status": card["status"] ?? control["status"] ?? .null]))
            if let i = rows.firstIndex(where: { $0.id == id }) { rows[i] = next } else { rows.append(next) }
            rows = AgentLogic.sortRows(rows)
            openError = nil
        } catch is CancellationError {
        } catch {
            guard generation == app.connectionGeneration, current == revision, openID == id else { return }
            if AgentLogic.code(error) == "SESSION_NOT_FOUND" {
                rowNote[id] = AgentLogic.words(code: "SESSION_NOT_FOUND")
                rows.removeAll { $0.id == id }
                show(nil)
                return
            }
            openError = AgentLogic.words(error)
        }
    }

    // MARK: - Commands

    private struct CommandContext {
        let gateway: GatewayClient
        let revision: UUID
        let prefix: String
        let local: Bool
    }

    private func check(_ context: CommandContext) throws {
        try Task.checkCancellation()
        guard context.revision == revision, gateway === context.gateway else { throw CancellationError() }
    }

    private func stamp(_ body: [String: JSONValue], context: CommandContext) async throws -> JSONValue {
        try check(context)
        var body = body
        if context.local {
            if status == nil {
                let answer = try await context.gateway.get(context.prefix + "status", as: JSONValue.self)
                try check(context)
                status = answer
            }
            body["connector"] = status?["connector"] ?? .null
        } else {
            if relay == nil {
                let answer = try await context.gateway.get(context.prefix + "status", as: JSONValue.self)
                try check(context)
                relay = (answer["connector"]?.string ?? "", answer["relayAccess"] ?? answer["revision"] ?? .null,
                         answer["deviceId"]?.string ?? "")
            }
            body["connector"] = .string(relay?.connector ?? "")
            body["relayAccess"] = relay?.access ?? .null
        }
        return .object(body)
    }

    /// The gateway, relay host and connector stamp belong to one immutable operation context.
    @discardableResult
    private func command(_ kind: String, _ id: String, payload: [String: JSONValue] = [:],
                         generation: JSONValue? = nil) async throws -> JSONValue {
        try Task.checkCancellation()
        guard let gateway else { throw AgentFailure(code: "OFFLINE") }
        let context = CommandContext(gateway: gateway, revision: revision, prefix: api(""), local: hostID == nil)
        let intent = UUID().uuidString.lowercased()
        let gen = generation ?? rows.first { $0.id == id }?.generation ?? .string("")
        let body = try await stamp(["id": .string(intent), "kind": .string(kind), "session": .string(id),
                                    "generation": gen, "payload": .object(payload)], context: context)
        try check(context)
        var answer: JSONValue
        do {
            answer = try await gateway.command(context.prefix + "commands", json: body, as: JSONValue.self)
        } catch {
            try check(context)
            let code = AgentLogic.code(error)
            if code == "HOST_ACCESS_CHANGED" || code == "WRONG_CONNECTOR" { relay = nil; status = nil }
            let unsure: Set<String> = ["OFFLINE", "OUTCOME_UNKNOWN", "HOST_COMMAND_OUTCOME_UNKNOWN", "HOST_UNAVAILABLE"]
            guard kind == "resume", unsure.contains(code),
                  let receipt = try? await gateway.get(context.prefix + "intents/" + BeamModel.segment(intent), as: JSONValue.self),
                  receipt["intent"]?["id"]?.string == intent, let found = receipt["intent"] else { throw error }
            answer = found
        }
        try check(context)
        let state = answer["state"]?.string ?? answer["intent"]?["state"]?.string
        if state == "unknown" { throw AgentFailure(code: "OUTCOME_UNKNOWN") }
        if state == "failed" { throw AgentFailure(code: "COMMAND_FAILED") }
        return answer
    }

    /// Runs one command for a row, keeping its result on that row.
    private func act(_ id: String, key: String? = nil, _ title: String, _ done: String,
                     _ run: @escaping () async throws -> Void) async -> Bool {
        let key = key ?? id
        guard !busyRows.contains(key) else { return false }
        busyRows.insert(key); rowNote[key] = nil
        let generation = app.connectionGeneration
        let current = revision
        defer { if current == revision { busyRows.remove(key) } }
        do {
            try await run()
            guard generation == app.connectionGeneration, current == revision else { return false }
            rowNote[key] = done
            app.recordActivity(title, done)
            await reload(id)
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard generation == app.connectionGeneration, current == revision else { return false }
            let words = AgentLogic.words(error)
            rowNote[key] = words
            app.recordActivity(title, words, failed: true)
            return false
        }
    }

    func decide(_ row: AgentRow, allow: Bool) async {
        guard let d = row.decision else { return }
        _ = await act(row.id, key: "decision:" + d.id, allow ? "Allowed" : "Denied",
                      allow ? "Allowed. The agent goes on." : "Denied. The agent was told no.") { [self] in
            try await command("permission", row.id, payload: ["allow": .bool(allow), "permission": .string(d.id)],
                              generation: d.generation)
        }
    }

    func stopAgent(_ row: AgentRow) async {
        _ = await act(row.id, "Stopped \(row.name)", "Stopped.") { [self] in try await command("stop", row.id) }
    }

    func resume(_ row: AgentRow) async {
        _ = await act(row.id, "Resumed \(row.name)", "Resumed.") { [self] in try await command("resume", row.id) }
    }

    func joinCodex(_ row: AgentRow) async {
        _ = await act(row.id, "Joined \(row.name)", "Joined: you can write to it now.") { [self] in
            try await command("join-codex", row.id, generation: .string(""))
        }
    }

    func rename(_ row: AgentRow, to name: String) async {
        let name = AgentLogic.clip(name, 80)
        guard !name.isEmpty else { rowNote[row.id] = "Give it a name first."; return }
        _ = await act(row.id, key: "rename:" + row.id, "Renamed an agent", "Renamed.") { [self] in
            try await command("rename", row.id, payload: ["name": .string(name)])
        }
    }

    func configure(_ row: AgentRow, option: String, value: JSONValue) async {
        guard let revision = row.configuration?["revision"] else { return }
        _ = await act(row.id, key: "configure:" + option, "Changed a setting", "Changed.") { [self] in
            try await command("configure", row.id, payload: ["option": .string(option), "value": value, "revision": revision])
        }
    }

    func answer(_ row: AgentRow, draft: [String: (selected: [String], custom: String)]) async -> Bool {
        guard let q = row.question, let qid = q["id"]?.string else { return false }
        guard let answers = AgentLogic.questionAnswers(q, draft) else {
            rowNote["question:" + qid] = AgentLogic.words(code: "INVALID_ANSWER")
            return false
        }
        return await act(row.id, key: "question:" + qid, "Answered a question", "Answered.") { [self] in
            try await command("answer", row.id, payload: ["question": .string(qid), "answers": answers],
                              generation: q["generation"] ?? row.generation)
            if let i = rows.firstIndex(where: { $0.id == row.id }) { rows[i].question = nil }
        }
    }

    // MARK: - Writing to an agent

    /// Sends after three seconds, so Undo can take it back; the words stay in the draft until it went.
    func send(_ row: AgentRow, text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...16000).contains(text.count) else { compose = .failed(AgentLogic.words(code: "EMPTY_OR_LONG_MESSAGE")); return }
        guard AgentLogic.can(row, "send") else { compose = .failed("It can't take a message right now."); return }
        sendTask?.cancel()
        let id = row.id
        drafts[id] = text
        let current = revision
        sendTask = Task { [weak self] in
            for left in stride(from: 3, to: 0, by: -1) {
                self?.compose = .waiting(left)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            guard let self, current == self.revision else { return }
            self.compose = .sending
            do {
                try await self.command("send", id, payload: ["text": .string(text)])
                guard !Task.isCancelled else { return }
                self.drafts[id] = nil
                self.compose = .sent
                self.app.recordActivity("Sent to \(row.name)", AgentLogic.clip(text, 60))
                await self.reload(id)
            } catch is CancellationError {
            } catch {
                guard current == self.revision, !Task.isCancelled else { return }
                self.compose = .failed(AgentLogic.words(error))
                self.app.recordActivity("Couldn't send to \(row.name)", AgentLogic.words(error), failed: true)
            }
        }
    }

    func undoSend() {
        guard case .waiting = compose else { return }
        sendTask?.cancel(); sendTask = nil
        compose = .idle
    }

    // MARK: - Starting an agent

    func loadWorkplaces() async {
        guard let gateway = gateway else { workplacesNote = "Connect to your computer first."; return }
        let generation = app.connectionGeneration
        let current = revision
        var list: [Workplace] = [], after: String?
        do {
            for _ in 0..<5 {
                let page = try await gateway.get(BeamModel.path(api("workplaces"), after.map { ["after": $0] } ?? [:]),
                                                 as: JSONValue.self)
                guard current == revision, generation == app.connectionGeneration else { return }
                list += (page["items"]?.array ?? []).compactMap { w in
                    guard let id = w["id"]?.string else { return nil }
                    let path = w["path"]?.string ?? ""
                    return Workplace(id: id, name: w["name"]?.string ?? AgentLogic.baseName(path), path: path)
                }
                after = page["next"]?.string
                if after == nil { break }
            }
            guard generation == app.connectionGeneration, current == revision else { return }
            workplaces = list
            workplacesNote = list.isEmpty ? "No projects yet. Add one in Agents on your computer." : nil
        } catch {
            guard generation == app.connectionGeneration, current == revision else { return }
            workplacesNote = AgentLogic.words(error)
        }
    }

    /// Makes the agent, opens it, waits until it takes words (30 s at most) and sends the first ones once.
    /// It never makes a second agent: a wait that runs out keeps the words as that agent's draft.
    func create(workplace: Workplace, engine: String, firstMessage: String) {
        guard !creating else { return }
        creating = true; createNote = nil
        let first = firstMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = revision
        createTask = Task { [weak self] in
            guard let self, current == self.revision, !Task.isCancelled else { return }
            defer { if current == self.revision { self.creating = false } }
            do {
                let name = AgentLogic.agentName(first, project: workplace.name)
                let id0 = UUID().uuidString.lowercased()
                let answer = try await self.command("create", id0, payload: [
                    "workplaceId": .string(workplace.id), "engine": .string(engine), "name": .string(name),
                ], generation: .string(""))
                let id = answer["session"]?.string ?? answer["result"]?["session"]?.string ?? id0
                var row = AgentLogic.row(.object(["id": .string(id), "name": .string(name), "cwd": .string(workplace.path),
                                                  "engine": .string(engine), "status": .string("connecting")]), seen: self.seen)
                row.state = "working"
                if !self.rows.contains(where: { $0.id == id }) { self.rows.insert(row, at: 0) }
                self.show(id)
                self.app.recordActivity("Started \(name)", AgentLogic.engines[engine] ?? engine)
                guard !first.isEmpty else { return }
                let deadline = Date.now.addingTimeInterval(30)
                while Date.now < deadline {
                    try await Task.sleep(for: .milliseconds(600))
                    await self.reload(id)
                    if let r = self.rows.first(where: { $0.id == id }), r.generation != nil, r.controllable, r.state != "working" {
                        self.send(r, text: first)
                        return
                    }
                }
                self.drafts[id] = first
                self.createNote = "It started but isn't ready for words yet. Your message is kept below; send it when it's ready."
            } catch is CancellationError {
            } catch {
                guard current == self.revision, !Task.isCancelled else { return }
                self.createNote = AgentLogic.words(error)
                self.app.recordActivity("Couldn't start an agent", AgentLogic.words(error), failed: true)
            }
        }
    }

    // MARK: - Changes

    func loadChanges(_ row: AgentRow) async {
        guard let gateway = gateway else { changesNote = "Connect to your computer first."; return }
        changesLoading = true; changesNote = nil
        let generation = app.connectionGeneration
        let current = revision
        defer { if current == revision { changesLoading = false } }
        do {
            let answer = try await gateway.command(api("changes/" + BeamModel.segment(row.id) + "?view=unstaged"),
                                                   json: [String: String](), as: JSONValue.self)
            guard generation == app.connectionGeneration, current == revision else { return }
            let text = answer["diff"]?.string ?? answer["text"]?.string ?? ""
            changes = AgentLogic.parseDiff(text) + AgentLogic.parseUntracked(answer["untracked"]?.string ?? text)
            changesNote = nil
        } catch {
            guard generation == app.connectionGeneration, current == revision else { return }
            changesNote = AgentLogic.words(error)
        }
    }

    // MARK: - Quick replies

    func loadReplies() async {
        guard let gateway = gateway else { return }
        let current = revision
        do {
            let answer = try await gateway.get(api("replies", here: true), as: JSONValue.self)
            guard current == revision, self.gateway != nil else { return }
            replies = AgentLogic.validReplies((answer["replies"]?.array ?? []).compactMap {
                guard let l = $0["label"]?.string, let t = $0["text"]?.string else { return nil }
                return AgentReply(label: l, text: t)
            })
            repliesNote = nil
        } catch { guard current == revision, self.gateway != nil else { return }; repliesNote = AgentLogic.words(error) }
    }

    func saveReplies(_ list: [AgentReply]?) async {
        guard let gateway = gateway else { repliesNote = "Connect to your computer first."; return }
        let current = revision
        let body: JSONValue = list.map { .object(["replies": .array(AgentLogic.validReplies($0).map {
            .object(["label": .string($0.label), "text": .string($0.text)])
        })]) } ?? .object(["reset": .bool(true)])
        do {
            let answer = try await gateway.send(api("replies", here: true), json: body, as: JSONValue.self)
            guard current == revision, self.gateway != nil else { return }
            replies = AgentLogic.validReplies((answer["replies"]?.array ?? []).compactMap {
                guard let l = $0["label"]?.string, let t = $0["text"]?.string else { return nil }
                return AgentReply(label: l, text: t)
            })
            repliesNote = list == nil ? "Back to the usual replies." : "Saved for every phone."
        } catch { guard current == revision, self.gateway != nil else { return }; repliesNote = AgentLogic.words(error) }
    }

    // MARK: - Computers

    func loadHosts() async {
        guard let gateway = gateway else { return }
        let current = revision
        do {
            let answer = try await gateway.get(api("hosts", here: true), as: JSONValue.self)
            guard current == revision, self.gateway != nil else { return }
            hosts = (answer["items"]?.array ?? []).compactMap {
                guard let id = $0["id"]?.string else { return nil }
                return Host(id: id, name: $0["name"]?.string ?? "Computer", origin: $0["origin"]?.string ?? "")
            }
            hostNote = nil
        } catch { guard current == revision, self.gateway != nil else { return }; hostNote = AgentLogic.words(error) }
    }

    func pickHost(_ id: String?) async {
        guard id != hostID else { return }
        stop()
        hostDrafts[hostID ?? ""] = drafts
        show(nil)
        hostID = id
        drafts = hostDrafts[id ?? ""] ?? [:]
        rowNote = [:]; workplaces = []; workplacesNote = nil; createNote = nil
        relay = nil
        rows = []; loaded = false; listError = nil
        loadSeen()
        start()
        await refresh()
    }

    // MARK: - Seen

    private func loadSeen() {
        seen = (defaults.dictionary(forKey: seenKey) as? [String: Double]) ?? [:]
    }

    private func markSeen(_ id: String) {
        seen[id] = Date.now.timeIntervalSince1970 * 1000
        if seen.count > 400 { seen = Dictionary(uniqueKeysWithValues: seen.sorted { $0.value > $1.value }.prefix(300).map { $0 }) }
        defaults.set(seen, forKey: seenKey)
        if let i = rows.firstIndex(where: { $0.id == id }) { rows[i].unseen = false }
    }
}
