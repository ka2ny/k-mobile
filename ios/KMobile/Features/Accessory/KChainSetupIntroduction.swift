import SwiftUI

struct KChainSetupIntroduction: View {
    let discover: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 24) {
                        KChainDeviceView(face: .pair).frame(width: 100, height: 116).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Meet your k-chain").font(.title2.weight(.semibold))
                            Text("Your computer companion, connected through your iPhone.")
                                .foregroundStyle(Design.muted)
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Start on your k-chain").font(.title3.weight(.semibold))
                        Label("Settings → Bluetooth → Pair a phone", systemImage: "hand.tap")
                        Text("Keep it nearby. Your board will be discoverable for two minutes.")
                            .foregroundStyle(Design.muted)
                    }.quietCard()
                    Label("Next, iOS helps you choose your board and confirm matching numbers on both screens.", systemImage: "checkmark.shield")
                        .font(.callout).foregroundStyle(Design.muted)
                    DisclosureGroup("Can’t find your board?") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Turn Bluetooth on and reopen Pair a phone on the board to start a fresh two-minute window.")
                            Text("A board using Wi-Fi may stop advertising Bluetooth. Open Pair a phone to make it discoverable again.")
                            Text("Already paired? Cancel and use Reconnect in the k-chain tab.")
                        }.font(.callout).foregroundStyle(Design.muted).padding(.top, 8)
                    }
                }.quietPage().quietEntrance()
            }
            .background(Design.background)
            .safeAreaInset(edge: .bottom) {
                Button("Find my k-chain", systemImage: "antenna.radiowaves.left.and.right", action: discover)
                    .buttonStyle(QuietProminentStyle()).accessibilityIdentifier("accessory.discover")
                    .padding(Design.gap).frame(maxWidth: .infinity).background(Design.background)
            }
            .navigationTitle("Set up k-chain").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}
