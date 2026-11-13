import Foundation
import Observation

/// k-beam on the phone, natively: the same /beam/api the k-hole phone app's page uses,
/// through the one pairing (the khole_app cookie /api/hello set). Every control has its own
/// result line, so nothing fails out of sight.
@MainActor @Observable
final class BeamModel {
    struct Me: Decodable, Sendable {
        struct Phone: Decodable, Sendable { let id: String; let name: String; let trusted: Bool; let push: Bool?; let linked: Bool? }
        let ok: Bool
        let name: String?
        let receive: Bool?
        let phone: Phone?
        let linked: Bool?
        let folder: Bool?
    }
    struct InboxFile: Decodable, Sendable, Identifiable { let id: String; let name: String; let size: Int64; let type: String?; let taken: Bool? }
    struct InboxItem: Decodable, Sendable, Identifiable {
        let id: String; let at: Int; let state: String?; let total: Int64?; let files: [InboxFile]; let text: String?; let until: Int?
    }
    typealias FolderFile = SharedFile
    private struct Inbox: Decodable, Sendable { let ok: Bool; let items: [InboxItem] }
    private struct Folder: Decodable, Sendable { let ok: Bool; let on: Bool; let name: String?; let files: [FolderFile]? }
    private struct Clip: Decodable, Sendable { let ok: Bool; let text: String? }
    private struct Prepared: Decodable, Sendable {
        struct Slot: Decodable, Sendable { let id: String; let token: String }
        let ok: Bool?; let done: Bool?; let ask: String?; let seconds: Int?; let state: String?
        let session: String?; let files: [Slot]?
    }
    private struct UploadState: Decodable, Sendable { let have: Int64; let done: Bool; let size: Int64 }
    private struct OK: Decodable, Sendable { let ok: Bool? }

    /// What a send is doing now, said beside the Send controls.
    enum SendState: Equatable {
        case idle
        case asking(seconds: Int)
        case sending(done: Int64, total: Int64)
        case sent(String)
        case failed(String)
    }

    struct Outgoing: Sendable { let name: String; let url: URL; let size: Int64; let type: String }

    private(set) var me: Me?
    private(set) var meError: String?
    private(set) var inbox: [InboxItem] = []
    private(set) var inboxError: String?
    private(set) var folderOn = false
    private(set) var folderName = "k-beam"
    private(set) var folder: [FolderFile] = []
    private(set) var folderError: String?
    private(set) var sendState: SendState = .idle
    private(set) var clipNote: String?
    private(set) var clipText: String?
    /// Per row (inbox file id or folder file name): its own line, and a saved copy to share.
    private(set) var rowNote: [String: String] = [:]
    private(set) var saved: [String: URL] = [:]
    private(set) var busyRows: Set<String> = []
    private(set) var loading = false

    private let app: AppModel
    private var askID: String?
    private var sessionID: String?
    private var sendTask: Task<Void, Never>?
    private var sendAttempt = UUID()

    private let originGateway: GatewayClient?
    private let originGeneration: UUID
    private var active = true
    private var gateway: GatewayClient? { active && app.connectionGeneration == originGeneration ? originGateway : nil }

    init(app: AppModel, gateway: GatewayClient? = nil) {
        self.app = app
        self.originGateway = gateway ?? app.gateway
        self.originGeneration = app.connectionGeneration
    }

    func stop() {
        if sending { stopSending() }
        active = false
    }

    private func checkContext() throws {
        try Task.checkCancellation()
        guard gateway != nil else { throw CancellationError() }
    }

    var sending: Bool {
        switch sendState { case .asking, .sending: true; default: false }
    }
    var trusted: Bool { me?.phone?.trusted == true }

    // MARK: - Reading

