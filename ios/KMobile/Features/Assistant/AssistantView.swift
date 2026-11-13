import SwiftUI
import UniformTypeIdentifiers

/// The desktop Assistant on the phone: start a task, follow its plan and steps, answer its questions,
/// refuse a step, steer and queue, read earlier chats and conversations between assistants. Allow and
/// Keep going are pressed on the computer only; their cards bring the window forward there.
struct AssistantView: View {
    let isActive: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var assistant: AssistantModel?
    @Binding var goal: String
    @State private var importTask: Task<Void, Never>?
    @State private var memoryPersona: Ref?
    @State private var steerText = ""
    @State private var answerText: [String: String] = [:]
    @State private var picking = false
    @State private var openChatRef: Ref?
    @State private var openThreadRef: Ref?

    struct Ref: Identifiable { let id: String }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.inset) {
                PageHeading(title: "Assistant", detail: "Tasks your computer does for you, followed from here.")
                if !model.canUseAssistant {
                    if model.selected != nil && model.refreshing && model.connectionError == nil && !model.online {
                        ProgressView("Connecting to your computer…").frame(maxWidth: .infinity).padding(Design.inset)
                    } else {
                        QuietEmptyState(title: blocker.title, detail: blocker.detail, icon: .assistant)
                    }
                } else if let a = assistant {
                    content(a)
                } else {
                    ProgressView("Checking Assistant…").frame(maxWidth: .infinity).padding(Design.inset)
                }
            }.quietPage().quietEntrance()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Design.background)
        .navigationTitle("Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await assistant?.refresh()
            await assistant?.loadHistory()
        }
        .task(id: "\(model.selectedID?.uuidString ?? "none")-\(model.canUseAssistant)-\(scenePhase)-\(isActive)") {
            guard isActive, scenePhase == .active, model.canUseAssistant else {
                assistant?.stop()
                return
            }
            let a = assistant ?? AssistantModel(app: model)
            assistant = a
            a.start()
            await a.loadThreads()
        }
        .onChange(of: model.selectedID) {
            assistant?.stop()
            assistant = nil
            steerText = ""
        }
        .onDisappear { importTask?.cancel(); assistant?.stop() }
        .sheet(item: $memoryPersona) { ref in
            if let a = assistant { AssistantMemoryView(assistant: a, persona: ref.id) }
        }
        .sheet(item: $openChatRef) { ref in
            if let a = assistant { AssistantChatSheet(assistant: a, id: ref.id) }
        }
        .sheet(item: $openThreadRef) { ref in
            if let a = assistant { AssistantThreadSheet(assistant: a, id: ref.id) }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.image, .pdf, .plainText],
                      allowsMultipleSelection: true) { result in
            guard let a = assistant else { return }
            switch result {
            case .success(let urls):
                importTask?.cancel()
                importTask = Task { await a.importFiles(urls) }
            case .failure(let error): a.attachmentError(error)
            }
        }
    }

    // MARK: - Page

    @ViewBuilder private func content(_ a: AssistantModel) -> some View {
        if let error = a.readError, !a.loaded || a.now == nil {
            QuietEmptyState(title: "Assistant is unavailable", detail: error, icon: .assistant)
            Button("Try again", systemImage: "arrow.clockwise") { Task { await a.refresh() } }
                .buttonStyle(QuietSecondaryStyle())
        } else if !a.loaded {
            ProgressView("Checking Assistant…").frame(maxWidth: .infinity).padding(Design.inset)
        } else {
            if let note = a.computerNote { NoteLine(note: note) }
            if a.running {
                taskCard(a)
                if let c = a.confirm { confirmCard(a, c) }
                if let q = a.question { questionCard(a, q) }
                if let p = a.paused { pausedCard(a, p) }
                steerCard(a)
            } else {
                composer(a)
                if let s = a.summary { resultCard(s) }
            }
            if let persona = a.chosenAssistant ?? a.defaultAssistant ?? a.assistants.first?.id {
                Button { memoryPersona = Ref(id: persona) } label: {
                    Label("What \(a.name(of: persona)) remembers", systemImage: "brain")
                }.buttonStyle(QuietSecondaryStyle())
            }
            if !a.running, !a.goals.isEmpty { AssistantGoalsView(assistant: a) }
            historySection(a)
            threadsSection(a)
        }
    }

    // MARK: - Composer

    private func composer(_ a: AssistantModel) -> some View {
        @Bindable var a = a
        let text = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: Design.gap) {
            Text("New task").font(.title2.weight(.medium))
            if a.assistants.count > 1 {
                Picker("Assistant", selection: $a.chosenAssistant) {
                    Text("Default (\(a.name(of: nil)))").tag(String?.none)
                    ForEach(a.assistants) { p in Text(p.name).tag(Optional(p.id)) }
                }
                .pickerStyle(.menu)
            }
            TextField("Describe a task for your computer…", text: $goal, axis: .vertical)
                .lineLimit(3...10)
                .padding(Design.gap)
                .background(Design.background, in: .rect(cornerRadius: Design.controlRadius))
                .accessibilityLabel("Task for your computer")
            if goal.count > AssistantModel.maxText {
                Text("Only the first \(AssistantModel.maxText) characters go to your computer.")
                    .font(.footnote).foregroundStyle(Design.muted)
            }
            attachments(a)
            HStack {
                Button("Add a file", systemImage: "paperclip") { picking = true }
                    .buttonStyle(QuietSecondaryStyle())
                    .disabled(a.importing || a.busy.contains(.composer) || a.busy.contains(.attach) || a.attachments.count >= AssistantModel.maxFiles)
                Spacer(minLength: 0)
                Button("Do it", systemImage: "arrow.up") {
                    Task { if await a.startTask(text), goal.trimmingCharacters(in: .whitespacesAndNewlines) == text { goal = "" } }
                }
                .buttonStyle(QuietProminentStyle())
                .disabled(text.isEmpty || a.busy.contains(.composer) || a.busy.contains(.attach) || a.importing)
            }
            if a.busy.contains(.composer) { ProgressView("Sending to your computer…").font(.callout) }
            if let note = a.notes[.composer] { NoteLine(note: note) }
        }.quietCard()
    }

    @ViewBuilder private func attachments(_ a: AssistantModel) -> some View {
        if !a.attachments.isEmpty || a.importing || a.busy.contains(.attach) || a.notes[.attach] != nil {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(a.attachments) { f in
                    HStack {
                        Image(systemName: "doc").accessibilityHidden(true)
                        Text(f.name).lineLimit(1).truncationMode(.middle)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(f.size), countStyle: .file))
                            .font(.footnote).foregroundStyle(Design.muted)
                        Spacer(minLength: 0)
                        Button("Remove \(f.name)", systemImage: "xmark") { Task { await a.unattach(f.id) } }
                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                            .disabled(a.importing || a.busy.contains(.attach) || a.busy.contains(.composer))
                    }
                }
                if a.importing && !a.busy.contains(.attach) { ProgressView("Preparing attachment…") }
                if a.busy.contains(.attach) { ProgressView("Sending the file…").font(.callout) }
                if let note = a.notes[.attach] { NoteLine(note: note) }
            }
        }
    }

    // MARK: - The task in front

    private func taskCard(_ a: AssistantModel) -> some View {
        VStack(alignment: .leading, spacing: Design.gap) {
            MobileLabel(a.answering ? "Answering with what it found" : "\(a.assistantName) is working",
                        icon: .assistant).font(.headline)
            Text(a.goal).font(.title3).textSelection(.enabled)
            if !a.plan.isEmpty {
                Text("Plan").font(.subheadline.weight(.semibold))
                ForEach(Array(a.plan.enumerated()), id: \.offset) { _, item in
                    StepRow(text: item["text"]?.string ?? "", status: item["status"]?.string)
                }
            }
            if !a.steps.isEmpty {
                Text("Steps").font(.subheadline.weight(.semibold))
                ForEach(Array(a.steps.suffix(8).enumerated()), id: \.offset) { _, step in
                    StepRow(text: stepWords(step), status: step["status"]?.string,
                            detail: step["detail"]?.string)
                }
            }
            if !a.findings.isEmpty {
                Text("Found so far").font(.subheadline.weight(.semibold))
                ForEach(Array(a.findings.enumerated()), id: \.offset) { _, f in
                    Text("• " + f).font(.callout).textSelection(.enabled)
                }
            }
            HStack {
                Button("Answer now", systemImage: "text.badge.checkmark") { Task { await a.answerNow() } }
                    .buttonStyle(QuietSecondaryStyle())
                    .disabled(a.answering || a.busy.contains(.answerNow) || a.confirm != nil
                              || a.question != nil || a.paused != nil)
                Button("Stop", systemImage: "stop.circle", role: .destructive) { Task { await a.stopTask() } }
                    .buttonStyle(QuietSecondaryStyle())
                    .disabled(a.busy.contains(.stop))
            }
            if let note = a.notes[.answerNow] { NoteLine(note: note) }
            if let note = a.notes[.stop] { NoteLine(note: note) }
        }.quietCard()
    }

    private func stepWords(_ step: JSONValue) -> String {
        let label = step["label"]?.string ?? ""
        if let rule = step["rule"]?.string, !rule.isEmpty { return label + " · allowed by a rule you set" }
        if let team = step["team"]?.string, !team.isEmpty { return team + ": " + label }
        return label
    }

    private func confirmCard(_ a: AssistantModel, _ c: JSONValue) -> some View {
        let id = c["id"]?.string ?? ""
        return VStack(alignment: .leading, spacing: Design.gap) {
            MobileLabel("It asks before this step", icon: .assistant).font(.headline)
            Text(c["label"]?.string ?? "").textSelection(.enabled)
            if let why = c["why"]?.string, !why.isEmpty {
                Text(why).font(.callout).foregroundStyle(Design.muted)
            }
            Text("Approve in the desktop Assistant window. Remote lets you reach that window from here.")
                .font(.footnote).foregroundStyle(Design.muted)
            HStack {
                Button("Don't", systemImage: "hand.raised", role: .destructive) { Task { await a.deny(id) } }
                    .buttonStyle(QuietSecondaryStyle())
                    .disabled(a.busy.contains(.confirm(id)))
                Button("Allow on the computer", systemImage: "desktopcomputer") {
                    Task { await a.showOnComputer(for: .confirm(id)) }
                }
                .buttonStyle(QuietProminentStyle())
                .disabled(a.busy.contains(.confirm(id)))
            }
            if let note = a.notes[.confirm(id)] { NoteLine(note: note) }
            if a.notes[.confirm(id)]?.fail == false {
                NavigationLink { RemoteStreamView() } label: {
                    MobileLabel("Open Remote", icon: .remote)
                }.buttonStyle(QuietSecondaryStyle())
            }
        }.quietCard()
    }

    private func questionCard(_ a: AssistantModel, _ q: JSONValue) -> some View {
        let id = q["id"]?.string ?? ""
        let choices = (q["choices"]?.array ?? []).compactMap(\.string)
        let typed = Binding(get: { answerText[id] ?? "" }, set: { answerText[id] = $0 })
        let reply = (answerText[id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: Design.gap) {
            MobileLabel("It has a question", icon: .assistant).font(.headline)
            Text(q["question"]?.string ?? "").textSelection(.enabled)
            ForEach(choices, id: \.self) { choice in
                Button(choice) { Task { await a.answer(id, choice) } }
                    .buttonStyle(QuietSecondaryStyle())
                    .disabled(a.busy.contains(.question(id)))
            }
            TextField(choices.isEmpty ? "Your answer" : "Or say something else", text: typed, axis: .vertical)
                .lineLimit(1...5)
                .padding(Design.gap)
                .background(Design.background, in: .rect(cornerRadius: Design.controlRadius))
            Button("Answer", systemImage: "arrow.up") {
                Task {
                    await a.answer(id, reply)
                    if a.notes[.question(id)]?.fail != true { answerText[id] = nil }
                }
            }
            .buttonStyle(QuietProminentStyle())
            .disabled(reply.isEmpty || a.busy.contains(.question(id)))
            if let note = a.notes[.question(id)] { NoteLine(note: note) }
        }.quietCard()
    }

    private func pausedCard(_ a: AssistantModel, _ p: JSONValue) -> some View {
        VStack(alignment: .leading, spacing: Design.gap) {
            MobileLabel("It stopped at a limit", icon: .assistant).font(.headline)
            Text(p["why"]?.string ?? "It reached a limit you set.").textSelection(.enabled)
            Text(limitWords(p)).font(.callout).foregroundStyle(Design.muted)
            Button("Keep going on the computer", systemImage: "desktopcomputer") {
                Task { await a.showOnComputer(for: .show) }
            }
            .buttonStyle(QuietProminentStyle())
            .disabled(a.busy.contains(.show))
            if let note = a.notes[.show] { NoteLine(note: note) }
            if a.notes[.show]?.fail == false {
                NavigationLink { RemoteStreamView() } label: {
                    MobileLabel("Open Remote", icon: .remote)
                }.buttonStyle(QuietSecondaryStyle())
            }
        }.quietCard()
    }

    private func limitWords(_ p: JSONValue) -> String {
        var parts: [String] = []
        if let s = p["steps"]?.int { parts.append("\(s) steps") }
        if let m = p["minutes"]?.int { parts.append("\(m) min") }
        if let c = p["cost_usd"]?.number { parts.append(String(format: "$%.2f", c)) }
        return parts.isEmpty ? "" : "So far: " + parts.joined(separator: " · ")
    }

    private func steerCard(_ a: AssistantModel) -> some View {
        let text = steerText.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: Design.gap) {
            Text("Tell it more").font(.headline)
            TextField("A correction now, or a task for after this one", text: $steerText, axis: .vertical)
                .lineLimit(1...5)
                .padding(Design.gap)
                .background(Design.background, in: .rect(cornerRadius: Design.controlRadius))
            HStack {
                Button("Steer now", systemImage: "arrow.turn.up.right") {
                    Task { if await a.steer(text) { steerText = "" } }
                }
                .buttonStyle(QuietSecondaryStyle())
                .disabled(text.isEmpty || a.busy.contains(.steer))
                Button("After this", systemImage: "text.append") {
                    Task { if await a.enqueue(text, asNew: true) { steerText = "" } }
                }
                .buttonStyle(QuietSecondaryStyle())
                .disabled(text.isEmpty || a.busy.contains(.queue))
            }
            if let note = a.notes[.steer] { NoteLine(note: note) }
            if let note = a.notes[.queue] { NoteLine(note: note) }
            if !a.queue.isEmpty {
                Text("Waiting their turn").font(.subheadline.weight(.semibold))
                ForEach(Array(a.queue.enumerated()), id: \.offset) { _, item in
                    let id = item["id"]?.string ?? ""
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(queueWords(item)).font(.callout)
                            Spacer(minLength: 0)
                            Button("Take it off", systemImage: "xmark") { Task { await a.unqueue(id) } }
                                .labelStyle(.iconOnly).buttonStyle(.borderless)
                                .disabled(a.busy.contains(.unqueue(id)))
                        }
                        if let note = a.notes[.unqueue(id)] { NoteLine(note: note) }
                    }
                }
            }
        }.quietCard()
    }

    private func queueWords(_ item: JSONValue) -> String {
        let text = item["text"]?.string ?? ""
        if let by = item["by"]?.string, !by.isEmpty, by != "you" { return "From \(by): \(text)" }
        return text
    }

    private func resultCard(_ s: JSONValue) -> some View {
        VStack(alignment: .leading, spacing: Design.gap) {
            HStack(spacing: 8) {
                Circle().fill(s["ok"]?.bool == false || s["reason"]?.string == "partial" ? Design.caution : Design.success).frame(width: 8, height: 8)
                Text(s["reason"]?.string == "partial" ? "Partly completed" : s["ok"]?.bool == false ? "It didn't finish" : "Last result").font(.headline)
            }
            AnswerParts(answer: s["answer"], fallback: s["summary"]?.string ?? s["reason"]?.string ?? "")
        }.quietCard()
    }

    // MARK: - Earlier

    private func historySection(_ a: AssistantModel) -> some View {
        @Bindable var a = a
        return VStack(alignment: .leading, spacing: Design.gap) {
            HStack {
                Text("Earlier tasks").font(.title2.weight(.medium))
                if a.unseen > 0 {
                    Text("\(a.unseen) new").font(.footnote.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Design.surface, in: .capsule)
                }
            }
            TextField("Search earlier tasks", text: $a.search)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .onSubmit { Task { await a.loadHistory() } }
            if a.busy.contains(.history) { ProgressView().frame(maxWidth: .infinity) }
            if let note = a.notes[.history] { NoteLine(note: note) }
            if a.history.isEmpty && !a.busy.contains(.history) {
                Text(a.search.isEmpty ? "Nothing yet." : "Nothing matches.").foregroundStyle(Design.muted)
            }
            ForEach(Array(a.history.prefix(30).enumerated()), id: \.offset) { _, item in
                let id = item["id"]?.string ?? ""
                Button { openChatRef = Ref(id: id) } label: {
                    HStack(alignment: .top) {
                        Circle().fill(item["ok"]?.bool == false || item["reason"]?.string == "partial" ? Design.caution : Design.success)
                            .frame(width: 8, height: 8).padding(.top, 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item["title"]?.string ?? item["goal"]?.string ?? "Task")
                                .lineLimit(2).foregroundStyle(Design.ink)
                            Text(historyMeta(item)).font(.footnote).foregroundStyle(Design.muted)
                        }
                        Spacer(minLength: 0)
                        if item["seen"]?.bool == false {
                            Circle().fill(Design.ink).frame(width: 6, height: 6).padding(.top, 8)
                                .accessibilityLabel("New")
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(id.isEmpty)
            }
        }
    }

    private func historyMeta(_ item: JSONValue) -> String {
        var parts: [String] = []
        if item["reason"]?.string == "partial" { parts.append("Partly completed") }
        if let name = item["assistant_name"]?.string { parts.append(name) }
        if let turns = item["turns"]?.int, turns > 1 { parts.append("\(turns) turns") }
        if let steps = item["steps"]?.int { parts.append("\(steps) steps") }
        if let ended = item["ended"]?.number {
            parts.append(Date(timeIntervalSince1970: ended).formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func threadsSection(_ a: AssistantModel) -> some View {
        if !a.threads.isEmpty || a.notes[.thread] != nil {
            VStack(alignment: .leading, spacing: Design.gap) {
                Text("Messages between assistants").font(.title2.weight(.medium))
                if let note = a.notes[.thread] { NoteLine(note: note) }
                ForEach(Array(a.threads.enumerated()), id: \.offset) { _, t in
                    let id = t["id"]?.string ?? ""
                    Button { openThreadRef = Ref(id: id) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t["title"]?.string ?? "Conversation").foregroundStyle(Design.ink)
                            Text(threadMeta(t)).font(.footnote).foregroundStyle(Design.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .disabled(id.isEmpty)
                }
            }
        }
    }

    private func threadMeta(_ t: JSONValue) -> String {
        var parts: [String] = []
        if let names = t["names"]?.array?.compactMap(\.string), !names.isEmpty {
            parts.append(names.joined(separator: ", "))
        }
        switch t["state"]?.string {
        case "talking": parts.append("talking")
        case "waiting": parts.append("waits for you")
        default: break
        }
        if let unread = t["unread"]?.int, unread > 0 { parts.append("\(unread) unread") }
        return parts.joined(separator: " · ")
    }

    /// Names the one thing standing between this device and Assistant, in the order a person would fix it.
    private var blocker: (title: String, detail: String) {
        guard let selected = model.selected else {
            return ("Connect to your computer", "Add a Computer connection to hand tasks to your desktop Assistant.")
        }
        if selected.kind != .computer {
            return (
                "Assistant needs a Computer connection",
                "The k-chain desktop service carries controls only. Choose a Computer connection in Connections."
            )
        }
        if !model.online {
            return ("Your computer is out of reach", "Keep your computer awake and on a network this device can reach.")
        }
        if model.hub?.stopped == true {
            return (
                "Paused on your computer", "Remote services are paused. Resume them on your computer to use Assistant."
            )
        }
        return ("Full control needed", "Approve full control for this device on your computer. You can ask from Computer.")
    }
}

// MARK: - Pieces

/// A message beside its control: a status dot and calm words, never a red card.
struct NoteLine: View {
    let note: AssistantModel.Note
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(note.fail ? Design.caution : Design.success).frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(note.text).font(.callout).foregroundStyle(Design.ink).textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StepRow: View {
    let text: String
    let status: String?
    var detail: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint).font(.footnote).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.callout)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.footnote).foregroundStyle(Design.muted).lineLimit(3)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(status ?? "")
    }
    private var symbol: String {
        switch status {
        case "done", "ok": "checkmark.circle"
        case "running", "doing", "now": "circle.dotted"
        case "fail", "failed", "refused": "exclamationmark.circle"
        default: "circle"
        }
    }
    private var tint: Color {
        switch status {
        case "done", "ok": Design.success
        case "fail", "failed", "refused": Design.caution
        default: Design.muted
        }
    }
}

/// The result in its parts: the answer, a row per detail, what it didn't check, where it read.
struct AnswerParts: View {
    let answer: JSONValue?
    let fallback: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(answer?["answer"]?.string ?? fallback).textSelection(.enabled)
            ForEach(Array(list("details").enumerated()), id: \.offset) { _, d in Text("• " + d).font(.callout) }
            if let pick = answer?["pick"]?.string, !pick.isEmpty {
                Text("Recommended: \(pick)").font(.callout.weight(.medium)).textSelection(.enabled)
            }
            if !list("unconfirmed").isEmpty {
                Text("Not found in its sources").font(.callout.weight(.semibold))
                ForEach(Array(list("unconfirmed").enumerated()), id: \.offset) { _, item in
                    Text("• \(item)").font(.callout).foregroundStyle(Design.caution).textSelection(.enabled)
                }
            }
            if !list("not_done").isEmpty {
                Text("Not done: " + list("not_done").joined(separator: "; ")).font(.callout)
                    .foregroundStyle(Design.muted)
            }
            if !list("sources").isEmpty {
                Text("Read at " + list("sources").joined(separator: ", ")).font(.footnote)
                    .foregroundStyle(Design.muted).textSelection(.enabled)
            }
            if let words = answer?["answer"]?.string ?? Optional(fallback), !words.isEmpty {
                Button("Copy the answer", systemImage: "doc.on.doc") { UIPasteboard.general.string = words }
                    .buttonStyle(.borderless).font(.callout)
            }
        }
    }
    private func list(_ key: String) -> [String] { (answer?[key]?.array ?? []).compactMap(\.string) }
}

