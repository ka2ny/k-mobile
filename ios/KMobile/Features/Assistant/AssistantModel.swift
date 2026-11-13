import Foundation
import Observation

/// The desktop Assistant, natively: the same /app/assistant the k-hole phone page reads, through the
/// one pairing. The phone starts tasks, stops them, refuses a step, answers a question, steers, queues
/// and replies in a conversation between assistants. It never allows a step or lets a task go on past a
/// limit: the computer answers those 403, and the app says to press it there and brings the window
/// forward. Every result is kept next to the control that sent it (`notes`), so nothing fails out of sight.
@MainActor @Observable
final class AssistantModel {
    /// Which control a result belongs to; the view puts the note right under that control.
    enum Spot: Hashable {
        case composer, stop, answerNow, steer, queue, show
        case confirm(String), question(String), unqueue(String), attach, history, chat, thread, memory
    }
    struct Note: Equatable { let text: String; let fail: Bool }
    struct Attachment: Identifiable, Equatable, Sendable { let id: String; let name: String; let size: Int }
    struct Persona: Identifiable, Equatable, Sendable { let id: String; let name: String; let about: String }

    private(set) var now: JSONValue?
    private(set) var loaded = false
    private(set) var readError: String?
    private(set) var history: [JSONValue] = []
    private(set) var goals: [AssistantGoal] = []
    private(set) var unseen = 0
    private(set) var assistants: [Persona] = []
    private(set) var defaultAssistant: String?
    private(set) var chat: JSONValue?
    private(set) var threads: [JSONValue] = []
    private(set) var thread: JSONValue?
    private(set) var memory: AssistantMemory?
    private(set) var importing = false
    private(set) var attachments: [Attachment] = []
    private(set) var notes: [Spot: Note] = [:]
    private(set) var busy: Set<Spot> = []
    var chosenAssistant: String?
    var search = ""

    private let app: AppModel
    private var watchTask: Task<Void, Never>?
    private var historyRefreshed = Date.distantPast

    private let originGateway: GatewayClient?
    private let originGeneration: UUID
    private var active = true
    private var lifecycle = UUID()
    private var requests: [Spot: UUID] = [:]
    private var refreshID = UUID()
    private var gateway: GatewayClient? { active && app.connectionGeneration == originGeneration ? originGateway : nil }

    init(app: AppModel, gateway: GatewayClient? = nil) {
        self.app = app
        originGateway = gateway ?? app.gateway
        originGeneration = app.connectionGeneration
    }

    private func begin(_ spot: Spot) -> UUID {
        let id = UUID(); requests[spot] = id; busy.insert(spot); return id
    }
    private func valid(_ spot: Spot, _ id: UUID) -> Bool {
        gateway != nil && requests[spot] == id && !Task.isCancelled
    }
    private func finish(_ spot: Spot, _ id: UUID) {
        if requests[spot] == id { busy.remove(spot) }
    }

    static let maxText = 2000
    static let maxFiles = 4
    static let maxBytes = 20 * 1024 * 1024

    // MARK: - The task in front

    var running: Bool { now?["running"]?.bool == true }
    var goal: String { now?["goal"]?.string ?? now?["title"]?.string ?? "" }
    var plan: [JSONValue] { now?["plan"]?.array ?? [] }
    var steps: [JSONValue] { now?["done"]?.array ?? [] }
    var findings: [String] { (now?["findings"]?.array ?? []).compactMap(\.string) }
    var confirm: JSONValue? { now?["confirm"].flatMap { $0.isNull ? nil : $0 } }
    var question: JSONValue? { now?["question"].flatMap { $0.isNull ? nil : $0 } }
    var paused: JSONValue? { now?["paused"].flatMap { $0.isNull ? nil : $0 } }
    var summary: JSONValue? { now?["summary"].flatMap { $0.isNull ? nil : $0 } }
    var queue: [JSONValue] { now?["queue"]?.array ?? [] }
    var answering: Bool { now?["answering"]?.truthy == true }
    var computerNote: Note? {
        guard let text = now?["note"]?["text"]?.string, !text.isEmpty else { return nil }
        return Note(text: text, fail: now?["note"]?["fail"]?.bool == true)
    }
    var assistantName: String { now?["assistant_name"]?.string ?? name(of: chosenAssistant) }

