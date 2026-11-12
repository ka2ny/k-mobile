import SwiftUI

/// Agents on the phone: the queue (what needs you first), one agent's conversation with its
/// decision card and composer, new sessions, changes and quick replies. Every result shows next
/// to the control that asked for it (`AgentsModel.rowNote`, keyed per control).
struct AgentsView: View {
    @Environment(AppModel.self) private var model
    @State private var agents: AgentsModel?
    @Environment(\.scenePhase) private var scenePhase
    @State private var showNew = false
    @State private var showReplies = false

    var body: some View {
        Group {
            if let agents {
                AgentsQueue(agents: agents, showNew: $showNew, showReplies: $showReplies)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Design.background)
        .navigationTitle("Agents")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(model.connectionGeneration)-\(scenePhase)") {
            guard scenePhase == .active else { agents?.stop(); return }
            let current = agents ?? AgentsModel(app: model)
            agents = current
            current.start()
        }
        .onDisappear { agents?.stop() }
        .sheet(isPresented: $showNew) {
            if let agents { NavigationStack { AgentNewSession(agents: agents) } }
        }
        .sheet(isPresented: $showReplies) {
            if let agents { NavigationStack { AgentRepliesEditor(agents: agents) } }
        }
    }
}

// MARK: - Queue

private struct AgentsQueue: View {
    let agents: AgentsModel
    @Binding var showNew: Bool
    @Binding var showReplies: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Design.inset) {
                PageHeading(title: "Agents", detail: agents.loaded ? agents.summary : "Reading your sessions…",
                            eyebrow: agents.hostName.uppercased())
                header
                if agents.unpaired {
                    QuietEmptyState(
                        title: "Agents waits for full control",
                        detail: "Ask for full control on Computer, then approve it on your computer. This page updates by itself.",
                        icon: .agents)
                } else if let error = agents.listError, agents.rows.isEmpty {
                    QuietEmptyState(title: "Can't read your agents", detail: error, icon: .agents)
                    Button("Try again", systemImage: "arrow.clockwise") { Task { await agents.refresh() } }
                        .buttonStyle(QuietSecondaryStyle())
                } else if agents.loaded && agents.rows.isEmpty {
                    QuietEmptyState(
                        title: "No sessions yet",
                        detail: "Start one here, or run Claude Code or Codex in a project on your computer.",
                        icon: .agents)
                } else {
                    if let error = agents.listError {
                        AgentNote(text: error, tone: .caution)
                    }
                    ForEach(agents.groups, id: \.state) { group in
                        VStack(alignment: .leading, spacing: Design.gap) {
                            Text(group.title).font(.headline).accessibilityAddTraits(.isHeader)
                            ForEach(group.rows) { row in
                                NavigationLink {
                                    AgentDetail(agents: agents, id: row.id)
                                } label: {
                                    AgentQueueRow(row: row, note: agents.rowNote[row.id])
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }.quietPage().quietEntrance()
        }
        .refreshable { await agents.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Design.gap) { newButton; hostMenu; repliesButton }
                VStack(alignment: .leading, spacing: 8) { newButton; HStack { hostMenu; repliesButton } }
            }
            if let note = agents.hostNote { AgentNote(text: note, tone: .caution) }
        }
    }

    private var newButton: some View {
        Button("New session", systemImage: "plus") { showNew = true }
            .buttonStyle(QuietProminentStyle())
            .disabled(agents.unpaired)
    }

    private var hostMenu: some View {
        Menu {
            Button("This computer") { Task { await agents.pickHost(nil) } }
            ForEach(agents.hosts) { host in
                Button(host.name) { Task { await agents.pickHost(host.id) } }
            }
        } label: {
            Label(agents.hostName, systemImage: "desktopcomputer")
        }
        .buttonStyle(QuietSecondaryStyle())
        .task { await agents.loadHosts() }
    }

    private var repliesButton: some View {
        Button("Quick replies", systemImage: "text.bubble") { showReplies = true }
            .buttonStyle(QuietSecondaryStyle())
    }
}

private struct AgentQueueRow: View {
    let row: AgentRow
    let note: String?
    @Environment(\.mobileAccent) private var accent

