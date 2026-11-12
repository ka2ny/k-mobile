import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Binding var showConnections: Bool
    @Environment(\.mobileAccent) private var accent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.inset) {
                PageHeading(
                    title: "Your computer", detail: "Open your desktop. Control what’s playing. Stay focused.",
                    eyebrow: "K-HOLE / MOBILE")

                connectionCard

                if model.online && model.device?.control != "full" { permissionCard }
                NavigationLink {
                    WorkspaceFeatureView(feature: .remote, showConnections: $showConnections) { RemoteStreamView() }
                } label: {
                    serviceRow("Open Remote", detail: "Your desktop, with touch and sound", icon: .remote,
                               ready: model.hub?.remote, trailing: "arrow.up.right")
                }.buttonStyle(.plain)
                if model.selected != nil { ComputerControlsView() }
                HStack(spacing: Design.gap) {
                    NavigationLink { ActivityView() } label: {
                        MobileLabel("Recent activity", icon: .activity)
                    }
                    Spacer(minLength: 8)
                    NavigationLink { YourComputersView() } label: {
                        MobileLabel("Computers", icon: .computer)
                    }
                }.font(.callout).padding(.vertical, 8)

            }.quietPage().quietEntrance()
        }
        .background(Design.background)
        .navigationTitle("Computer")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh(includeCompanion: true) }
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
