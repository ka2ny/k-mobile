import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance.mode") private var appearance = "system"
    @AppStorage("appearance.accent") private var accent = "sage"
    @State private var confirmForget = false

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        Picker("Appearance", selection: $appearance) {
                            ForEach(MobileAppearance.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        .accessibilityIdentifier("appearance.mode")
                        Picker("Accent", selection: $accent) {
                            ForEach(MobileAccent.allCases) { option in
                                HStack {
                                    Circle().fill(option.color).frame(width: 12, height: 12).accessibilityHidden(true)
                                    Text(option.title)
                                }.tag(option.rawValue)
                            }
                        }
                        .accessibilityIdentifier("appearance.accent")
                    } header: {
                        Text("Appearance")
                    } footer: {
                        Text(
                            "System follows your device. These preferences apply to this app; your computer keeps its own appearance."
                        )
                    }
                    Section("This connection") {
                        if let profile = model.selected {
                            LabeledContent("Name", value: profile.name)
                            LabeledContent("Type", value: profile.kind.title)
                            Text(profile.origin.absoluteString).textSelection(.enabled)
                            LabeledContent("Control", value: controlLabel)
                            Button("Forget on this device", role: .destructive) { confirmForget = true }
                                .disabled(model.interacting)
                                .confirmationDialog(
                                    "Forget this connection on this device?", isPresented: $confirmForget,
                                    titleVisibility: .visible
                                ) {
                                    Button("Forget connection", role: .destructive) { model.forgetSelected() }
                                } message: {
                                    Text(
                                        "The saved token and certificate pin will be deleted. To revoke access on the computer as well, remove this device in Settings → Remote on the computer."
                                    )
                                }
                        } else {
                            Text("No connection selected").foregroundStyle(Design.muted)
                        }
                    }
                    Section("Made for your device") {
                        Label("Motion follows accessibility settings", systemImage: "figure.walk")
                        Label("Supports larger text and VoiceOver", systemImage: "textformat.size")
                        Label("Credentials stay in Keychain", systemImage: "key")
                    }
                    Section("About") {
                        LabeledContent(
                            "k-hole",
                            value: "Native iOS · "
                                + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                                    ?? "Unknown"))
                        Text(
                            "Connects to your computer’s phone gateway and k-chain companion service. Includes Bluetooth board pairing and Wi-Fi setup. Voice recording and native desktop streaming are not included in this version."
                        )
                        .foregroundStyle(Design.muted)
                        Text(
                            "Remote, Beam and the full Agents workspace open in your browser. They may ask you to pair separately."
                        )
                        .foregroundStyle(Design.muted)
                        DisclosureGroup("Source notice") {
                            Text(sourceNotice).font(.footnote).textSelection(.enabled)
                        }
                    }
                }
                .listRowBackground(Design.surface)
            }
            .quietList()
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var controlLabel: String {
        guard let control = model.device?.control else { return "Unknown until connected" }
        switch control {
        case "full": return "Full control"
        case "view": return "View only"
        default: return control.capitalized
        }
    }

    private var sourceNotice: String {
        guard let url = Bundle.main.url(forResource: "SourceNotice", withExtension: "txt"),
            let notice = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "k-hole mark: © 2026 k-flow owner. See repository LICENSE.md."
        }
        return notice
    }
}