    var body: some View {
        HStack(alignment: .top, spacing: Design.gap) {
            Circle().fill(dot).frame(width: 8, height: 8).padding(.top, 7).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(row.name).font(.headline).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(AgentLogic.age(row.updatedAt)).font(.footnote).foregroundStyle(Design.muted)
                }
                Text([row.engineLabel, row.project].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(Design.muted).lineLimit(1)
                if let d = row.decision {
                    Text("\(AgentLogic.decisionVerb(d.tool)): \(d.summary)")
                        .font(.callout).lineLimit(2)
                } else {
                    let words = AgentLogic.lastWords(row)
                    if !words.isEmpty { Text(words).font(.callout).foregroundStyle(Design.muted).lineLimit(2) }
                }
                if let note { AgentNote(text: note, tone: .caution) }
            }
            Image(systemName: "chevron.right").foregroundStyle(Design.muted).accessibilityHidden(true)
        }
        .quietCard()
        .accessibilityElement(children: .combine)
    }

    private var dot: Color {
        switch row.state {
        case "needs": Design.caution
        case "working": accent
        case "unreachable": Design.danger
        case "turn": Design.success
        default: Design.muted.opacity(0.5)
        }
    }
}

// MARK: - One agent

private struct AgentDetail: View {
    let agents: AgentsModel
    let id: String
    @State private var renaming = false
    @State private var newName = ""
    @State private var showChanges = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.inset) {
                if let row = agents.open {
                    head(row)
                    if let d = row.decision, AgentLogic.can(row, "decide") {
                        AgentDecisionCard(agents: agents, row: row, decision: d)
                    }
                    if let q = row.question, AgentLogic.can(row, "question") {
                        AgentQuestionForm(agents: agents, row: row, question: q)
                    }
                    conversation(row)
                    if AgentLogic.can(row, "send") {
                        AgentComposer(agents: agents, row: row)
                    } else if row.readOnly {
                        AgentNote(text: "Started in a terminal: you can read it here.", tone: .plain)
                    }
                    actions(row)
                    if let c = row.configuration, AgentLogic.can(row, "configure") {
                        AgentConfiguration(agents: agents, row: row, configuration: c)
                    }
                } else if let error = agents.openError {
                    QuietEmptyState(title: "Can't open this agent", detail: error, icon: .agents)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }.quietPage()
        }
        .background(Design.background)
        .navigationTitle(agents.open?.name ?? "Agent")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { agents.show(id) }
        .onDisappear { if agents.openID == id { agents.show(nil) } }
        .sheet(isPresented: $showChanges) {
            if let row = agents.open { NavigationStack { AgentChanges(agents: agents, row: row) } }
        }
    }

    private func head(_ row: AgentRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AgentLogic.titles[row.state] ?? row.status).font(.caption.monospaced()).tracking(1.2)
                .foregroundStyle(Design.muted)
            if renaming {
                HStack {
                    TextField("Name", text: $newName).textFieldStyle(.roundedBorder).submitLabel(.done)
                        .onSubmit { commitRename(row) }
                    Button("Save") { commitRename(row) }.buttonStyle(QuietProminentStyle())
                    Button("Cancel") { renaming = false }.buttonStyle(QuietSecondaryStyle())
                }
            } else {
                Text(row.name).font(.title.weight(.medium)).accessibilityAddTraits(.isHeader)
            }
            Text([row.engineLabel, row.cwd].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.subheadline).foregroundStyle(Design.muted).textSelection(.enabled)
            if let note = agents.rowNote["rename:" + row.id] { AgentNote(text: note, tone: .caution) }
        }
    }

    private func commitRename(_ row: AgentRow) {
        let name = newName
        renaming = false
        Task { await agents.rename(row, to: name) }
    }

    @ViewBuilder
    private func conversation(_ row: AgentRow) -> some View {
        let items = AgentLogic.items(row.messages)
        if items.isEmpty {
            let lines = AgentLogic.tailLines(row.tail)
            if !lines.isEmpty {
                Text(lines.joined(separator: "\n")).font(.footnote.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading).quietCard()
            }
        } else {
            VStack(alignment: .leading, spacing: Design.gap) {
                ForEach(items.suffix(40)) { item in AgentItemView(item: item) }
            }
        }
    }

    private func actions(_ row: AgentRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Design.gap) { actionButtons(row) }
                VStack(alignment: .leading, spacing: 8) { actionButtons(row) }
            }
            if let note = agents.rowNote[row.id] { AgentNote(text: note, tone: .caution) }
        }
    }

    @ViewBuilder
    private func actionButtons(_ row: AgentRow) -> some View {
        let busy = agents.busyRows.contains(row.id)
        if AgentLogic.can(row, "stop") {
            HoldButton(title: "Hold to stop", systemImage: "stop.fill", tint: Design.danger, disabled: busy) {
                Task { await agents.stopAgent(row) }
            }
        }
        if AgentLogic.can(row, "resume") {
            Button("Continue", systemImage: "play.fill") { Task { await agents.resume(row) } }
                .buttonStyle(QuietSecondaryStyle()).disabled(busy)
        }
        if AgentLogic.can(row, "codex") {
            Button("Join", systemImage: "person.badge.plus") { Task { await agents.joinCodex(row) } }
                .buttonStyle(QuietSecondaryStyle()).disabled(busy)
        }
        Button("Changes", systemImage: "doc.text.magnifyingglass") { showChanges = true }
            .buttonStyle(QuietSecondaryStyle())
        if AgentLogic.can(row, "rename") {
            Button("Rename", systemImage: "pencil") { newName = row.name; renaming = true }
                .buttonStyle(QuietSecondaryStyle())
        }
    }
}

