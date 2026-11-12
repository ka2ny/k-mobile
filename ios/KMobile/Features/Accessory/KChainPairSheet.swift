import SwiftUI

/// Presented only after AccessorySetupKit dismisses its picker.
struct KChainPairSheet: View {
    @Environment(AccessoryModel.self) private var accessory
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    private var verified: Bool { accessory.pairing.verified && accessory.error == nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    KChainDeviceView(face: accessory.face)
                        .frame(maxWidth: 200, maxHeight: 232)
                        .scaleEffect(arrived || reduceMotion ? 1 : 0.94)
                        .opacity(arrived ? 1 : 0)
                        .accessibilityHidden(true)
                    VStack(spacing: 8) {
                        Text(accessory.name ?? "k-chain").font(.title2.weight(.semibold))
                        Text(verified ? "Bluetooth verified" : "Finish connecting")
                            .font(.headline)
                        Text(accessory.status).foregroundStyle(Design.muted)
                            .contentTransition(.opacity)
                    }.multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: 20) {
                        step("Accessory selected", detail: "iOS has authorized this app to access your board.", complete: true)
                        step("Confirm on both devices", detail: verified
                             ? "The board has sent a protected relay request."
                             : "Compare the numbers shown by iOS and on k-chain. Confirm only if they match. Saved bonds may reconnect without asking again.", complete: verified)
                        step("Relay connection", detail: accessory.streams > 0
                             ? "\(accessory.streams) TCP connection(s) active. Check the board for its computer sign-in status."
                             : "Your board opens a connection when it needs the phone’s network. Bluetooth verification alone does not confirm the computer is reachable.", complete: accessory.streams > 0)
                    }
                    if let error = accessory.error { PairingNote(text: error) }
                    if verified {
                        Text("Wi-Fi setup and linking this phone on your computer are optional next steps in the k-chain tab.")
                            .font(.footnote).foregroundStyle(Design.muted)
                    }
                    Button(verified ? "Done" : accessory.error == nil ? "Continue in app" : "Back to setup") {
                        if accessory.error != nil { accessory.disconnect() }
                        dismiss()
                    }.buttonStyle(QuietProminentStyle())
                    if !verified && accessory.error == nil {
                        Text("Keep k-mobile open while setup finishes.")
                            .font(.footnote).foregroundStyle(Design.muted)
                        Button("Cancel setup", role: .cancel) { accessory.disconnect(); dismiss() }
                            .buttonStyle(QuietSecondaryStyle())
                    }
                }.padding(Design.inset).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .background(Design.background)
            .navigationTitle("Connect k-chain")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(!verified)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: accessory.pairing.phase)
        .onAppear { withAnimation(reduceMotion ? nil : .smooth(duration: 0.4)) { arrived = true } }
        .sensoryFeedback(.success, trigger: verified) { _, now in now }
        .sensoryFeedback(.warning, trigger: accessory.error) { _, now in now != nil }
    }

    private func step(_ title: String, detail: String, complete: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: complete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(complete ? Color.accentColor : Design.muted).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(Design.muted)
            }
        }.accessibilityElement(children: .combine)
            .accessibilityValue(complete ? "Complete" : "Pending")
    }
}
