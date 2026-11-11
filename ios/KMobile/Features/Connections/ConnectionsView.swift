import SwiftUI

struct ConnectionsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.mobileAccent) private var accent
    @State private var showPairing = false

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                        ForEach(model.profiles) { profile in
                            Button {
                                model.select(profile.id)
                                dismiss()
                            } label: {
                                HStack(spacing: Design.gap) {
                                    MobileIcon(profile.kind == .computer ? .computer : .controls)
                                        .foregroundStyle(accent).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(profile.name).foregroundStyle(Design.ink)
                                        Text(profile.kind.title).font(.subheadline).foregroundStyle(Design.muted)
                                        Text(profile.origin.absoluteString).font(.footnote).foregroundStyle(
                                            Design.muted)
                                    }
                                    Spacer()
                                    if model.selectedID == profile.id {
                                        Image(systemName: "checkmark.circle").accessibilityLabel("Selected")
                                    }
                                }.padding(.vertical, 8)
                            }.disabled(model.interacting)
                        }
                        Button("Add connection", systemImage: "plus") { showPairing = true }
                            .frame(minHeight: 44).disabled(model.interacting)
                    } footer: {
                        Text(
                            "Computer uses the phone gateway. Companion uses the desktop’s dedicated k-chain address. Each keeps its own pairing and permissions."
                        )
                    }
                }
                .listRowBackground(Design.surface)
            }
            .quietList()
            .navigationTitle("Connections")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showPairing) { PairingView() }
        }
    }
}