private struct AgentItemView: View {
    let item: AgentItem
    @Environment(\.mobileAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !item.title.isEmpty {
                Text(item.title).font(.caption.monospaced()).foregroundStyle(Design.muted)
            }
            Text(item.body)
                .font(item.kind == .tool ? .footnote.monospaced() : .body)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: item.kind == .you ? .trailing : .leading)
        .background(
            RoundedRectangle(cornerRadius: Design.controlRadius)
                .fill(item.kind == .you ? accent.opacity(0.14) : Design.surface))
        .padding(item.kind == .you ? .leading : .trailing, 32)
    }
}

// MARK: - Decision

private struct AgentDecisionCard: View {
    let agents: AgentsModel
    let row: AgentRow
    let decision: AgentDecision

    var body: some View {
        let key = "decision:" + decision.id
        let busy = agents.busyRows.contains(key)
        VStack(alignment: .leading, spacing: Design.gap) {
            MobileLabel(AgentLogic.decisionVerb(decision.tool), icon: .agents).font(.headline)
            Text(decision.summary).font(.body)
            if !decision.detail.isEmpty {
                Text(decision.detail).font(.footnote.monospaced()).foregroundStyle(Design.muted)
                    .lineLimit(12).textSelection(.enabled)
            }
            if !decision.complete {
                Text("Part of what it wants to do isn't shown here. Check on your computer if unsure.")
                    .font(.footnote).foregroundStyle(Design.muted)
            }
            HStack(spacing: Design.gap) {
                Button("Deny", systemImage: "xmark") { Task { await agents.decide(row, allow: false) } }
                    .buttonStyle(QuietSecondaryStyle()).disabled(busy)
                HoldButton(title: "Hold to allow", systemImage: "checkmark", tint: Design.success, disabled: busy) {
                    Task { await agents.decide(row, allow: true) }
                }
            }
            if busy { Text("Sending your answer…").font(.footnote).foregroundStyle(Design.muted) }
            if let note = agents.rowNote[key] { AgentNote(text: note, tone: .caution) }
        }.quietCard()
    }
}

/// A press that only counts once held for 0.6 s; a short press does nothing. VoiceOver gets the
/// same action through an explicit accessibility action.
private struct HoldButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    var disabled = false
    let action: () -> Void
    @State private var progress: CGFloat = 0
    @State private var holding = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.body.weight(.medium))
            .padding(.horizontal, 16).frame(minHeight: 44)
            .background(alignment: .leading) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: Design.controlRadius).fill(tint.opacity(0.14))
                        RoundedRectangle(cornerRadius: Design.controlRadius).fill(tint.opacity(0.35))
                            .frame(width: g.size.width * progress)
                    }
                }
            }
            .opacity(disabled ? 0.5 : 1)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.6, perform: {
                guard !disabled else { return }
                progress = 0
                action()
            }, onPressingChanged: { pressing in
                guard !disabled else { return }
                withAnimation(pressing ? .linear(duration: reduce ? 0 : 0.6) : .easeOut(duration: 0.15)) {
                    progress = pressing ? 1 : 0
                }
            })
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if !disabled { action() } }
    }
}

