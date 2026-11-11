import SwiftUI

struct DecisionView: View {
    let decision: GatewayModels.Companion.Decision
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmAllow = false
    @State private var deciding = false

    private var isCurrent: Bool { model.companion?.agents?.top?.identity == decision.identity }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section("Agent request") {
                        LabeledContent("Agent", value: decision.name)
                        LabeledContent("Tool", value: decision.tool ?? "Unknown")
                        Text(decision.summary ?? "No summary supplied.").textSelection(.enabled)
                    }
                    Section {
                        Text(
                            "This is a shortened request summary. Inspect the full action on your computer if the scope is unclear."
                        )
                        if !isCurrent && !deciding {
                            Label(
                                "This request changed. Close and review the current one.",
                                systemImage: "clock.badge.exclamationmark")
                        }
                        if deciding { ProgressView("Waiting for your computer…") }
                        if let error = model.decisionError {
                            Label(error, systemImage: "exclamationmark.circle").foregroundStyle(Design.danger)
                        }
                        Button("Allow this request", systemImage: "checkmark.shield") { confirmAllow = true }
                            .frame(minHeight: 44)
                            .confirmationDialog(
                                "Allow this specific agent action?", isPresented: $confirmAllow,
                                titleVisibility: .visible
                            ) {
                                Button("Allow action") { decide(allow: true) }
                            } message: {
                                Text(decision.summary ?? decision.name)
                            }
                        Button("Deny request", systemImage: "xmark.shield", role: .destructive) { decide(allow: false) }
                            .frame(minHeight: 44)
                    }.disabled(!isCurrent || !model.canControl)
                }
                .listRowBackground(Design.surface)
            }
            .quietList()
            .navigationTitle("Review decision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .interactiveDismissDisabled(deciding)
            .onDisappear { model.clearDecisionError() }
        }
    }

    /// Close only after the computer accepted the answer. A failure stays here, next to the request it concerns.
    private func decide(allow: Bool) {
        deciding = true
        Task {
            let accepted = await model.decide(decision, allow: allow)
            deciding = false
            if accepted { dismiss() }
        }
    }
}
