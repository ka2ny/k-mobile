import Foundation

/// A permission an agent asked for, said in words a phone can show.
struct AgentDecision: Equatable, Sendable {
    let id: String
    let generation: JSONValue?
    let tool: String
    let summary: String
    let detail: String
    let complete: Bool
}

/// One coding session as the phone shows it: the connector's card folded into one row.
struct AgentRow: Identifiable, Equatable, Sendable {
    var id: String
    var state: String
    var status: String
    var engine: String
    var name: String
    var project: String
    var engineLabel: String
    var cwd: String
    var controllable: Bool
    /// The connector's controls map; nil = it named none (each action then follows the state).
    var controls: [String: JSONValue]?
    var peer: Bool
    var resume: Bool
    var generation: JSONValue?
    var readOnly: Bool
    var codexJoin: Bool
    var unseen: Bool
    var updatedAt: Double
    var decision: AgentDecision?
    var question: JSONValue?
    var configuration: JSONValue?
    var tail: String
    var messages: [JSONValue]
}

/// One line of a conversation.
struct AgentItem: Identifiable, Equatable, Sendable {
    enum Kind: Sendable { case you, agent, tool }
    let id: String
    let kind: Kind
    let title: String
    let body: String
}

struct AgentReply: Codable, Equatable, Sendable, Identifiable {
    var id: String { label + "\u{0}" + text }
    var label: String
    var text: String
}

struct AgentDiffFile: Identifiable, Equatable, Sendable {
    struct Hunk: Equatable, Sendable { var header: String; var lines: [String] }
    var id: String { path }
    var path: String
    var status: String
    var binary: Bool
    var added: Int
    var removed: Int
    var hunks: [Hunk]
}

/// The PWA's model.js rules, ported line for line so the phone reads the connector exactly as
/// the web remote does. Pure: no network, no state.
enum AgentLogic {
    static let needs: Set<String> = ["awaiting-permission", "awaiting-input", "needs-native-input"]
    static let working: Set<String> = ["running", "busy", "connecting", "stopping", "live-busy", "live-queued",
                                       "live-transition", "dispatching"]
    static let order = ["needs", "turn", "working", "earlier", "unreachable"]
    static let titles = ["needs": "Needs you", "turn": "Your turn", "working": "Working", "earlier": "Earlier",
                         "unreachable": "Can't reach"]
    static let engines = ["claude-code": "Claude Code", "codex": "Codex", "omp": "OMP", "dsh": "DeepSeek Harness",
                          "opencode": "OpenCode", "gemini": "Gemini", "qwen": "Qwen", "cursor": "Cursor",
                          "kimi": "Kimi Code", "copilot": "GitHub Copilot", "goose": "Goose", "aider": "Aider"]
    static let intents: [(label: String, text: String)] = [
        ("Pick up where I left off", "Look at the project’s current state and recent changes, then continue the work in progress. Tell me what you’re doing first."),
        ("Fix the failing tests", "Run the tests, find what fails and fix it. Show me what you changed."),
        ("Review my last changes", "Review the changes since the last commit and point out bugs, risks and anything unfinished."),
    ]

    // MARK: - Words

    /// The connector's code for a failure, as model.js names it.
    static func code(_ error: Error) -> String {
        if let error = error as? AgentFailure { return error.code }
        switch error as? GatewayError {
        case .coded(_, let code, _): return code
        case .http(let status, _): return status == 502 || status == 504 ? "HOST_UNAVAILABLE" : "HTTP_\(status)"
        case .needsPairing: return "PAIR_REQUIRED"
        case .needsControl: return "CONTROL_REQUIRED"
        default: break
        }
        return error is URLError ? "OFFLINE" : "UNKNOWN"
    }

    static func words(_ error: Error) -> String {
        let code = code(error)
        if let said = table[code] { return said }
        if code == "UNKNOWN" || code == "CONTROL_REQUIRED" { return BeamModel.words(error) }
        if case GatewayError.coded(_, _, let message) = error, !message.isEmpty { return message }
        return words(code: code)
    }

    static func words(code: String) -> String {
        if let said = table[code] { return said }
        let plain = code.lowercased().replacingOccurrences(of: "_", with: " ")
        return plain.prefix(1).uppercased() + plain.dropFirst() + "."
    }

    // MARK: - Rows