// MARK: - Composer

private struct AgentComposer: View {
    let agents: AgentsModel
    let row: AgentRow

    var body: some View {
        @Bindable var agents = agents
        VStack(alignment: .leading, spacing: 8) {
            if !agents.replies.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(agents.replies) { reply in
                            Button(reply.label) { agents.send(row, text: reply.text) }
                                .buttonStyle(QuietControlStyle())
                                .disabled(isBusy)
                        }
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Say something", text: draft, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: Design.controlRadius).fill(Design.surface))
                Button {
                    agents.send(row, text: agents.drafts[row.id] ?? "")
                } label: {
                    Image(systemName: "arrow.up").frame(width: 44, height: 44)
                }
                .buttonStyle(QuietProminentStyle())
                .accessibilityLabel("Send")
                .disabled(isBusy || (agents.drafts[row.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
            }
            stateLine
        }
        .task { await agents.loadReplies() }
    }

    private var draft: Binding<String> {
        Binding(get: { agents.drafts[row.id] ?? "" }, set: { agents.drafts[row.id] = $0 })
    }

    private var isBusy: Bool {
        switch agents.compose { case .waiting, .sending: true; default: false }
    }

    @ViewBuilder private var stateLine: some View {
        switch agents.compose {
        case .idle: EmptyView()
        case .waiting(let s):
            HStack {
                Text("Sending in \(s) s").font(.footnote).foregroundStyle(Design.muted)
                Button("Undo") { agents.undoSend() }.font(.footnote.weight(.medium))
            }
        case .sending: Text("Sending…").font(.footnote).foregroundStyle(Design.muted)
        case .sent: Text("Sent.").font(.footnote).foregroundStyle(Design.muted)
        case .failed(let why): AgentNote(text: why, tone: .caution)
        }
    }
}

// MARK: - Question

private struct AgentQuestionForm: View {
    let agents: AgentsModel
    let row: AgentRow
    let question: JSONValue
    @State private var selected: [String: Set<String>] = [:]
    @State private var custom: [String: String] = [:]

    var body: some View {
        let qid = question["id"]?.string ?? ""
        let key = "question:" + qid
        let parts = question["questions"]?.array ?? []
        VStack(alignment: .leading, spacing: Design.gap) {
            MobileLabel("It asks you", icon: .agents).font(.headline)
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                let pid = part["id"]?.string ?? ""
                let multiple = part["multiple"]?.truthy == true
                VStack(alignment: .leading, spacing: 8) {
                    Text(part["prompt"]?.string ?? "").font(.body.weight(.medium))
                    if let d = part["detail"]?.string, !d.isEmpty {
                        Text(d).font(.footnote).foregroundStyle(Design.muted)
                    }
                    ForEach(Array((part["options"]?.array ?? []).enumerated()), id: \.offset) { _, option in
                        let label = option["label"]?.string ?? ""
                        let on = selected[pid, default: []].contains(label)
                        Button {
                            var set = multiple ? selected[pid, default: []] : []
                            if on { set.remove(label) } else { set.insert(label) }
                            selected[pid] = set
                        } label: {
                            HStack(alignment: .top) {
                                Image(systemName: on ? (multiple ? "checkmark.square.fill" : "largecircle.fill.circle")
                                                     : (multiple ? "square" : "circle"))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(label)
                                    if let d = option["description"]?.string, !d.isEmpty {
                                        Text(d).font(.footnote).foregroundStyle(Design.muted)
                                    }
                                }
                                Spacer(minLength: 0)
                            }.frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                    if part["allowCustom"]?.truthy != false {
                        TextField(part["options"]?.array?.isEmpty == false ? "Another answer…" : "Your answer…",
                                  text: Binding(get: { custom[pid] ?? "" },
                                                set: { custom[pid] = String($0.prefix(12000)) }),
                                  axis: .vertical)
                            .lineLimit(1...5).textFieldStyle(.roundedBorder)
                    }
                }
            }
            Button("Send answers") {
                var draft: [String: (selected: [String], custom: String)] = [:]
                for part in parts {
                    let pid = part["id"]?.string ?? ""
                    draft[pid] = (Array(selected[pid] ?? []), custom[pid] ?? "")
                }
                Task {
                    if await agents.answer(row, draft: draft) { selected = [:]; custom = [:] }
                }
            }
            .buttonStyle(QuietProminentStyle())
            .disabled(agents.busyRows.contains(key))
            if let note = agents.rowNote[key] { AgentNote(text: note, tone: .caution) }
        }.quietCard()
    }
}

// MARK: - Configuration

private struct AgentConfiguration: View {
    let agents: AgentsModel
    let row: AgentRow
    let configuration: JSONValue

    var body: some View {
        let options = configuration["options"]?.array ?? []
        if !options.isEmpty {
            VStack(alignment: .leading, spacing: Design.gap) {
                MobileLabel("Session settings", icon: .controls).font(.headline)
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    let oid = option["id"]?.string ?? ""
                    let choices = option["choices"]?.array ?? []
                    let current = option["value"] ?? .null
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(option["label"]?.string ?? oid)
                            Spacer()
                            Menu {
                                ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                                    let value = choice["value"] ?? .null
                                    Button {
                                        Task { await agents.configure(row, option: oid, value: value) }
                                    } label: {
                                        if value == current {
                                            Label(choice["label"]?.string ?? "", systemImage: "checkmark")
                                        } else {
                                            Text(choice["label"]?.string ?? "")
                                        }
                                    }
                                }
                            } label: {
                                Text(choices.first { ($0["value"] ?? .null) == current }?["label"]?.string ?? "Choose")
                            }
                            .disabled(agents.busyRows.contains("configure:" + oid))
                        }
                        if let d = option["description"]?.string, !d.isEmpty {
                            Text(d).font(.footnote).foregroundStyle(Design.muted)
                        }
                        if let note = agents.rowNote["configure:" + oid] { AgentNote(text: note, tone: .caution) }
                    }
                }
            }.quietCard()
        }
    }
}