/// One earlier chat: its turns and a follow-up that goes on in the same chat.
private struct AssistantChatSheet: View {
    let assistant: AssistantModel
    let id: String
    @Environment(\.dismiss) private var dismiss
    @State private var followUp = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.inset) {
                    if assistant.busy.contains(.chat) && assistant.chat == nil {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    if let note = assistant.notes[.chat] { NoteLine(note: note) }
                    if let chat = assistant.chat {
                        ForEach(Array((chat["turns"]?.array ?? []).enumerated()), id: \.offset) { _, turn in
                            VStack(alignment: .leading, spacing: Design.gap) {
                                Text(turn["goal"]?.string ?? "").font(.headline).textSelection(.enabled)
                                if turn["reason"]?.string == "partial" { Text("Partly completed").font(.callout).foregroundStyle(Design.caution) }
                                AnswerParts(answer: turn["answer"],
                                            fallback: turn["summary"]?.string ?? turn["reason"]?.string ?? "")
                            }.quietCard()
                        }
                        followUpCard(chat)
                    }
                }.quietPage()
            }
            .background(Design.background)
            .navigationTitle(assistant.chat?["title"]?.string ?? "Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await assistant.openChat(id) }
        }
    }

    @ViewBuilder private func followUpCard(_ chat: JSONValue) -> some View {
        let text = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: Design.gap) {
            if chat["running"]?.bool == true {
                Text("This chat is working on your computer now.").foregroundStyle(Design.muted)
            }
            TextField("Ask a follow-up", text: $followUp, axis: .vertical)
                .lineLimit(1...6)
                .padding(Design.gap)
                .background(Design.background, in: .rect(cornerRadius: Design.controlRadius))
            Button("Send", systemImage: "arrow.up") {
                Task {
                    if await assistant.startTask(text, follow: id) {
                        followUp = ""
                        dismiss()
                    }
                }
            }
            .buttonStyle(QuietProminentStyle())
            .disabled(text.isEmpty || assistant.running || assistant.busy.contains(.composer))
            if assistant.running {
                Text("A task is running; follow up once it ends, or queue it from the Assistant page.")
                    .font(.footnote).foregroundStyle(Design.muted)
            }
            if let note = assistant.notes[.composer] { NoteLine(note: note) }
        }.quietCard()
    }
}