    func refresh() async {
        guard !loading else { return }
        guard let gateway = gateway else {
            meError = "Connect to your computer to use k-beam."
            return
        }
        let generation = app.connectionGeneration
        loading = true
        defer { loading = false }
        do {
            let me = try await gateway.get("/beam/api/me", as: Me.self)
            guard generation == app.connectionGeneration, active, !Task.isCancelled else { return }
            self.me = me
            meError = nil
        } catch {
            guard generation == app.connectionGeneration, active, !Task.isCancelled else { return }
            me = nil; inbox = []; folder = []; folderOn = false
            meError = Self.words(error, off: "k-beam is off on your computer. Turn it on in Settings → k-beam.")
            return
        }
        do {
            let box = try await gateway.get("/beam/api/inbox", as: Inbox.self)
            guard generation == app.connectionGeneration, active, !Task.isCancelled else { return }
            inbox = box.items.filter { $0.state != "done" }
            inboxError = nil
        } catch {
            guard generation == app.connectionGeneration, active, !Task.isCancelled else { return }
            inboxError = Self.words(error)
        }
        guard me?.folder == true else {
            folderOn = false; folder = []; folderError = nil
            return
        }
        do {
            let shared = try await gateway.get("/beam/api/folder", as: Folder.self)
            guard generation == app.connectionGeneration, active, !Task.isCancelled else { return }
            folderOn = shared.on
            folderName = shared.name ?? "k-beam"
            folder = shared.files ?? []
            folderError = nil
        } catch {
            guard generation == app.connectionGeneration, active, !Task.isCancelled else { return }
            folderError = Self.words(error)
        }
    }

    // MARK: - Sending

    func send(text: String, onSent: @escaping @MainActor () -> Void = {}) {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { sendState = .failed("Type something to send first."); return }
        start {
            try await self.sendText(words)
            try self.checkContext()
            onSent()
        }
    }

    func send(files: [Outgoing], toFolder: Bool = false) {
        guard !files.isEmpty else { return }
        guard !sending, gateway != nil else { BeamImport.remove(files); return }
        start(cleanup: { BeamImport.remove(files) }) {
            try await self.sendFiles(files, toFolder: toFolder)
        }
    }

    func stopSending() {
        sendAttempt = UUID()
        sendTask?.cancel()
        guard let gateway = originGateway else { sendState = .idle; return }
        let ask = askID, session = sessionID
        askID = nil; sessionID = nil
        sendState = .failed("Stopped sending. Check the computer for anything that already arrived.")
        Task {
            if let ask { _ = try? await gateway.post(Self.path("/beam/api/cancel", ["ask": ask]), body: [:], as: OK.self) }
            if let session {
                _ = try? await gateway.post(Self.path("/beam/api/cancel", ["session": session]), body: [:], as: OK.self)
            }
        }
    }

    private func start(cleanup: @escaping @MainActor () -> Void = {}, _ work: @escaping @MainActor () async throws -> Void) {
        guard !sending else { return }
        guard gateway != nil else { sendState = .failed("Connect to your computer first."); return }
        sendState = .asking(seconds: 0)
        let current = UUID()
        sendAttempt = current
        sendTask = Task {
            defer { cleanup() }
            do { try checkContext(); try await work() } catch is CancellationError {
                // stopSending already said so.
            } catch {
                if Task.isCancelled || gateway == nil { return }
                sendState = .failed(Self.words(error))
                app.recordActivity("k-beam", "Send failed: \(Self.words(error))", failed: true)
            }
            if current == sendAttempt { askID = nil; sessionID = nil }
        }
    }

    private func sendText(_ text: String) async throws {
        guard let gateway = gateway else { throw GatewayError.missingCredential }
        sendState = .asking(seconds: 0)
        struct Body: Encodable { let text: String; let wait: Bool }
        var answer = try await gateway.send("/beam/api/prepare", json: Body(text: text, wait: false), as: Prepared.self)
        answer = try await waitForAnswer(answer, gateway: gateway)
        try checkContext()
        guard answer.done == true else { throw GatewayError.invalidResponse }
        sendState = .sent("Sent to \(me?.name ?? "your computer"). It's on its clipboard.")
        app.recordActivity("k-beam", "Sent text to \(me?.name ?? "your computer")")
    }