    static func stateOf(_ s: JSONValue) -> String {
        let status = s["status"]?.string ?? ""
        if needs.contains(status) { return "needs" }
        if status == "live-unavailable" || status == "disconnected" || status == "unavailable" { return "unreachable" }
        if working.contains(status) { return "working" }
        if s["controllable"]?.truthy == true || s["ompControl"]?.truthy == true { return "turn" }
        return "earlier"
    }

    static func row(_ s: JSONValue, seen: [String: Double]) -> AgentRow {
        let id = s["id"]?.string ?? ""
        let cwd = s["cwd"]?.string ?? ""
        let engine = s["engine"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? "claude-code"
        let controllable = s["controllable"]?.truthy == true
        let state = stateOf(s)
        let updated = s["updatedAt"]?.number ?? 0
        let name = [s["name"]?.string ?? "", baseName(cwd)].first { !$0.isEmpty } ?? "Agent"
        return AgentRow(
            id: id, state: state, status: s["status"]?.string ?? "", engine: engine, name: name,
            project: s["project"]?.string ?? baseName(cwd), engineLabel: engines[engine] ?? engine, cwd: cwd,
            controllable: controllable, controls: s["controls"]?.object, peer: s["peerControl"]?.truthy == true,
            resume: s["resumeAvailable"]?.truthy == true, generation: s["generation"],
            readOnly: engine == "omp", codexJoin: engine == "codex" && !controllable,
            unseen: state == "turn" && updated > (seen[id] ?? 0), updatedAt: updated, decision: nil,
            question: nonNull(s["question"]), configuration: nonNull(s["configuration"]), tail: "", messages: [])
    }

    private static func nonNull(_ v: JSONValue?) -> JSONValue? { v.flatMap { $0.isNull ? nil : $0 } }

    static func describePermission(_ p: JSONValue) -> AgentDecision {
        let tool = p["tool"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? "Tool"
        let raw = p["input"] ?? .null
        var summary = "", detail = "", complete = false
        if tool == "apply_patch", let changes = raw["changes"]?.array {
            summary = changes.compactMap { $0["path"]?.string }.joined(separator: "\n")
            detail = raw.pretty; complete = true
        } else if let command = raw["command"]?.string, tool == "exec_command" || command.count > 4000 {
            summary = command; detail = raw.pretty; complete = true
        } else if let command = raw["command"]?.string {
            summary = command; detail = raw["description"]?.string ?? ""
        } else if let path = raw["file_path"]?.string {
            summary = path; detail = raw["new_string"]?.string ?? raw["content"]?.string ?? ""
        } else if let target = raw["url"]?.string ?? raw["pattern"]?.string {
            summary = target
        } else {
            summary = raw.string ?? raw.pretty
        }
        return AgentDecision(id: p["id"]?.string ?? "", generation: p["generation"], tool: tool,
                             summary: String(summary.prefix(4000)), detail: String(detail.prefix(4000)), complete: complete)
    }

    static func unavailable(_ r: AgentRow) -> AgentRow {
        var r = r
        r.state = "unreachable"; r.status = "live-unavailable"; r.controllable = false
        r.generation = nil; r.decision = nil; r.question = nil; r.configuration = nil
        r.codexJoin = false; r.resume = false; r.controls = [:]
        return r
    }

    static func mergeSummary(_ prev: AgentRow?, _ summary: JSONValue, seen: [String: Double]) -> AgentRow {
        var next = row(summary, seen: seen)
        guard let prev else { return next }
        next.tail = prev.tail; next.messages = prev.messages
        let same = next.controllable && next.generation == prev.generation
        if same && next.state == "needs" {
            next.decision = prev.decision
            next.question = next.question ?? prev.question
        }
        if same && next.controls?["configure"]?.truthy == true {
            next.configuration = next.configuration ?? prev.configuration
        }
        return next
    }

    /// Folds a session's detail card (GET sessions/<id>) into its row.
    static func applyCard(_ r: AgentRow, _ c: JSONValue) -> AgentRow {
        if c["available"] == .bool(false) { return unavailable(r) }
        var r = r
        let control = c["control"]
        if control?.isNull == true {
            r.controllable = false; r.generation = nil; r.decision = nil; r.question = nil; r.configuration = nil
            r.controls = [:]; r.codexJoin = r.engine == "codex"
        }
        let control_ = control ?? .object([:])
        r.status = c["status"]?.string ?? control_["status"]?.string ?? r.status
        var merged: [String: JSONValue] = ["controllable": .bool(r.controllable)]
        for (k, v) in control_.object ?? [:] { merged[k] = v }
        merged["status"] = .string(r.status)
        r.state = stateOf(.object(merged))
        if let text = c["text"]?.string, !text.isEmpty { r.tail = String(text.suffix(6000)) }
        if let flag = control_["controllable"] {
            r.controllable = flag.truthy
            r.codexJoin = r.engine == "codex" && !r.controllable
        }
        if let controls = control_["controls"] {
            r.controls = controls.object ?? [:]
        } else if control_["controllable"]?.truthy == true,
                  !r.controllable || control_["generation"] != r.generation {
            r.controls = nil
        }
        if let v = control_["resumeAvailable"] { r.resume = v.truthy }
        if let v = control_["peerControl"] { r.peer = v.truthy }
        if let gen = control_["generation"] {
            let generation: JSONValue? = gen.isNull ? nil : gen
            if generation != r.generation { r.decision = nil; r.question = nil; r.configuration = nil }
            r.generation = generation
        }
        if let v = control_["configuration"] { r.configuration = nonNull(v) }
        if let v = control_["question"] { r.question = nonNull(v) }
        if let p = control_["permission"] { r.decision = p.isNull ? nil : describePermission(p) }
        if !r.controllable || r.generation == nil || r.readOnly { r.decision = nil; r.question = nil; r.configuration = nil }
        if r.decision != nil { r.state = "needs" }
        if let messages = control_["messages"]?.array, !messages.isEmpty { r.messages = messages }
        return r
    }

    static func sortRows(_ rows: [AgentRow]) -> [AgentRow] {
        rows.sorted {
            let a = order.firstIndex(of: $0.state) ?? 9, b = order.firstIndex(of: $1.state) ?? 9
            return a != b ? a < b : $0.updatedAt > $1.updatedAt
        }
    }

    static func summary(_ rows: [AgentRow]) -> String {
        let needs = rows.filter { $0.state == "needs" }.count
        let working = rows.filter { $0.state == "working" }.count
        let turn = rows.filter { $0.state == "turn" }.count
        var parts: [String] = []
        if needs > 0 { parts.append(needs == 1 ? "1 needs you" : "\(needs) need you") }
        if working > 0 { parts.append("\(working) working") }
        if turn > 0 { parts.append("\(turn) waiting for you") }
        return parts.isEmpty ? "Nothing is running." : parts.joined(separator: " · ")
    }

    static func decisionVerb(_ tool: String) -> String {
        switch tool {
        case "Bash", "shell", "exec_command", "local_shell": "wants to run"
        case "Edit", "Write", "MultiEdit", "NotebookEdit", "apply_patch": "wants to change a file"
        case "Read": "wants to read a file"
        case "WebFetch", "WebSearch": "wants to look on the web"
        default: "wants to use \(tool)"
        }
    }

    static func age(_ ms: Double, now: Date = .now) -> String {
        guard ms > 0 else { return "" }
        let minutes = Int((now.timeIntervalSince1970 * 1000 - ms) / 60_000)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) h" }
        let days = hours / 24
        return days == 1 ? "yesterday" : "\(days) days"
    }

    static func can(_ r: AgentRow, _ what: String) -> Bool {
        if r.readOnly { return false }
        if let controls = r.controls, ["send", "stop", "resume", "decide", "rename", "terminal"].contains(what) {
            let key = what == "decide" ? "permission" : what
            if controls[key]?.truthy != true { return false }
        }
        switch what {
        case "send": return r.controllable && (r.state == "turn" || r.state == "working")
        case "stop": return r.controllable && !r.peer && (r.state == "working" || r.state == "needs")
        case "resume": return r.state == "earlier" && r.resume
        case "codex": return r.codexJoin && r.state != "working"
        case "decide": return r.controllable && r.state == "needs" && r.decision != nil
        case "rename": return r.controllable && r.generation != nil && r.controls?["rename"]?.truthy == true
        case "question": return questionKey(r) != nil
        case "configure": return configurationKey(r) != nil
        default: return false
        }
    }

    // MARK: - Text

    static func baseName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? ""
    }

