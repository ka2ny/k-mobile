import SwiftUI

struct DecisionView: View {
    let decision: GatewayModels.Companion.Decision
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmAllow = false

    private var isCurrent: Bool { model.companion?.agents?.top?.identity == decision.identity }

    var body: some View {
        NavigationStack {
            Form {
                Section("Agent request") {
                    LabeledContent("Agent", value: decision.name)
                    LabeledContent("Tool", value: decision.tool ?? "Unknown")
                    Text(decision.summary ?? "No summary supplied.").textSelection(.enabled)
                }
                Section {
                    Text("This is a shortened request summary. Inspect the full action on your computer if the scope is unclear.")
                    if !isCurrent { Label("This request changed. Close and review the current one.", systemImage: "clock.badge.exclamationmark") }
                    Button("Allow this request", systemImage: "checkmark.shield") { confirmAllow = true }
                        .frame(minHeight: 44)
                        .confirmationDialog("Allow this specific agent action?", isPresented: $confirmAllow, titleVisibility: .visible) {
                            Button("Allow action") {
                                Task { await model.decide(decision, allow: true); dismiss() }
                            }
                        } message: { Text(decision.summary ?? decision.name) }
                    Button("Deny request", systemImage: "xmark.shield", role: .destructive) {
                        Task { await model.decide(decision, allow: false); dismiss() }
                    }.frame(minHeight: 44)
                }.disabled(!isCurrent || !model.canControl)
            }
            .navigationTitle("Review decision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
