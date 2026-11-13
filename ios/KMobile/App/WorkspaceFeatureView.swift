import SwiftUI

/// Destinations stay discoverable; only their live content requires a working service.
struct WorkspaceFeatureView<Content: View>: View {
    enum Feature: String {
        case remote = "Remote", beam = "Beam", agents = "Agents", assistant = "Assistant"
        var icon: MobileGlyph {
            switch self { case .remote: .remote; case .beam: .beam; case .agents: .agents; case .assistant: .assistant }
        }
        var purpose: String {
            switch self {
            case .remote: "View your desktop, hear its audio and control it with touch."
            case .beam: "Send text and files, collect incoming shares and browse your shared folder."
            case .agents: "Follow coding sessions, review changes and answer agent requests."
            case .assistant: "Start tasks, answer questions and continue conversations with your computer."
            }
        }
    }
    let feature: Feature
    @Binding var showConnections: Bool
    var draft: Binding<String>? = nil
    @ViewBuilder var content: () -> Content
    @Environment(AppModel.self) private var model
    @State private var admittedGeneration: UUID?

    private var unavailable: String? {
        if model.selected == nil { return "Connect a computer to get started." }
        if model.selected?.kind != .computer { return "This feature needs a Computer connection. Add one using Settings → Remote on your desktop." }
        if !model.online { return model.connectionError ?? "Keep your computer awake and connected to the same network or tailnet." }
        if model.hub?.stopped == true { return "Resume remote services in Settings on your computer." }
        let enabled: Bool? = switch feature {
        case .remote: model.hub?.remote
        case .beam: model.hub?.beam
        case .agents: model.hub?.agents
        case .assistant: nil
        }
        if enabled == false { return "Turn on \(feature.rawValue) in Settings on your computer." }
        return nil
    }

    var body: some View {
        Group {
            if let unavailable, admittedGeneration != model.connectionGeneration {
                ScrollView {
                    VStack(alignment: .leading, spacing: Design.inset) {
                        PageHeading(title: introduction, detail: feature.purpose, eyebrow: feature.rawValue.uppercased())
                        VStack(alignment: .leading, spacing: Design.gap) {
                            if let draft {
                                Text(feature == .beam ? "Ready to send" : "Your next task").font(.headline)
                                TextField(feature == .beam ? "Words, a link, a code…" : "What would you like your computer to do?", text: draft, axis: .vertical)
                                    .lineLimit(3...8)
                                    .padding(14)
                                    .background(Design.background, in: .rect(cornerRadius: Design.controlRadius))
                                    .accessibilityIdentifier("workspace.draft")
                                Text("Your draft stays here while you connect.").font(.footnote).foregroundStyle(Design.muted)
                            } else {
                                MobileIcon(feature.icon, size: 32)
                            }
                            Text(unavailable).foregroundStyle(Design.muted)
                            Button(model.selected == nil ? "Connect a computer" : "Manage connections") {
                                showConnections = true
                            }.buttonStyle(QuietProminentStyle()).disabled(model.interacting)
                                .accessibilityIdentifier("workspace.connect")
                            if model.selected != nil {
                                Button("Try again", systemImage: "arrow.clockwise") {
                                    Task { await model.refresh(includeCompanion: false) }
                                }.buttonStyle(QuietSecondaryStyle()).disabled(model.refreshing)
                            }
                        }.quietCard()
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(capabilities, id: \.title) { item in
                                HStack(alignment: .top, spacing: 14) {
                                    Image(systemName: item.icon).frame(width: 24).foregroundStyle(Design.muted).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title).font(.headline)
                                        Text(item.detail).font(.callout).foregroundStyle(Design.muted)
                                    }
                                }
                            }
                        }.padding(.vertical, 8)
                    }.quietPage()
                }
                .scrollDismissesKeyboard(.interactively)
            } else {
                content().id(model.connectionGeneration)
            }
        }
        .background(Design.background)
        .navigationTitle(feature.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: unavailable, initial: true) { _, reason in
            if reason == nil { admittedGeneration = model.connectionGeneration }
        }
    }

    private var introduction: String {
        switch feature {
        case .beam: "From here to there."
        case .agents: "Keep your work moving."
        case .assistant: "A task off your mind."
        case .remote: "Your desktop, within reach."
        }
    }

    private var capabilities: [(title: String, detail: String, icon: String)] {
        switch feature {
        case .beam: [
            ("Send & receive", "Photos, files and text in either direction.", "arrow.up.arrow.down"),
            ("Your shared folder", "Find, preview and save files from your computer.", "folder"),
            ("Clipboard", "Bring copied text to your phone when you need it.", "doc.on.clipboard")]
        case .agents: [
            ("Decide what happens next", "Review permission requests and proposed changes.", "checkmark.bubble"),
            ("Continue a session", "Reply, steer or stop work from your phone.", "text.bubble"),
            ("Start something new", "Choose a project and give your coding agent a task.", "plus.square")]
        case .assistant: [
            ("Follow the work", "See the plan, answer questions and read the result.", "list.bullet.rectangle"),
            ("Pick up the conversation", "Return to earlier tasks and what your Assistant remembers.", "clock.arrow.circlepath")]
        case .remote: [
            ("Touch, type & listen", "Use your computer’s screen and sound on your phone.", "hand.draw"),
            ("You stay in control", "Your computer decides which permissions this phone has.", "lock.shield")]
        }
    }
}
