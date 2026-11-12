import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Binding var showConnections: Bool
    @Environment(\.mobileAccent) private var accent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.inset) {
                PageHeading(
                    title: "Your computer", detail: "Controls, files and agents from this phone.",
                    eyebrow: "K-HOLE / MOBILE")

                connectionCard

                if model.selected != nil {
                    if model.online && model.device?.control != "full" {
                        permissionCard
                    }
                    if model.selected?.kind == .computer {
                        computerServices
                    } else {
                        MobileLabel("Companion connection", icon: .controls)
                            .font(.headline)
                        Text(
                            "Media, focus and agent decisions travel through your computer’s k-chain service. Add a Computer connection for Assistant and the mobile workspace."
                        )
                        .foregroundStyle(Design.muted)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        MobileLabel("Have a k-chain?", icon: .accessory).font(.headline)
                        Text(
                            "Pair your board in the k-chain tab. Its Bluetooth connection is separate from your computer connection."
                        )
                        .font(.callout).foregroundStyle(Design.muted)
                    }.padding(.horizontal, 4)

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
            ViewThatFits(in: .horizontal) {
                connectionIdentity
                VStack(alignment: .leading, spacing: 12) {
                    MobileIcon(model.selected?.kind == .companion ? .controls : .computer, size: 32).foregroundStyle(
                        accent)
                    ConnectionStatus(
                        online: model.online, checking: model.refreshing && !model.online,
                        selected: model.selected != nil)
                }
            }
            Text(model.selected?.name ?? "Connect a computer")
                .font(.title2.weight(.medium))
            Text(model.selected?.origin.host ?? "Use the address and PIN in desktop Settings → Remote.")
                .font(.subheadline).foregroundStyle(Design.muted).textSelection(.enabled)
            if let error = model.connectionError {
                Text(error).font(.callout).foregroundStyle(Design.muted)
            }
            if let date = model.lastUpdated, model.online {
                Text("Updated \(date.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote).foregroundStyle(Design.muted)
            }
            // Keep one clear connection action in either state.
            if model.selected != nil {
                Button("Switch connection", systemImage: "arrow.left.arrow.right") { showConnections = true }
                    .buttonStyle(QuietSecondaryStyle()).disabled(model.interacting)
            } else {
                Button("Add connection", systemImage: "plus") { showConnections = true }
                    .buttonStyle(QuietProminentStyle()).disabled(model.interacting)
            }
        }.quietCard()
    }

    private var connectionIdentity: some View {
        HStack(alignment: .center, spacing: 16) {
            MobileIcon(model.selected?.kind == .companion ? .controls : .computer, size: 32).foregroundStyle(accent)
            Spacer(minLength: 12)
            ConnectionStatus(
                online: model.online, checking: model.refreshing && !model.online, selected: model.selected != nil
            )
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: Design.gap) {
            Label("Control permission", systemImage: "hand.raised")
                .font(.headline)
            Text("Approve full control on the computer before using companion actions or Assistant.")
                .foregroundStyle(Design.muted)
            if let code = model.device?.fp {
                Text("Device code: \(code)").font(.body.monospaced()).textSelection(.enabled)
            }
            if model.selected?.kind == .computer {
                Button("Ask for full control") { Task { await model.requestControl() } }
                    .buttonStyle(QuietProminentStyle()).disabled(model.interacting)
                if let receipt = model.lastReceipt, model.receiptContext == "permission" {
                    Text(receipt + " Approve on your computer. This page updates by itself.")
                        .font(.callout).foregroundStyle(Design.muted)
                }
            } else {
                Text("On your computer: Settings → Remote → this device → Full control.")
                    .font(.callout)
            }
        }.quietCard()
    }

    private var computerServices: some View {
        VStack(alignment: .leading, spacing: Design.gap) {
            Text("Workspace").font(.title2.weight(.medium)).accessibilityAddTraits(.isHeader)
            Text("Remote, Beam and Agents all run here in the app.")
                .font(.callout).foregroundStyle(Design.muted)
            if let error = model.computerError { Text(error).font(.callout).foregroundStyle(Design.muted) }
            if model.hub?.stopped == true {
                Label("Remote services are paused on your computer.", systemImage: "pause.circle")
            }
            if let profile = model.selected {
                NavigationLink {
                    RemoteStreamView()
                } label: {
                    serviceRow(
                        "Remote", detail: "View and control your desktop", icon: .remote,
                        ready: model.hub?.remote, trailing: "chevron.right")
                }
                .buttonStyle(.plain)
                .disabled(!serviceAvailable(model.hub?.remote))
                .opacity(serviceAvailable(model.hub?.remote) ? 1 : 0.6)
                NavigationLink {
                    BeamView()
                } label: {
                    serviceRow(
                        "Beam & Files", detail: "Send files and browse shared folders", icon: .beam,
                        ready: model.hub?.beam, trailing: "chevron.right")
                }
                .buttonStyle(.plain)
                .disabled(!serviceAvailable(model.hub?.beam))
                .opacity(serviceAvailable(model.hub?.beam) ? 1 : 0.6)
                NavigationLink {
                    AgentsView()
                } label: {
                    serviceRow(
                        "Agents", detail: "Review and steer coding sessions", icon: .agents,
                        ready: model.hub?.agents, trailing: "chevron.right")
                }
                .buttonStyle(.plain)
                .disabled(!serviceAvailable(model.hub?.agents))
                .opacity(serviceAvailable(model.hub?.agents) ? 1 : 0.6)
                NavigationLink {
                    YourComputersView()
                } label: {
                    serviceRow(
                        "Your computers", detail: "Open another k-hole computer with this pairing", icon: .computer,
                        ready: model.online ? true : nil, trailing: "chevron.right")
                }
                .buttonStyle(.plain)
                .disabled(!model.online)
                .opacity(model.online ? 1 : 0.6)
            }
        }
    }

    private func serviceAvailable(_ ready: Bool?) -> Bool {
        model.online && ready == true && model.hub?.stopped != true
    }

    private func serviceRow(
        _ title: String, detail: String, icon: MobileGlyph, ready: Bool?, trailing: String
    ) -> some View {
        HStack(spacing: Design.gap) {
            MobileIcon(icon).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(Design.muted)
                Text(
                    ready == nil
                        ? "Availability unknown" : ready == true ? "Enabled on computer" : "Off on computer"
                )
                .font(.footnote).foregroundStyle(Design.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: trailing).accessibilityHidden(true)
        }.quietCard()
    }
}
