import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Binding var showConnections: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.inset) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR PERSONAL ORBIT")
                        .font(.subheadline.monospaced()).foregroundStyle(.secondary)
                    Text("Your world.\nWithin reach.")
                        .font(.largeTitle).bold().tracking(-1)
                    Text("Your computer and k-chain, in one quiet place.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, Design.gap)

                connectionCard

                if model.selected != nil {
                    if model.online && model.device?.control != "full" {
                        permissionCard
                    }
                    if model.selected?.kind == .computer {
                        computerServices
                    } else {
                        Label("Companion connection", systemImage: "wave.3.right")
                            .font(.headline)
                        Text("Media, focus and agent decisions travel through your computer’s k-chain service. Add a Computer connection for Assistant and the mobile workspace.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: Design.gap) {
                        Label("A little closer to everything", systemImage: "circle.hexagongrid")
                            .font(.headline)
                        Text("Add your computer for controls and Assistant. Open the k-chain tab to pair your physical accessory.")
                            .foregroundStyle(.secondary)
                        Button("Connect your computer", systemImage: "plus") { showConnections = true }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    }.quietCard()
                }
            }.quietPage().quietEntrance()
        }
        .background(Design.background)
        .navigationTitle("k-hole")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh(includeCompanion: false) }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: Design.gap) {
            HStack(alignment: .top) {
                Image(systemName: model.selected?.kind == .companion ? "wave.3.right.circle" : "desktopcomputer")
                    .font(.largeTitle).foregroundStyle(Design.accent).accessibilityHidden(true)
                Spacer()
                ConnectionStatus(online: model.online, checking: model.refreshing && !model.online, selected: model.selected != nil)
            }
            Text(model.selected?.name ?? "Make yourself at home")
                .font(.title2).bold()
            Text(model.selected?.origin.host ?? "Your first connection starts here.")
                .font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
            if let error = model.connectionError {
                Text(error).font(.callout).foregroundStyle(.secondary)
            }
            if let date = model.lastUpdated, model.online {
                Text("Updated \(date.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button(model.selected == nil ? "Add connection" : "Switch connection", systemImage: "arrow.left.arrow.right") {
                showConnections = true
            }
            .buttonStyle(.bordered).controlSize(.large).disabled(model.interacting)
        }.quietCard()
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: Design.gap) {
            Label("Your computer has the final say", systemImage: "hand.raised")
                .font(.headline)
            Text("Approve full control on the computer before using companion actions or Assistant.")
                .foregroundStyle(.secondary)
            if let code = model.device?.fp {
                Text("Device code: \(code)").font(.body.monospaced()).textSelection(.enabled)
            }
            if model.selected?.kind == .computer {
                Button("Ask for full control") { Task { await model.requestControl() } }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.interacting)
                if let receipt = model.lastReceipt, model.receiptContext == "permission" {
                    Text(receipt + " Approve on your computer, then pull to refresh.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Text("On your computer: Settings → Remote → this device → Full control.")
                    .font(.callout)
            }
        }.quietCard()
    }

    private var computerServices: some View {
        VStack(alignment: .leading, spacing: Design.gap) {
            Text("Your workspace").font(.title2).bold()
            Text("Open the existing workspace in your browser. Browser pairing is separate from this app.")
                .font(.callout).foregroundStyle(.secondary)
            if let error = model.computerError { Text(error).font(.callout).foregroundStyle(.secondary) }
            if model.hub?.stopped == true {
                Label("Remote services are paused on your computer.", systemImage: "pause.circle")
            }
            if let profile = model.selected {
                service("Remote", detail: "Your desktop, wherever you are", icon: "display", path: "remote/", ready: model.hub?.remote, profile: profile)
                service("Beam & Files", detail: "Bring a file along", icon: "arrow.up.doc", path: "beam/", ready: model.hub?.beam, profile: profile)
                service("Agents", detail: "Pick up where your agents left off", icon: "terminal", path: "agents/", ready: model.hub?.agents, profile: profile)
            }
        }
    }

    private func service(_ title: String, detail: String, icon: String, path: String, ready: Bool?, profile: ConnectionProfile) -> some View {
        Link(destination: profile.origin.appending(path: path)) {
            HStack(spacing: Design.gap) {
                Image(systemName: icon).font(.title2).foregroundStyle(Design.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    Text(ready == nil ? "Availability unknown" : ready == true ? "Enabled on computer" : "Off on computer")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").accessibilityHidden(true)
            }.quietCard()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens in your browser")
        .disabled(!model.online || ready != true || model.hub?.stopped == true)
    }
}