    private func sendFiles(_ files: [Outgoing], toFolder: Bool) async throws {
        guard let gateway = gateway else { throw GatewayError.missingCredential }
        struct File: Encodable { let name: String; let size: Int64; let type: String }
        struct Body: Encodable { let files: [File]; let wait: Bool; let to: String? }
        let total = files.reduce(Int64(0)) { $0 + $1.size }
        sendState = .asking(seconds: 0)
        var answer = try await gateway.send(
            "/beam/api/prepare",
            json: Body(files: files.map { File(name: $0.name, size: $0.size, type: $0.type) }, wait: false,
                       to: toFolder ? "folder" : nil),
            as: Prepared.self)
        answer = try await waitForAnswer(answer, gateway: gateway)
        guard let session = answer.session, let slots = answer.files, slots.count == files.count else {
            throw GatewayError.invalidResponse
        }
        sessionID = session
        var before: Int64 = 0
        sendState = .sending(done: 0, total: total)
        for (file, slot) in zip(files, slots) {
            try checkContext()
            let query = ["session": session, "file": slot.id, "token": slot.token]
            var have: Int64 = 0
            for attempt in 0..<4 {
                try checkContext()
                do {
                    let state = try await gateway.get(Self.path("/beam/api/upload", query), as: UploadState.self)
                    try checkContext()
                    have = state.have
                    if state.done { break }
                    sendState = .sending(done: before + have, total: total)
                    var withOffset = query
                    withOffset["offset"] = String(have)
                    _ = try await gateway.uploadFile(Self.path("/beam/api/upload", withOffset), file: file.url,
                                                     from: have, as: OK.self)
                    try checkContext()
                    have = file.size
                    break
                } catch let error as URLError where attempt < 3 {
                    // A dropped connection keeps the part on the computer: ask how much arrived and go on.
                    _ = error
                    try await Task.sleep(for: .seconds(Double(1 << attempt)))
                }
            }
            before += file.size
            sendState = .sending(done: before, total: total)
        }
        sessionID = nil
        let place = toFolder ? "the shared folder" : (me?.name ?? "your computer")
        let what = files.count == 1 ? "“\(files[0].name)”" : "\(files.count) files"
        sendState = .sent("Sent \(what) to \(place).")
        app.recordActivity("k-beam", "Sent \(what) to \(place)")
    }

    /// Waits for the computer's Accept card when the share has to ask; long-polls 25 s at a time.
    private func waitForAnswer(_ first: Prepared, gateway: GatewayClient) async throws -> Prepared {
        try checkContext()
        var answer = first
        guard let ask = first.ask else { return first }
        askID = ask
        sendState = .asking(seconds: first.seconds ?? 0)
        while true {
            try checkContext()
            answer = try await gateway.wait(Self.path("/beam/api/ask", ["id": ask, "wait": "25"]), as: Prepared.self)
            try checkContext()
            if answer.state == "waiting" {
                sendState = .asking(seconds: answer.seconds ?? 0)
                continue
            }
            askID = nil
            return answer
        }
    }

    // MARK: - Receiving

    func save(_ file: InboxFile, of item: InboxItem) async {
        await fetch(row: file.id, name: file.name,
                    path: "/beam/api/inbox/\(Self.segment(item.id))/\(Self.segment(file.id))")
        // Every file of the share taken: tell the computer it can let the share go.
        if let gateway = gateway,
           item.files.allSatisfy({ $0.taken == true || saved[$0.id] != nil }) {
            _ = try? await gateway.post("/beam/api/inbox/\(Self.segment(item.id))/done", body: [:], as: OK.self)
        }
    }

    func dismiss(_ item: InboxItem) async {
        guard let gateway = gateway else { return }
        do {
            _ = try await gateway.post("/beam/api/inbox/\(Self.segment(item.id))/done", body: [:], as: OK.self)
            try checkContext()
            inbox.removeAll { $0.id == item.id }
        } catch {
            rowNote[item.id] = Self.words(error)
        }
    }

