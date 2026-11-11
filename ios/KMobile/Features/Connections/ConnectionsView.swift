import SwiftUI

struct ConnectionsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showPairing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.profiles) { profile in
                        Button {
                            model.select(profile.id)
                            dismiss()
                        } label: {
                            HStack(spacing: Design.gap) {
                                Image(systemName: profile.kind == .computer ? "desktopcomputer" : "wave.3.right")
                                    .foregroundStyle(Design.accent).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.name).foregroundStyle(.primary)
                                    Text(profile.kind.title).font(.subheadline).foregroundStyle(.secondary)
                                    Text(profile.origin.absoluteString).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.selectedID == profile.id {
                                    Image(systemName: "checkmark.circle.fill").accessibilityLabel("Selected")
                                }
                            }.padding(.vertical, 8)
                        }.disabled(model.interacting)
                    }
                    Button("Add connection", systemImage: "plus") { showPairing = true }
                        .frame(minHeight: 44).disabled(model.interacting)
                } footer: {
                    Text("Computer uses the phone gateway. Companion uses the desktop’s dedicated k-chain address. Each keeps its own pairing and permissions.")
                }
            }
            .navigationTitle("Connections")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showPairing) { PairingView() }
        }
    }
}
