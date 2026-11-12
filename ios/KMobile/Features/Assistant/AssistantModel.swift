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
        case confirm(String), question(String), unqueue(String), attach, history, chat, thread
    }
    struct Note: Equatable { let text: String; let fail: Bool }
    struct Attachment: Identifiable, Equatable, Sendable { let id: String; let name: String; let size: Int }
    struct Persona: Identifiable, Equatable, Sendable { let id: String; let name: String; let about: String }

    private(set) var now: JSONValue?
    private(set) var loaded = false
    private(set) var readError: String?
    private(set) var history: [JSONValue] = []
    private(set) var unseen = 0
    private(set) var assistants: [Persona] = []
    private(set) var defaultAssistant: String?
    private(set) var chat: JSONValue?
    private(set) var threads: [JSONValue] = []
    private(set) var thread: JSONValue?
    private(set) var attachments: [Attachment] = []
    private(set) var notes: [Spot: Note] = [:]
    private(set) var busy: Set<Spot> = []
    var chosenAssistant: String?
    var search = ""

    private let app: AppModel
    private var watchTask: Task<Void, Never>?

    init(app: AppModel) { self.app = app }

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
        watchTask = Task { [weak self] in
            await self?.loadHistory()
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() { watchTask?.cancel(); watchTask = nil }

    func refresh() async {
        guard let gateway = app.gateway else {
            readError = "Connect to your computer to use the Assistant."
            loaded = true
            return
        }
        let generation = app.connectionGeneration
        do {
            let answer = try await gateway.get("/app/assistant", as: JSONValue.self)
            guard generation == app.connectionGeneration else { return }
            now = answer["now"]
            readError = nil
        } catch is CancellationError {
        } catch {
            guard generation == app.connectionGeneration else { return }
            readError = Self.words(error)
        }
        loaded = true
    }

    func loadHistory() async {
        guard let gateway = app.gateway else { return }
        var path = "/app/assistant?history=1"
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { path += "&q=" + Self.query(String(q.prefix(200))) }
        busy.insert(.history)
        defer { busy.remove(.history) }
        do {
            let answer = try await gateway.get(path, as: JSONValue.self)
            history = answer["history"]?.array ?? []
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
            notes[.history] = Note(text: Self.words(error), fail: true)
        }
    }

    func openChat(_ id: String) async {
        guard let gateway = app.gateway, id.range(of: #"^t\d{8}-\d{6}-[0-9a-f]{4}$"#, options: .regularExpression) != nil
        else { return }
        chat = nil
        busy.insert(.chat)
        defer { busy.remove(.chat) }
        do {
            chat = try await gateway.get("/app/assistant?chat=" + id, as: JSONValue.self)["chat"]
            notes[.chat] = nil
        } catch {
            notes[.chat] = Note(text: Self.words(error), fail: true)
        }
    }

    func loadThreads() async {
        guard let gateway = app.gateway else { return }
        do {
            threads = try await gateway.get("/app/assistant?threads=1", as: JSONValue.self)["threads"]?.array ?? []
            notes[.thread] = nil
        } catch {
            notes[.thread] = Note(text: Self.words(error), fail: true)
        }
    }

    func openThread(_ id: String) async {
        guard let gateway = app.gateway, id.range(of: #"^h[0-9a-f]{10}$"#, options: .regularExpression) != nil
        else { return }
        do {
            let answer = try await gateway.get("/app/assistant?thread=" + id, as: JSONValue.self)
            thread = answer["thread"] ?? answer
            notes[.thread] = nil
        } catch {
            notes[.thread] = Note(text: Self.words(error), fail: true)
        }
    }

    // MARK: - Taps

    /// Starts a task; with `follow`, it goes on in the open chat.
    @discardableResult
    func startTask(_ text: String, follow: String? = nil) async -> Bool {
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
        guard let gateway = app.gateway else {
            notes[spot] = Note(text: "Connect to your computer first.", fail: true)
            return false
        }
        guard !busy.contains(spot) else { return false }
        busy.insert(spot)
        defer { busy.remove(spot) }
        var body = extra
        body["action"] = .string(action)
        do {
            let answer = try await gateway.send("/app/assistant/do", json: JSONValue.object(body), as: JSONValue.self)
            let ok = answer["ok"]?.bool != false
            let words = answer["note"]?.string ?? ""
            if !ok {
                notes[spot] = Note(text: words.isEmpty ? "The computer didn't take that." : words, fail: true)
            } else if !quietOK {
                notes[spot] = words.isEmpty ? nil : Note(text: words, fail: false)
            }
            await refresh()
            return ok
        } catch {
            notes[spot] = Note(text: Self.words(error), fail: true)
            await refresh()
            return false
        }
    }

    // MARK: - Files from the phone

    func attach(_ data: Data, name: String) async {
        guard let gateway = app.gateway else { return }
        guard attachments.count < Self.maxFiles else {
            notes[.attach] = Note(text: "Four files at most go with one task.", fail: true)
            return
        }
        let total = attachments.reduce(0) { $0 + $1.size } + data.count
        guard total <= Self.maxBytes else {
            notes[.attach] = Note(text: "Files for one task can be 20 MB together. That one doesn't fit.", fail: true)
            return
        }
        busy.insert(.attach)
        defer { busy.remove(.attach) }
        do {
            let answer = try await gateway.upload(
                "/app/assistant/attach?name=" + Self.query(String(name.prefix(120))), data: data, as: JSONValue.self)
            guard let id = answer["id"]?.string else { throw GatewayError.invalidResponse }
            attachments.append(Attachment(id: id, name: answer["name"]?.string ?? name, size: answer["size"]?.int ?? data.count))
            notes[.attach] = nil
        } catch {
            notes[.attach] = Note(text: Self.words(error), fail: true)
        }
    }

    func unattach(_ id: String) async {
        guard let gateway = app.gateway else { return }
        do {
            _ = try await gateway.send("/app/assistant/unattach", json: JSONValue.object(["id": .string(id)]), as: JSONValue.self)
            attachments.removeAll { $0.id == id }
            notes[.attach] = nil
        } catch {
            notes[.attach] = Note(text: Self.words(error), fail: true)
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
