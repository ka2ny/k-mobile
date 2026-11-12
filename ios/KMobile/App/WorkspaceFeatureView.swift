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
                        PageHeading(title: feature.rawValue, detail: feature.purpose)
                        VStack(alignment: .leading, spacing: Design.gap) {
                            MobileIcon(feature.icon, size: 32)
                            Text(unavailable).foregroundStyle(Design.muted)
                            Button(model.selected == nil ? "Connect a computer" : "Manage connections") {
                                showConnections = true
                            }.buttonStyle(QuietProminentStyle()).disabled(model.interacting)
                            if model.selected != nil {
                                Button("Try again", systemImage: "arrow.clockwise") {
                                    Task { await model.refresh(includeCompanion: false) }
                                }.buttonStyle(QuietSecondaryStyle()).disabled(model.refreshing)
                            }
                        }.quietCard()
                    }.quietPage()
                }
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
}
