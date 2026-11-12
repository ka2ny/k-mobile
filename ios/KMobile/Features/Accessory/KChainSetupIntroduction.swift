import SwiftUI

struct KChainSetupIntroduction: View {
    let discover: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    KChainDeviceView(face: .pair)
                        .frame(maxWidth: 180, maxHeight: 209).frame(maxWidth: .infinity)
                    PageHeading(title: "Bring your k-chain close", detail: "A secure Bluetooth link lets your board use this phone’s network.")
                    Label("On k-chain, open Settings → Bluetooth → Pair a phone.", systemImage: "1.circle")
                    Label("Choose your board in the iOS accessory picker. The pairing window lasts two minutes.", systemImage: "2.circle")
                    Label("Compare the numbers on iPhone and k-chain, then confirm on both.", systemImage: "3.circle")
                    Button("Find my k-chain", systemImage: "antenna.radiowaves.left.and.right", action: discover)
                        .buttonStyle(QuietProminentStyle()).accessibilityIdentifier("accessory.discover")
                    DisclosureGroup("My board isn’t showing up") {
                        Text("Keep Bluetooth on and stay close. A board using Wi-Fi may stop advertising Bluetooth. Open Pair a phone on the board to start a new pairing window, then try again. For a saved accessory, use Reconnect instead.")
                            .font(.callout).foregroundStyle(Design.muted).padding(.top, 8)
                    }
                    Text("iOS owns the numeric confirmation. k-mobile never creates or guesses a pairing code.")
                        .font(.footnote).foregroundStyle(Design.muted)
                }.padding(Design.inset).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .background(Design.background)
            .navigationTitle("Set up k-chain")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}
