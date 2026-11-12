import SwiftUI

/// The AirPods-style card that rises after the board is chosen in the system picker. The system picker can only show a
/// still picture, so the live board, its halo and every state word live here. Everything shown is the model's real
/// state: the board reads ready only once the encrypted Bluetooth link is up.
struct KChainPairSheet: View {
    @Environment(AccessoryModel.self) private var accessory
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    private var face: KChainDeviceView.Face { accessory.face }
    private var done: Bool { face == .ready && accessory.error == nil }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .background(Design.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            KChainDeviceView(face: face)
                .frame(width: 200, height: 232)
                .scaleEffect(arrived || reduceMotion ? 1 : 0.86)
                .opacity(arrived ? 1 : 0)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(accessory.name ?? "k-chain")
                    .font(.title2.weight(.semibold))
                Text(done ? "Connected. Your phone carries the board’s traffic now." : accessory.status)
                    .font(.callout).foregroundStyle(Design.muted)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
            }
            .accessibilityElement(children: .combine)
            if !done && accessory.error == nil {
                Text("Confirm the same numbers on the board when it asks.")
                    .font(.footnote).foregroundStyle(Design.muted).multilineTextAlignment(.center)
            }
            if let error = accessory.error {
                PairingNote(text: error)
                Button("Try again") { accessory.choose(.relay) }
                    .buttonStyle(QuietSecondaryStyle())
                    .frame(maxWidth: .infinity)
            }
            Button(done ? "Done" : "Keep pairing in the background") { dismiss() }
                .buttonStyle(QuietProminentStyle())
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Design.inset)
        .padding(.bottom, Design.inset)
        .padding(.top, 12)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(38)
        .presentationBackground(.ultraThinMaterial)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: face)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.55, bounce: 0.18)) { arrived = true }
        }
        .sensoryFeedback(.success, trigger: done) { _, now in now }
        .sensoryFeedback(.warning, trigger: accessory.error) { _, now in now != nil }
    }
}
