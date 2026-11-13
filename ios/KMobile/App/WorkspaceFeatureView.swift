import SwiftUI

/// Destinations stay discoverable; only their live content requires a working service.
struct WorkspaceFeatureView<Content: View>: View {
    let feature: WorkspaceFeature
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
                WorkspaceIntroduction(feature: feature, unavailable: unavailable, showConnections: $showConnections, draft: draft)
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