/// One conversation between assistants, read here and answered as you.
private struct AssistantThreadSheet: View {
    let assistant: AssistantModel
    let id: String
    @Environment(\.dismiss) private var dismiss
    @State private var reply = ""

    var body: some View {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.gap) {
                    ForEach(Array((assistant.thread?["messages"]?.array ?? []).enumerated()), id: \.offset) { _, m in
                        let you = m["you"]?.bool == true || m["from"]?.string == "you"
                        VStack(alignment: .leading, spacing: 2) {
                            Text(you ? "You" : (m["name"]?.string ?? "Assistant"))
                                .font(.footnote.weight(.semibold)).foregroundStyle(Design.muted)
                            Text(m["text"]?.string ?? "").textSelection(.enabled)
                            if m["kind"]?.string == "suggest" {
                                Text("A suggestion: start it on your computer.").font(.footnote)
                                    .foregroundStyle(Design.muted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: you ? .trailing : .leading)
                        .padding(Design.gap)
                        .background(you ? Design.surface : Design.background, in: .rect(cornerRadius: Design.radius))
                    }
                    TextField("Write as you", text: $reply, axis: .vertical)
                        .lineLimit(1...5)
                        .padding(Design.gap)
                        .background(Design.surface, in: .rect(cornerRadius: Design.controlRadius))
                    Button("Reply", systemImage: "arrow.up") {
                        Task { if await assistant.replyInThread(id, text) { reply = "" } }
                    }
                    .buttonStyle(QuietProminentStyle())
                    .disabled(text.isEmpty || assistant.busy.contains(.thread))
                    if let note = assistant.notes[.thread] { NoteLine(note: note) }
                }.quietPage()
            }
            .background(Design.background)
            .navigationTitle(assistant.thread?["title"]?.string ?? "Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await assistant.openThread(id) }
        }
    }
}