// MARK: - Changes

private struct AgentChanges: View {
    let agents: AgentsModel
    let row: AgentRow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.gap) {
                if agents.changesLoading {
                    ProgressView("Reading the changes…").frame(maxWidth: .infinity).padding(.top, 40)
                } else if let note = agents.changesNote {
                    AgentNote(text: note, tone: .caution)
                    Button("Try again") { Task { await agents.loadChanges(row) } }.buttonStyle(QuietSecondaryStyle())
                } else if agents.changes.isEmpty {
                    QuietEmptyState(title: "No changes", detail: "Nothing in this project differs from its last commit.",
                                    icon: .files)
                } else {
                    Text(AgentLogic.changeSummary(agents.changes)).foregroundStyle(Design.muted)
                    ForEach(agents.changes) { file in
                        DisclosureGroup {
                            if file.binary {
                                Text("A binary file.").font(.footnote).foregroundStyle(Design.muted)
                            } else {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(Array(file.hunks.enumerated()), id: \.offset) { _, hunk in
                                        Text(hunk.header).font(.caption.monospaced()).foregroundStyle(Design.muted)
                                        ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                                            Text(line).font(.caption.monospaced())
                                                .foregroundStyle(line.hasPrefix("+") ? Design.success
                                                                 : line.hasPrefix("-") ? Design.danger : Design.ink)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }.textSelection(.enabled)
                            }
                        } label: {
                            HStack {
                                Text(file.path).font(.footnote.monospaced()).lineLimit(2)
                                Spacer()
                                Text("+\(file.added) −\(file.removed)").font(.footnote.monospaced())
                                    .foregroundStyle(Design.muted)
                            }
                        }.quietCard()
                    }
                }
            }.quietPage()
        }
        .background(Design.background)
        .navigationTitle("Changes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { await agents.loadChanges(row) }
    }
}

