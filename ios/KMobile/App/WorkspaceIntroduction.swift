import SwiftUI

struct WorkspaceIntroduction: View {
    let feature: WorkspaceFeature
    let unavailable: String
    @Binding var showConnections: Bool
    var draft: Binding<String>?
    @Environment(AppModel.self) private var model
    @FocusState private var draftFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.inset) {
                PageHeading(title: introduction, detail: feature.purpose, eyebrow: feature.rawValue.uppercased())
                VStack(alignment: .leading, spacing: Design.gap) {
                    if let draft {
                        Text(feature == .beam ? "Ready to send" : "Your next task").font(.headline)
                        TextField(feature == .beam ? "Words, a link, a code…" : "What would you like your computer to do?", text: draft, axis: .vertical)
                            .lineLimit(3...8)
                            .focused($draftFocused)
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") { draftFocused = false }
                    .accessibilityIdentifier("workspace.hideKeyboard")
            }
        }
        .onChange(of: showConnections) { _, shown in if shown { draftFocused = false } }
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