    func name(of id: String?) -> String {
        assistants.first { $0.id == (id ?? defaultAssistant) }?.name ?? "Assistant"
    }

    // MARK: - Watching

    /// Reads the task every 2 s while the page shows, as the phone page does; nothing runs when it's gone.
    func start() {
        guard watchTask == nil else { return }
        active = true
        watchTask = Task { [weak self] in
            await self?.loadHistory()
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                if Date().timeIntervalSince(self.historyRefreshed) >= 30 { await self.loadHistory() }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        watchTask?.cancel(); watchTask = nil
        active = false; requests = [:]; busy = []; refreshID = UUID(); lifecycle = UUID()
    }

    func refresh() async {
        guard let gateway = gateway else {
            readError = "Connect to your computer to use the Assistant."
            loaded = true
            return
        }
        let request = UUID(); refreshID = request
        do {
            let answer = try await gateway.get("/app/assistant", as: JSONValue.self)
            guard gateway === self.gateway, refreshID == request, !Task.isCancelled else { return }
            now = answer["now"]
            readError = nil
        } catch is CancellationError {
        } catch {
            guard gateway === self.gateway, refreshID == request, !Task.isCancelled else { return }
            readError = Self.words(error)
        }
        if gateway === self.gateway, refreshID == request, !Task.isCancelled { loaded = true }
    }

    func loadHistory() async {
        guard let gateway = gateway else { return }
        var path = "/app/assistant?history=1&goals=1"
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { path += "&q=" + Self.query(String(q.prefix(200))) }
        let request = begin(.history)
        historyRefreshed = Date()
        defer { finish(.history, request) }
        do {
            let answer = try await gateway.get(path, as: JSONValue.self)
            guard valid(.history, request) else { return }
            history = answer["history"]?.array ?? []
            goals = (answer["goals"]?.array ?? []).prefix(20).compactMap(AssistantGoal.init)
            historyRefreshed = Date()
            unseen = answer["unseen"]?.int ?? 0
            defaultAssistant = answer["default"]?.string
            assistants = (answer["assistants"]?.array ?? []).compactMap { a in
                guard let id = a["id"]?.string else { return nil }
                return Persona(id: id, name: a["name"]?.string ?? id, about: a["about"]?.string ?? "")
            }
            if let now = answer["now"] { self.now = now }
            notes[.history] = nil
        } catch is CancellationError {
        } catch {
            guard valid(.history, request) else { return }
            notes[.history] = Note(text: Self.words(error), fail: true)
        }
    }

    func openChat(_ id: String) async {
        guard let gateway = gateway, id.range(of: #"^t\d{8}-\d{6}-[0-9a-f]{4}$"#, options: .regularExpression) != nil
        else { return }
        chat = nil
        let request = begin(.chat)
        defer { finish(.chat, request) }
        do {
            let answer = try await gateway.get("/app/assistant?chat=" + id, as: JSONValue.self)
            guard valid(.chat, request) else { return }
            chat = answer["chat"]
            notes[.chat] = nil
        } catch {
            guard valid(.chat, request) else { return }
            notes[.chat] = Note(text: Self.words(error), fail: true)
        }
    }

    func loadThreads() async {
        guard let gateway = gateway else { return }
        let request = begin(.thread)
        defer { finish(.thread, request) }
        do {
            let answer = try await gateway.get("/app/assistant?threads=1", as: JSONValue.self)
            guard valid(.thread, request) else { return }
            threads = answer["threads"]?.array ?? []
            notes[.thread] = nil
        } catch {
            guard valid(.thread, request) else { return }
            notes[.thread] = Note(text: Self.words(error), fail: true)
        }
    }

    func openThread(_ id: String) async {
        guard let gateway = gateway, id.range(of: #"^h[0-9a-f]{10}$"#, options: .regularExpression) != nil
        else { return }
        thread = nil
        let request = begin(.thread)
        defer { finish(.thread, request) }
        do {
            let answer = try await gateway.get("/app/assistant?thread=" + id, as: JSONValue.self)
            guard valid(.thread, request) else { return }
            thread = answer["thread"] ?? answer
            notes[.thread] = nil
        } catch {
            guard valid(.thread, request) else { return }
            notes[.thread] = Note(text: Self.words(error), fail: true)
        }
    }

    // MARK: - Taps

    /// Starts a task; with `follow`, it goes on in the open chat.
    @discardableResult
    func startTask(_ text: String, follow: String? = nil) async -> Bool {
        guard !busy.contains(.attach), !importing else { return false }
        var body: [String: JSONValue] = ["text": .string(Self.clip(text))]
        if let a = chosenAssistant { body["assistant"] = .string(a) }
        if let follow { body["follow"] = .string(follow) }
        if !attachments.isEmpty { body["attach"] = .array(attachments.map { .string($0.id) }) }
        let ok = await act("start", body, spot: .composer)
        if ok { attachments = [] }
        return ok
    }

    func stopTask() async { await act("stop", [:], spot: .stop) }
    func answerNow() async { await act("answer-now", [:], spot: .answerNow) }
    func deny(_ id: String) async { await act("deny", ["id": .string(id)], spot: .confirm(id)) }
    func answer(_ id: String, _ text: String) async {
        await act("answer", ["id": .string(id), "text": .string(Self.clip(text))], spot: .question(id))
    }
    @discardableResult
    func steer(_ text: String) async -> Bool { await act("steer", ["text": .string(Self.clip(text))], spot: .steer) }
    @discardableResult
    func enqueue(_ text: String, asNew: Bool) async -> Bool {
        await act("queue", ["text": .string(Self.clip(text)), "new": .bool(asNew)], spot: .queue)
    }
    func unqueue(_ id: String) async { await act("unqueue", ["id": .string(id)], spot: .unqueue(id)) }
    /// Brings the Assistant's window forward on the computer, where Allow and Keep going are pressed.
    func showOnComputer(for spot: Spot = .show) async {
        if await act("show", [:], spot: spot, quietOK: true) {
            notes[spot] = Note(text: "The Assistant's window is in front on your computer. Press Allow there, or open Remote to press it from here.", fail: false)
        }
    }
    @discardableResult
    func replyInThread(_ id: String, _ text: String) async -> Bool {
        let ok = await act("thread-reply", ["id": .string(id), "text": .string(Self.clip(text))], spot: .thread)
        if ok { await openThread(id) }
        return ok
    }

    @discardableResult
    private func act(_ action: String, _ extra: [String: JSONValue], spot: Spot, quietOK: Bool = false) async -> Bool {
        guard let gateway = gateway else {
            notes[spot] = Note(text: "Connect to your computer first.", fail: true)
            return false
        }
        guard !busy.contains(spot) else { return false }
        let request = begin(spot)
        defer { finish(spot, request) }
        var body = extra
        body["action"] = .string(action)
        do {
            let answer = try await gateway.send("/app/assistant/do", json: JSONValue.object(body), as: JSONValue.self)
            guard valid(spot, request) else { return false }
            let ok = answer["ok"]?.bool != false
            let words = answer["note"]?.string ?? ""
            if !ok {
                notes[spot] = Note(text: words.isEmpty ? "The computer didn't take that." : words, fail: true)
            } else if !quietOK {
                notes[spot] = words.isEmpty ? nil : Note(text: words, fail: false)
            }
            await refresh()
            return ok && valid(spot, request)
        } catch {
            guard valid(spot, request) else { return false }
            notes[spot] = Note(text: Self.words(error), fail: true)
            await refresh()
            return false
        }
    }

    // MARK: - Files from the phone

    func attach(_ data: Data, name: String) async {
        guard let gateway, !busy.contains(.attach), !busy.contains(.composer) else { return }
        guard attachments.count < Self.maxFiles else {
            notes[.attach] = Note(text: "Four files at most go with one task.", fail: true)
            return
        }
        let total = attachments.reduce(0) { $0 + $1.size } + data.count
        guard total <= Self.maxBytes else {
            notes[.attach] = Note(text: "Files for one task can be 20 MB together. That one doesn't fit.", fail: true)
            return
        }
        let request = begin(.attach)
        defer { finish(.attach, request) }
        do {
            let answer = try await gateway.upload(
                "/app/assistant/attach?name=" + Self.query(String(name.prefix(120))), data: data, as: JSONValue.self)
            guard valid(.attach, request) else { return }
            guard let id = answer["id"]?.string else { throw GatewayError.invalidResponse }
            attachments.append(Attachment(id: id, name: answer["name"]?.string ?? name, size: answer["size"]?.int ?? data.count))
            notes[.attach] = nil
        } catch {
            guard valid(.attach, request) else { return }
            notes[.attach] = Note(text: Self.words(error), fail: true)
        }
    }

    func unattach(_ id: String) async {
        guard let gateway, !busy.contains(.attach), !busy.contains(.composer), !importing else { return }
        let request = begin(.attach)
        defer { finish(.attach, request) }
        do {
            _ = try await gateway.send("/app/assistant/unattach", json: JSONValue.object(["id": .string(id)]), as: JSONValue.self)
            guard valid(.attach, request) else { return }
            attachments.removeAll { $0.id == id }
            notes[.attach] = nil
        } catch {
            guard valid(.attach, request) else { return }
            notes[.attach] = Note(text: Self.words(error), fail: true)
        }
    }

    func loadMemory(_ persona: String) async {
        guard let gateway else { return }
        memory = nil
        let request = begin(.memory)
        defer { finish(.memory, request) }
        do {
            let answer = try await gateway.get("/app/assistant?memory=" + Self.query(persona), as: JSONValue.self)
            guard valid(.memory, request) else { return }
            guard let value = answer["memory"], !value.isNull else { throw GatewayError.invalidResponse }
            memory = AssistantMemory(value)
            notes[.memory] = nil
        } catch {
            guard valid(.memory, request) else { return }
            notes[.memory] = Note(text: Self.words(error), fail: true)
        }
    }

    func attachmentError(_ error: Error) { notes[.attach] = Note(text: Self.words(error), fail: true) }

    func importFiles(_ urls: [URL]) async {
        guard gateway != nil, !importing, !busy.contains(.attach), !busy.contains(.composer) else { return }
        importing = true
        let operation = lifecycle
        defer { importing = false }
        for url in urls {
            guard operation == lifecycle, gateway != nil, !Task.isCancelled else { return }
            let remaining = Self.maxBytes - attachments.reduce(0) { $0 + $1.size }
            guard attachments.count < Self.maxFiles else {
                notes[.attach] = Note(text: "A task can have up to four files.", fail: true); return
            }
            do {
                let data = try await Task.detached { try AssistantAttachment.read(url, limit: remaining) }.value
                guard operation == lifecycle, gateway != nil, !Task.isCancelled else { return }
                await attach(data, name: url.lastPathComponent)
                if notes[.attach]?.fail == true { return }
            } catch {
                guard operation == lifecycle, gateway != nil, !Task.isCancelled else { return }
                attachmentError(error); return
            }
        }
    }

    func clearNote(_ spot: Spot) { notes[spot] = nil }

    // MARK: - Words

    static func clip(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxText))
    }

    static func query(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    /// The computer's refusals in plain words: 403 Allow/continue, 409 a gone card or a question open there.
    nonisolated static func words(_ error: Error) -> String {
        switch error {
        case GatewayError.http(409, let message):
            return message.isEmpty ? "That changed on the computer before your tap arrived." : message
        case GatewayError.http(403, let message):
            return message.isEmpty ? "The computer refused that from the phone." : message
        case let e as URLError where e.code == .notConnectedToInternet:
            return "This phone is offline."
        case let e as URLError where e.code == .timedOut:
            return "Your computer didn't answer in time."
        default:
            return error.localizedDescription
        }
    }
}
