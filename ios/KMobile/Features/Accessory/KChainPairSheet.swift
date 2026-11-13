import SwiftUI

/// Presented after the system picker. Progress follows actual protected board traffic.
struct KChainPairSheet: View {
    @Environment(AccessoryModel.self) private var accessory
    @Environment(\.dismiss) private var dismiss
    private var verified: Bool { accessory.pairing.verified && accessory.error == nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    KChainDeviceView(face: accessory.face).frame(width: 150, height: 174).accessibilityHidden(true)
                    VStack(spacing: 8) {
                        Text(title).font(.title.weight(.semibold))
                        Text(accessory.name ?? "k-chain").font(.headline).foregroundStyle(Design.muted)
                        Text(instruction).foregroundStyle(Design.muted).contentTransition(.opacity)
                    }.multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: 18) {
                        stage("Board found", complete: true)
                        stage("Bluetooth confirmed", complete: verified)
                        stage(accessory.streams > 0 ? "Phone relay active" : "Ready when your board needs it", complete: accessory.streams > 0)
                    }.frame(maxWidth: .infinity, alignment: .leading).quietCard()
                    if let error = accessory.error { PairingNote(text: error) }
                    if verified {
                        Text("You can add Wi-Fi or link your phone on the computer next.")
                            .font(.callout).foregroundStyle(Design.muted)
                    } else if accessory.error == nil {
                        ProgressView("Waiting for k-chain…")
                        Text("Keep this app open until confirmation finishes.").font(.footnote).foregroundStyle(Design.muted)
                    }
                    DisclosureGroup("Connection details") {
                        Text(accessory.status).font(.callout).foregroundStyle(Design.muted)
                        Text("Bluetooth lets the board use your phone’s network. Your board shows whether it has signed in to your computer.")
                            .font(.footnote).foregroundStyle(Design.muted)
                    }
                }.quietPage()
            }.background(Design.background)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 8) {
                        if verified {
                            Button("Done") { dismiss() }.buttonStyle(QuietProminentStyle())
                        } else if accessory.error != nil {
                            Button("Try again") { accessory.useSaved(.relay) }.buttonStyle(QuietProminentStyle())
                            Button("Back to setup") { accessory.disconnect(); dismiss() }.buttonStyle(QuietSecondaryStyle())
                        } else {
                            Button("Cancel setup", role: .cancel) { accessory.disconnect(); dismiss() }.buttonStyle(QuietSecondaryStyle())
                        }
                    }.padding(Design.gap).frame(maxWidth: .infinity).background(Design.background)
                }
                .navigationTitle("Connect k-chain").navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large]).interactiveDismissDisabled(!verified)
        .quietStateAnimation(value: accessory.pairing.phase)
        .sensoryFeedback(.success, trigger: verified) { _, now in now }
        .sensoryFeedback(.warning, trigger: accessory.error) { _, now in now != nil }
    }

    private var title: String {
        if accessory.error != nil { return "Let’s try that again" }
        if verified { return "You’re connected" }
        return accessory.pairing.phase == .confirming ? "Check the numbers" : "Connecting your k-chain"
    }
    private var instruction: String {
        if accessory.error != nil { return "Your board hasn’t finished connecting." }
        if verified { return "Your k-chain can now use this iPhone’s network." }
        if accessory.pairing.phase == .confirming { return "Confirm on iPhone and k-chain only when both show the same numbers." }
        return "Keep your board close. iOS may ask you to confirm a pairing code."
    }
    private func stage(_ title: String, complete: Bool) -> some View {
        Label(title, systemImage: complete ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(complete ? Design.ink : Design.muted)
            .accessibilityValue(complete ? "Complete" : "Pending")
    }
}