// MARK: - New session

private struct AgentNewSession: View {
    let agents: AgentsModel
    @Environment(\.dismiss) private var dismiss
    @State private var workplaceID: String?
    @State private var engine = ""
    @State private var first = ""
    @State private var started = false

    var body: some View {
        Form {
            Section("Project") {
                if agents.workplaces.isEmpty {
                    Text(agents.workplacesNote ?? "Reading your projects…").foregroundStyle(Design.muted)
                } else {
                    Picker("Project", selection: $workplaceID) {
                        ForEach(agents.workplaces) { w in Text(w.name).tag(Optional(w.id)) }
                    }
                }
            }
            Section("Agent") {
                Picker("Agent", selection: $engine) {
                    ForEach(agents.engines, id: \.self) { e in Text(AgentLogic.engines[e] ?? e).tag(e) }
                }
            }
            Section("First words") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(AgentLogic.intents, id: \.label) { intent in
                            Button(intent.label) { first = intent.text }.buttonStyle(QuietControlStyle())
                        }
                    }
                }
                TextField("What should it do?", text: $first, axis: .vertical).lineLimit(2...8)
            }
            Section {
                Button(agents.creating ? "Starting…" : "Start") {
                    guard let w = agents.workplaces.first(where: { $0.id == workplaceID }) else { return }
                    started = true
                    agents.create(workplace: w, engine: engine, firstMessage: first)
                }
                .disabled(agents.creating || workplaceID == nil || engine.isEmpty)
                if let note = agents.createNote { Text(note).font(.footnote).foregroundStyle(Design.muted) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Design.background)
        .navigationTitle("New session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        .task {
            await agents.loadWorkplaces()
            if workplaceID == nil { workplaceID = agents.workplaces.first?.id }
            if engine.isEmpty { engine = agents.engines.first ?? "" }
        }
        .onChange(of: agents.creating) { _, now in
            if started && !now && agents.createNote == nil { dismiss() }
        }
    }
}

// MARK: - Quick replies

private struct AgentRepliesEditor: View {
    let agents: AgentsModel
    @Environment(\.dismiss) private var dismiss
    @State private var list: [AgentReply] = []
    @State private var saving = false

    var body: some View {
        Form {
            Section {
                ForEach($list) { $reply in
                    VStack(alignment: .leading) {
                        TextField("Label", text: Binding(get: { reply.label },
                                                         set: { reply.label = String($0.prefix(24)) }))
                            .font(.body.weight(.medium))
                        TextField("What it sends", text: Binding(get: { reply.text },
                                                                 set: { reply.text = String($0.prefix(2000)) }),
                                  axis: .vertical).foregroundStyle(Design.muted)
                    }
                }
                .onDelete { list.remove(atOffsets: $0) }
                .onMove { list.move(fromOffsets: $0, toOffset: $1) }
                if list.count < 12 {
                    Button("Add a reply", systemImage: "plus") { list.append(AgentReply(label: "", text: "")) }
                }
            } footer: {
                Text("Shared by every device you use Agents on. Up to 12.")
            }
            Section {
                Button(saving ? "Saving…" : "Save") {
                    saving = true
                    Task { await agents.saveReplies(list); saving = false; if agents.repliesNote == nil { dismiss() } }
                }.disabled(saving)
                Button("Use the usual replies") {
                    saving = true
                    Task { await agents.saveReplies(nil); list = agents.replies; saving = false }
                }.disabled(saving)
                if let note = agents.repliesNote { Text(note).font(.footnote).foregroundStyle(Design.muted) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Design.background)
        .navigationTitle("Quick replies")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            ToolbarItem(placement: .primaryAction) { EditButton() }
        }
        .task { await agents.loadReplies(); list = agents.replies }
    }
}

// MARK: - Note

/// A result next to its control: a dot and calm words, never a red card.
private struct AgentNote: View {
    enum Tone { case plain, caution }
    let text: String
    let tone: Tone

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if tone == .caution { Circle().fill(Design.caution).frame(width: 6, height: 6).accessibilityHidden(true) }
            Text(text).font(.footnote).foregroundStyle(Design.muted).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