    static func clip(_ s: String, _ n: Int) -> String {
        let flat = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return flat.count > n ? String(flat.prefix(n - 1)) + "…" : flat
    }

    static func tailLines(_ tail: String, _ n: Int = 8) -> [String] {
        var lines = tail.components(separatedBy: "\n").filter { !["USER", "ASSISTANT", "TOOL"].contains($0) }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        return Array(lines.suffix(n))
    }

    static func lastWords(_ r: AgentRow) -> String {
        if let m = r.messages.last(where: { $0["role"]?.string == "assistant" && !($0["text"]?.string ?? "").isEmpty }) {
            return clip(m["text"]?.string ?? "", 200)
        }
        let lines = tail(r.tail, 50)
        return clip(lines.last { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "", 200)
    }

    private static func tail(_ text: String, _ n: Int) -> [String] { Array(text.components(separatedBy: "\n").suffix(n)) }

    static func items(_ messages: [JSONValue]) -> [AgentItem] {
        messages.enumerated().compactMap { i, m in
            let text = m["text"]?.string ?? ""
            if m["kind"]?.string == "tool" || m["role"]?.string == "tool" {
                let lines = text.components(separatedBy: "\n")
                return AgentItem(id: m["id"]?.string ?? "t\(i)", kind: .tool, title: clip(lines.first ?? "", 120),
                                 body: lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
            }
            guard !text.isEmpty else { return nil }
            return AgentItem(id: m["id"]?.string ?? "m\(i)", kind: m["role"]?.string == "user" ? .you : .agent,
                             title: "", body: text)
        }
    }

    static func validReplies(_ list: [AgentReply]) -> [AgentReply] {
        Array(list.filter { (1...24).contains($0.label.count) && (1...2000).contains($0.text.count) }.prefix(12))
    }

    static func agentName(_ text: String, project: String) -> String {
        let said = clip(text, 48)
        if !said.isEmpty { return said }
        return project.isEmpty ? "New agent" : "Work on \(project)"
    }

    // MARK: - Changes

    static func parseDiff(_ text: String, limit: Int = 300) -> [AgentDiffFile] {
        var files: [AgentDiffFile] = []
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("diff --git a/") {
                guard files.count < limit else { break }
                let path = line.components(separatedBy: " b/").last ?? line
                files.append(AgentDiffFile(path: path, status: "modified", binary: false, added: 0, removed: 0, hunks: []))
                continue
            }
            guard !files.isEmpty else { continue }
            let i = files.count - 1
            if line.hasPrefix("new file") { files[i].status = "added" }
            else if line.hasPrefix("deleted file") { files[i].status = "deleted" }
            else if line.hasPrefix("rename from") || line.hasPrefix("similarity") { files[i].status = "renamed" }
            else if line.hasPrefix("Binary files") || line.hasPrefix("GIT binary patch") { files[i].binary = true }
            else if line.hasPrefix("@@") { files[i].hunks.append(.init(header: line, lines: [])) }
            else if let h = files[i].hunks.indices.last, let first = line.first, "+- \\".contains(first) {
                if files[i].hunks[h].lines.count < 2000 { files[i].hunks[h].lines.append(line) }
                if first == "+" { files[i].added += 1 } else if first == "-" { files[i].removed += 1 }
            }
        }
        return files
    }

    static func parseUntracked(_ text: String) -> [AgentDiffFile] {
        text.components(separatedBy: "\n").compactMap { line in
            guard line.hasPrefix("Untracked file ") else { return nil }
            let raw = String(line.dropFirst("Untracked file ".count))
            let name = (try? JSONDecoder().decode(String.self, from: Data(raw.utf8))) ?? raw
            return AgentDiffFile(path: name, status: "added", binary: false, added: 0, removed: 0, hunks: [])
        }
    }

    static func changeSummary(_ files: [AgentDiffFile]) -> String {
        guard !files.isEmpty else { return "Nothing here." }
        let a = files.reduce(0) { $0 + $1.added }, d = files.reduce(0) { $0 + $1.removed }
        return "\(files.count) file\(files.count == 1 ? "" : "s") · +\(a) −\(d)"
    }

    // MARK: - Questions and configuration

    static func questionKey(_ r: AgentRow) -> String? {
        guard r.controllable, let gen = r.generation, let q = r.question, r.controls?["question"]?.truthy == true,
              q["expired"]?.truthy != true, q["generation"] == nil || q["generation"] == gen,
              let qid = q["id"]?.string else { return nil }
        return "\(r.id)/\(gen.pretty)/\(qid)"
    }

    /// The answers in the connector's shape, or nil when the draft can't be sent.
    static func questionAnswers(_ question: JSONValue, _ draft: [String: (selected: [String], custom: String)]) -> JSONValue? {
        guard let questions = question["questions"]?.array else { return nil }
        var out: [JSONValue] = []
        for q in questions {
            guard let id = q["id"]?.string else { return nil }
            let d = draft[id] ?? ([], "")
            let options = Set((q["options"]?.array ?? []).compactMap { $0["label"]?.string ?? $0.string })
            if d.selected.contains(where: { !options.contains($0) }) || Set(d.selected).count != d.selected.count { return nil }
            let custom = d.custom.trimmingCharacters(in: .whitespacesAndNewlines)
            if custom.count > 12000 { return nil }
            if !custom.isEmpty && q["allowCustom"]?.truthy != true { return nil }
            if d.selected.count + (custom.isEmpty ? 0 : 1) > 1 && q["multiple"]?.truthy != true { return nil }
            if d.selected.isEmpty && custom.isEmpty { continue }
            var answer: [String: JSONValue] = ["id": .string(id), "selected": .array(d.selected.map(JSONValue.string))]
            if !custom.isEmpty { answer["custom"] = .string(custom) }
            out.append(.object(answer))
        }
        return out.isEmpty ? nil : .array(out)
    }

    static func configurationKey(_ r: AgentRow) -> String? {
        guard !r.readOnly, r.controllable, let gen = r.generation, r.controls?["configure"]?.truthy == true,
              let c = r.configuration, c["available"]?.truthy == true,
              c["generation"] == nil || c["generation"] == gen,
              let revision = c["revision"]?.int, c["options"]?.array != nil else { return nil }
        return "\(r.id)/\(gen.pretty)/\(revision)"
    }

    static func createEngines(_ status: JSONValue?) -> [String] {
        if let list = status?["createEngines"]?.array { return list.compactMap(\.string) }
        if status?["canCreateClaude"] == .bool(false) { return [] }
        return ["claude-code"]
    }

    // MARK: - The connector's codes, in words

    static let table: [String: String] = [
        "WORKSPACE_GIT_FAILED": "Git could not finish. Check the repository, new branch name and Git authentication on the computer.",
        "INVALID_REPOSITORY_URL": "Use an HTTPS or SSH repository address without embedded tokens or query parameters.",
        "INVALID_WORKSPACE_BRANCH": "Choose a valid new Git branch name.",
        "WORKSPACE_JOBS_BUSY": "Two workspace preparations are running. Wait or cancel one.",
        "WORKSPACE_JOB_NOT_FOUND": "This preparation is not available to this device.",
        "WORKPLACE_PATH_REJECTED": "Choose a folder inside registered project roots, with an existing parent folder.",
        "WORKPLACE_EXISTS": "That folder already exists. Choose Add existing to register it.",
        "WORKPLACE_CREATE_FAILED": "The folder could not be created. Check its parent folder and permissions.",
        "WORKPLACE_REGISTRATION_FAILED": "The folder was created but could not be registered. Choose Add existing; your files were kept.",
        "PAIR_REQUIRED": "This phone isn’t paired. Pair it from your computer: Agents, then Use it from your phone.",
        "REVOKED": "This phone was disconnected. Pair it again from your computer.",
        "PAIR_EXPIRED": "That code expired. Make a new one on your computer.",
        "PAIR_INVALID": "That code was already used or isn’t valid. Make a new one on your computer.",
        "PAIR_RATE_LIMIT": "Too many tries. Wait five minutes.",
        "EMPTY_OR_LONG_MESSAGE": "Write something first (at most 16,000 characters).",
        "STALE_TARGET": "The agent moved on meanwhile. Try again.",
        "ACP_AUTH_REQUIRED": "Sign in to this coding tool on your computer, then start or resume it again.",
        "ACP_NATIVE_REJECTED": "The coding tool refused this action. Check its native account and workspace policy.",
        "ACP_DISCONNECTED": "The coding tool disconnected. Its unfinished actions have not been replayed.",
        "OPENCODE_DISCONNECTED": "The OpenCode server is disconnected. Check its connection on your computer.",
        "STALE_CONFIGURATION": "The session settings changed. Refresh and choose again.",
        "INVALID_CONFIGURATION": "Choose a setting offered by this agent.",
        "ACP_SESSION_IN_USE": "This conversation is already open in another native process.",
        "ACP_OWNERSHIP_LOST": "The native agent lost exclusive access. Reconnect explicitly.",
        "ACP_WORKSPACE_UNTRUSTED": "Review project trust in the native tool on your computer, then start or resume here.",
        "ACP_CONFIG_UNAVAILABLE": "Session settings are not available right now.",
        "STALE_QUESTION": "This question was replaced or already answered.",
        "INVALID_ANSWER": "Complete the current question using its available choices.",
        "ENGINE_CREATE_UNAVAILABLE": "This coding tool has no configured launcher. Check Agents setup on your computer.",
        "STALE_PERMISSION": "That decision was already answered.",
        "INVALID_PERMISSION": "There’s no decision waiting.",
        "OUTCOME_UNKNOWN": "Sent, but the agent didn’t confirm. Check the conversation before sending again.",
        "RUNTIME_LIMIT": "Eight agents are already running. Stop one first.",
        "WORKSPACE_REJECTED": "That folder isn’t in your projects.",
        "SESSION_ALREADY_RUNNING": "It’s already running.",
        "SESSION_NOT_FOUND": "That agent isn’t there any more.",
        "RESUME_UNAVAILABLE": "This session cannot resume here right now. Check its connection, native resume support and workspace configuration.",
        "LAUNCH_FAILED": "Claude Code didn’t start on the computer.",
        "DSH_DISCONNECTED": "dsh is disconnected. Check its Web host and reconnect from Agents on your computer.",
        "DSH_NATIVE_REJECTED": "dsh refused this operation. Check its workspace trust and native tool policy.",
        "DSH_CONNECTION_INVALID": "Reconnect dsh from Agents on your computer using its current local launch link.",
        "OMP_VIEW_ONLY": "Use the native OMP connection controls for this session.",
        "OMP_LIVE_UNAVAILABLE": "Native OMP observation is unavailable. Enable its identity extension on the computer.",
        "OMP_CONTROLS_DISABLED": "Enable the native OMP admission extension and connector control configuration first.",
        "OMP_OBSERVATION_REQUIRED": "Connect live OMP status before enabling sending.",
        "OMP_CONNECTION_CHANGED": "The native OMP connection changed. Reconnect explicitly.",
        "OMP_OUTCOME_UNKNOWN": "No confirmed native receipt. Your draft and request ID are retained; check the receipt.",
        "OMP_PENDING_RECEIPT": "Check the saved native receipt before sending another request.",
        "OMP_SEND_UNAVAILABLE": "Wait for this native session to be idle and its previous receipt to settle.",
        "OMP_TEXT_INVALID": "OMP accepts plain text up to 16 KiB here; slash commands and @ references stay native.",
        "OMP_STATE_UNSAFE": "Local receipt storage is unavailable or invalid. Sending is disabled.",
        "OMP_STORAGE_LOCK_UNAVAILABLE": "This browser cannot protect native command receipts across tabs. Use a browser with Web Locks.",
        "OMP_INTERRUPT_UNAVAILABLE": "Only a turn started here can be stopped through this connection.",
        "OMP_DISCONNECT_PENDING": "Disconnected locally; native confirmation is pending.",
        "OMP_RECEIPT_NOT_FOUND": "No saved receipt is available for this native operation.",
        "NATIVE_OFFER_EXPIRED": "Refresh the saved conversations and select it again.",
        "NATIVE_DISCOVERY_UNAVAILABLE": "This tool does not offer qualified saved-session discovery here.",
        "CODEX_JOIN_UNAVAILABLE": "Codex can be taken over only while it’s idle.",
        "CHANGES_NOT_GIT": "This project isn’t a Git repository.",
        "CHANGES_BUSY": "Two reviews are already running. Try again shortly.",
        "INVALID_REPLIES": "Each quick reply needs a name (24 characters) and its words.",
        "BUSY": "The computer is busy. Try again in a moment.",
        "CONNECTOR_STOPPING": "Agents is restarting on the computer.",
        "HOST_UNAVAILABLE": "That computer isn’t answering.",
        "HOST_ACCESS_CHANGED": "That computer’s access changed. Try again.",
        "WRONG_CONNECTOR": "That went to the wrong computer. Try again.",
        "HOST_PAIR_INVALID": "That isn’t a pairing link. Make one on the other computer: Agents, Use it from your phone.",
        "ACTIVITY_STREAM_LIMIT": "Too many live views are open on this phone.",
        "OFFLINE": "Can’t reach your computer. Is Tailscale on?",
    ]
}

/// A failure the phone found itself, carried with a connector-style code.
struct AgentFailure: LocalizedError {
    let code: String
    var errorDescription: String? { AgentLogic.words(code: code) }
}
