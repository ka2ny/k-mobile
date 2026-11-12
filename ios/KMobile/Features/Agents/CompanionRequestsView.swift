import SwiftUI

/// Preserve decisions offered by a companion-only connection in the canonical Agents destination.
struct CompanionRequestsView: View {
    @Environment(AppModel.self) private var model
    @State private var decision: GatewayModels.Companion.Decision?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.gap) {
                PageHeading(title: "Agents", detail: "Requests from your computer’s companion.")
                agentCard
                Text("Add a Computer connection for conversations, changes and new sessions.")
                    .foregroundStyle(Design.muted)
            }.quietPage()
        }
        .background(Design.background)
        .navigationTitle("Agents")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $decision) { DecisionView(decision: $0) }
    }
    private var agentCard: some View {
        VStack(alignment: .leading, spacing: Design.gap) {
            MobileLabel("Agent requests", icon: .agents).font(.headline)
            if let agents = model.companion?.agents {
                Text("\(agents.working) working · \(agents.needs) waiting")
                    .font(.subheadline).foregroundStyle(Design.muted)
                if let top = agents.top {
                    Text(top.name).font(.title3).bold()
                    Text(top.summary ?? "Review the request on your computer.")
                    Button("Review request", systemImage: "arrow.up.right") { decision = top }
                        .buttonStyle(QuietProminentStyle()).disabled(!model.controlAllowed)
                } else {
                    Text("Nothing needs a decision right now.").foregroundStyle(Design.muted)
                }
            } else if model.companion == nil && model.companionError == nil {
                Text("Checking for agent requests…").foregroundStyle(Design.muted)
            } else {
                Text("Agent status is unavailable. Enable the Agents connector on your computer.")
                    .foregroundStyle(Design.muted)
            }
        }.quietCard()
    }
}
