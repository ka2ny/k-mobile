import SwiftUI

/// Computer owns media, focus and lock. Agent decisions live in the Agents tab.
struct ComputerControlsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var confirmLock = false

    var body: some View {
        VStack(alignment: .leading, spacing: Design.gap) {
            if let error = model.companionError {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(Design.muted)
            }
            if model.hub?.stopped == true {
                Label("Controls paused on your computer", systemImage: "pause.circle")
            }
            controls
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Design.inset) {
            MobileLabel("Media & focus", icon: .controls).font(.headline)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 120), spacing: Design.gap)],
                spacing: Design.gap
            ) {
                ForEach(CompanionCommand.allCases.filter { $0 != .lock }) { command in
                    Button {
                        Task { await model.command(command) }
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: command.symbol).font(.title2.weight(.regular)).accessibilityHidden(true)
                            Text(command.title).font(.subheadline).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 84)
                        .padding(8)
                    }.buttonStyle(QuietControlStyle())
                }
            }
            // Permission decides how the keys look; a request in flight only holds further taps.
            .disabled(!model.controlAllowed || model.companion == nil)
            .allowsHitTesting(!model.interacting)
            Button("Lock computer", systemImage: "lock") { confirmLock = true }
                .buttonStyle(QuietSecondaryStyle()).disabled(!model.canControl)
                .confirmationDialog("Lock your computer now?", isPresented: $confirmLock, titleVisibility: .visible) {
                    Button("Lock computer") { Task { await model.command(.lock) } }
                }
            statusLine
        }.quietCard()
    }

    /// One fixed row for progress and receipts, so a key press never moves the controls under a thumb.
    private var statusLine: some View {
        Group {
            if model.busy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for your computer…")
                }
            } else if let receipt = model.lastReceipt,
                model.receiptContext == "controls" || model.receiptContext == "permission"
            {
                Label(receipt, systemImage: "checkmark.circle")
            } else if model.controlAllowed && model.companion == nil && model.companionError == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading controls…")
                }
            } else {
                Text("Responses from your computer appear here.")
            }
        }
        .font(.callout).foregroundStyle(Design.muted)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

}
