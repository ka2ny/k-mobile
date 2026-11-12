import SwiftUI

struct AccessoryView: View {
    @Environment(AccessoryModel.self) private var accessory
    @State private var showSetup = false
    @State private var confirmForget = false

    var body: some View {
        List {
            Group {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        KChainDeviceView(face: accessory.face)
                            .frame(maxWidth: 220, maxHeight: 255)
                            .frame(maxWidth: .infinity)
                        Text(accessory.name ?? "Your k-chain")
                            .font(.title.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                        Text(accessory.status).foregroundStyle(Design.muted)
                        if accessory.streams > 0 {
                            Label(
                                accessory.streams == 1
                                    ? "1 active connection" : "\(accessory.streams) active connections",
                                systemImage: "lock.shield")
                        }
                    }.padding(.vertical, 12)
                }
                if let error = accessory.error {
                    Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(Design.danger) }
                }
                Section {
                    Button(
                        accessory.savedRelay ? "Reconnect k-chain" : "Pair your k-chain",
                        systemImage: "antenna.radiowaves.left.and.right"
                    ) {
                        if accessory.savedRelay { accessory.useSaved(.relay) } else { accessory.choose(.relay) }
                    }.disabled(accessory.working)
                    if accessory.savedRelay {
                        Button("Choose another k-chain", systemImage: "plus") { accessory.choose(.relay) }.disabled(
                            accessory.working)
                        Button("Disconnect", systemImage: "pause.circle") { accessory.disconnect() }
                    }
                } header: {
                    Text("Bluetooth companion")
                } footer: {
                    Text(
                        "On the board, open Settings → Bluetooth → Pair a phone. Confirm the same numbers on both screens. Your phone carries the board’s encrypted traffic to your computer when needed. Keep the app open for the most reliable connection."
                    )
                }
                Section {
                    Button("Set up board Wi-Fi", systemImage: "wifi") {
                        accessory.prepareSetup()
                        showSetup = true
                    }
                    .disabled(accessory.working)
                    NavigationLink {
                        BoardLinkView()
                    } label: {
                        MobileLabel("Link phone on your computer", icon: .computer)
                    }
                } footer: {
                    Text(
                        "Wi-Fi setup, Bluetooth pairing and the computer’s phone link each have their own confirmation. Computer permissions remain in desktop Settings."
                    )
                }
                if accessory.savedRelay {
                    Section {
                        Button("Forget Bluetooth accessory", role: .destructive) { confirmForget = true }
                            .disabled(accessory.working)
                    } footer: {
                        Text(
                            "This removes this app’s accessory access. Remove the phone on the board too if you want to revoke its saved bond. Desktop links are managed separately."
                        )
                    }
                }
            }
            .listRowBackground(Design.surface)
        }
        .quietList()
        .navigationTitle("k-chain")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSetup) { WiFiSetupView() }
        .confirmationDialog("Forget this Bluetooth accessory?", isPresented: $confirmForget, titleVisibility: .visible)
        {
            Button("Forget accessory", role: .destructive) { accessory.forget() }
        }
    }
}

struct WiFiSetupView: View {
    @Environment(AccessoryModel.self) private var accessory
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var code = ""
    @State private var ssid = ""
    @State private var password = ""
    @State private var openNetwork = false
    @State private var operation: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    if let address = accessory.joinedAddress {
                        Section {
                            Label("Connected to Wi-Fi", systemImage: "checkmark.circle")
                            Text(
                                "The board reported \(address). Finish computer enrollment on its screen, then reconnect Bluetooth if you use the phone relay."
                            )
                        }
                    } else {
                        Section {
                            KChainDeviceView(face: accessory.mode == .setup ? accessory.face : .wifi)
                                .frame(maxWidth: 160, maxHeight: 186)
                                .frame(maxWidth: .infinity)
                            Text(
                                "Open Wi-Fi setup on your k-chain. Keep this app open until the board confirms its connection."
                            )
                            Button("Choose board", systemImage: "wifi") {
                                if accessory.savedRelay { accessory.useSaved(.setup) } else { accessory.choose(.setup) }
                            }.disabled(accessory.working)
                            Text(accessory.status).foregroundStyle(Design.muted)
                        }
                        if accessory.mode == .setup && accessory.ready && !accessory.setupAuthenticated {
                            Section("Verify your board") {
                                SecureField("Six-digit Wi-Fi setup code", text: $code)
                                    .keyboardType(.numberPad).privacySensitive()
                                Button("Verify") {
                                    operation = Task {
                                        await accessory.authenticate(code: code)
                                        code = ""
                                    }
                                }.disabled(code.count != 6 || accessory.working)
                                Text("Use the Wi-Fi setup code, not the Phone screen’s linking code.").font(.footnote)
                                    .foregroundStyle(Design.muted)
                            }
                        }
                        if accessory.setupAuthenticated {
                            Section("Wi-Fi network") {
                                Button("Scan nearby networks", systemImage: "arrow.clockwise") {
                                    operation = Task { await accessory.scan() }
                                }
                                .disabled(accessory.working)
                                ForEach(accessory.networks) { network in
                                    Button {
                                        ssid = network.ssid
                                        openNetwork = network.auth == 0
                                        password = ""
                                    } label: {
                                        HStack {
                                            Text(network.ssid)
                                            Spacer()
                                            if !network.supported {
                                                Text("Unsupported").font(.caption)
                                            } else if ssid == network.ssid {
                                                Image(systemName: "checkmark").accessibilityLabel("Selected")
                                            }
                                        }
                                    }.disabled(!network.supported || accessory.working)
                                }
                                TextField("Network name", text: $ssid).textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .disabled(accessory.working)
                                Toggle("Open network (no password)", isOn: $openNetwork).disabled(accessory.working)
                                if !openNetwork {
                                    SecureField("Wi-Fi password", text: $password).privacySensitive().disabled(
                                        accessory.working)
                                }
                                Button("Connect board to Wi-Fi") {
                                    operation = Task {
                                        _ = await accessory.join(ssid: ssid, password: openNetwork ? "" : password)
                                        password = ""
                                    }
                                }.disabled(ssid.isEmpty || (!openNetwork && password.isEmpty) || accessory.working)
                            }
                        }
                        if accessory.working { Section { ProgressView("Waiting for your board…") } }
                        if let error = accessory.error { Section { Text(error).foregroundStyle(Design.danger) } }
                        Section("If Bluetooth setup is unavailable") {
                            Text(
                                "Use the board’s USB or SoftAP setup instructions. This app currently supports secure Bluetooth Wi-Fi setup; it does not join the setup hotspot. No Wi-Fi password is sent without verifying the board first."
                            )
                            .font(.footnote).foregroundStyle(Design.muted)
                        }
                    }
                }
                .listRowBackground(Design.surface)
            }
            .quietList()
            .navigationTitle("Board Wi-Fi")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(accessory.joinedAddress == nil ? "Cancel" : "Done") {
                        operation?.cancel()
                        if accessory.mode == .setup { accessory.disconnect() }
                        code = ""
                        password = ""
                        dismiss()
                    }
                }
            }
            .interactiveDismissDisabled(accessory.working)
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    operation?.cancel()
                    code = ""
                    password = ""
                }
            }
            .onDisappear {
                operation?.cancel()
                code = ""
                password = ""
                if accessory.mode == .setup { accessory.disconnect() }
            }
        }
    }
}