    func save(_ file: FolderFile) async {
        await fetch(row: file.downloadKey, name: file.name,
                    path: Self.path("/beam/api/folder/file", ["name": file.name]))
    }

    private func fetch(row: String, name: String, path: String) async {
        guard let gateway = gateway else { rowNote[row] = "Connect to your computer first."; return }
        guard !busyRows.contains(row) else { return }
        busyRows.insert(row)
        rowNote[row] = "Downloading…"
        defer { busyRows.remove(row) }
        do {
            let temp = try await gateway.download(path)
            guard gateway === self.gateway, !Task.isCancelled else {
                try? FileManager.default.removeItem(at: temp)
                return
            }
            let folder = try Self.receivedFolder()
            let target = Self.unique(folder.appending(path: Self.safeName(name)))
            try FileManager.default.moveItem(at: temp, to: target)
            saved[row] = target
            rowNote[row] = "Saved in Files → k-hole → Received."
            app.recordActivity("k-beam", "Received “\(target.lastPathComponent)”")
        } catch {
            guard self.gateway != nil else { return }
            rowNote[row] = Task.isCancelled ? "Download cancelled." : Self.words(error)
        }
    }

    // MARK: - Clipboard

    func readClipboard() async {
        guard let gateway = gateway else { clipNote = "Connect to your computer first."; return }
        clipNote = "Reading the computer's clipboard…"
        clipText = nil
        do {
            let clip = try await gateway.get("/beam/api/clipboard", as: Clip.self)
            try checkContext()
            clipText = clip.text
            clipNote = (clip.text ?? "").isEmpty ? "The computer's clipboard is empty." : nil
        } catch GatewayError.http(403, let message) {
            clipNote = message.isEmpty
                ? "Only a trusted phone can read the clipboard. Trust it on the computer: Settings → k-beam."
                : message
        } catch GatewayError.http(404, _) {
            clipNote = "The computer's clipboard is empty."
        } catch {
            clipNote = Self.words(error)
        }
    }

    func clearClipboardResult() { clipText = nil; clipNote = nil }
    func clearSendState() { if !sending { sendState = .idle } }

    // MARK: - Helpers

    static func path(_ base: String, _ query: [String: String]) -> String {
        var parts = URLComponents()
        parts.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        // URLComponents leaves "+" alone; the computer reads it as a space.
        let encoded = (parts.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
        return encoded.isEmpty ? base : base + "?" + encoded
    }

    static func segment(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
    }

    /// A name the computer gave, made safe as one file name here.
    static func safeName(_ name: String) -> String {
        let last = name.split(separator: "/").last.map(String.init) ?? name
        let cleaned = last.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && !(0x202A...0x202E).contains($0.value)
                && !(0x2066...0x2069).contains($0.value) && $0.value != 0x200B && $0.value != 0x200F && $0.value != 0x200E
        }
        var out = String(String.UnicodeScalarView(cleaned)).trimmingCharacters(in: .whitespaces)
        while out.hasPrefix(".") { out.removeFirst() }
        return out.isEmpty ? "file" : String(out.prefix(120))
    }

    private static func receivedFolder() throws -> URL {
        let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = docs.appending(path: "Received", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func unique(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let stem = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        for n in 2...999 {
            let next = url.deletingLastPathComponent().appending(path: ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)")
            if !FileManager.default.fileExists(atPath: next.path) { return next }
        }
        return url.deletingLastPathComponent().appending(path: UUID().uuidString + (ext.isEmpty ? "" : "." + ext))
    }

    nonisolated static func words(_ error: Error, off: String? = nil) -> String {
        if let off, case GatewayError.http(let code, _) = error, code == 404 || code == 502 || code == 503 { return off }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet: return "This phone is offline."
            case .timedOut: return "The computer took too long to answer. Try again."
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
                return "Can't reach your computer. Check that it's awake and on Tailscale."
            default: break
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