struct BoardLinkView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var code = ""
    @State private var remove: GatewayModels.BoardLink?
    @State private var cooldownActive = false
    var body: some View {
        Form {
            Group {
                Section {
                    Text(
                        "Associate this phone with your k-chain through the selected computer. This grants no control permissions and does not pair Bluetooth."
                    )
                    if let selected = model.selected { LabeledContent("Computer", value: selected.name) }
                }
                if model.supportsBoardLink {
                    Section("Board’s Phone screen") {
                        SecureField("Six-digit phone code", text: $code).keyboardType(.numberPad).privacySensitive()
                            .disabled(model.linkBusy)
                        Button("Link phone") {
                            Task { if await model.linkBoard(code: code) { code = "" } }
                        }.disabled(code.count != 6 || model.linkBusy || model.busy || cooldownActive)
                        if let retry = model.linkRetryAt, retry > .now {
                            Text("Try again after \(retry.formatted(date: .omitted, time: .standard)).")
                                .foregroundStyle(Design.muted)
                        }
                        Text(
                            "Codes expire after one minute and can be used once. Create a new code on the board if needed."
                        ).font(.footnote).foregroundStyle(Design.muted)
                    }
                    Section("Linked boards") {
                        if model.boardLinks.isEmpty { Text("No confirmed links").foregroundStyle(Design.muted) }
                        ForEach(model.boardLinks) { link in
                            HStack {
                                MobileLabel(link.board.name.isEmpty ? "k-chain" : link.board.name, icon: .accessory)
                                Spacer()
                                Button("Unlink", role: .destructive) { remove = link }.disabled(model.linkBusy)
                            }
                        }
                    }
                } else {
                    Section {
                        ContentUnavailableView(
                            "Phone linking unavailable", systemImage: "link",
                            description: Text(
                                "Select an online Computer connection that supports phone linking. The k-chain desktop service uses a different identity."
                            ))
                    }
                }
                if let error = model.linksError { Section { Text(error).foregroundStyle(Design.danger) } }
            }
            .listRowBackground(Design.surface)
        }
        .quietList()
        .navigationTitle("Phone link")
        .task(id: "\(model.selectedID?.uuidString ?? "none")-\(model.supportsBoardLink)-\(scenePhase)") {
            guard scenePhase == .active else {
                code = ""
                return
            }
            while !Task.isCancelled {
                guard model.supportsBoardLink else { return }
                await model.refreshBoardLinks()
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
        .task(id: model.linkRetryAt) {
            guard let deadline = model.linkRetryAt else {
                cooldownActive = false
                return
            }
            cooldownActive = deadline > .now
            do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) } catch { return }
            cooldownActive = false
        }
        .onChange(of: model.selectedID) { code = "" }
        .confirmationDialog(
            "Remove this phone’s desktop association?",
            isPresented: Binding(get: { remove != nil }, set: { if !$0 { remove = nil } }), titleVisibility: .visible
        ) {
            Button("Unlink phone", role: .destructive) {
                if let remove { Task { await model.unlinkBoard(remove.id) } }
                remove = nil
            }
        }
    }
}
