import SwiftUI

struct PairingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var kind = ConnectionProfile.Kind.computer
    @State private var name = ""
    @State private var address = ""
    @State private var pin = ""
    @State private var certificateCode = ""
    @State private var errorMessage: String?
    @State private var pairingTask: Task<Void, Never>?
    @State private var scanning = false
    @State private var scanNote: String?

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        MobileLabel("Pair with your computer", icon: .connection)
                            .font(.title2.weight(.medium)).padding(.vertical, 8)
                        Text("Scan the code in Settings → Remote, or enter its address and the PIN shown there.")
                            .foregroundStyle(Design.muted)
                        if kind == .computer {
                            Button {
                                scanNote = nil
                                scanning = true
                            } label: {
                                Label("Scan the code on your computer", systemImage: "qrcode.viewfinder")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(QuietProminentStyle())
                            .disabled(model.busy)
                            if let scanNote {
                                PairingNote(text: scanNote)
                            }
                        }
                    }
                    Section("Connect to") {
                        Picker("Connection type", selection: $kind) {
                            ForEach(ConnectionProfile.Kind.allCases) { Text($0.title).tag($0) }
                        }
                        TextField("Name, such as Studio", text: $name)
                            .textContentType(.nickname)
                        TextField("Address, such as studio.example", text: $address)
                            .textContentType(.URL).keyboardType(.URL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    Section {
                        if kind == .companion {
                            TextField("Certificate code · XXXX-XXXX", text: $certificateCode)
                                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                                .font(.body.monospaced())
                        }
                        SecureField("Six-digit PIN", text: $pin)
                            .keyboardType(.numberPad).textContentType(.oneTimeCode)
                    } header: {
                        Text("Confirm on your computer")
                    } footer: {
                        Text(
                            kind == .computer
                                ? "In Settings → Remote, enable the browser view. Enter its HTTPS address and PIN. Join the same tailnet if required."
                                : "In Settings → Remote → k-chain, enable the companion. Enter its HTTPS address (usually port 8445), certificate code and PIN. Your phone must reach its home network."
                        )
                    }
                    Section {
                        Button {
                            pairingTask = Task {
                                errorMessage = nil
                                if await model.pair(
                                    name: name, address: address, kind: kind, pin: pin, code: certificateCode)
                                {
                                    pin = ""
                                    dismiss()
                                } else {
                                    pin = ""
                                    errorMessage = model.pairingError
                                }
                            }
                        } label: {
                            HStack {
                                Text(model.busy ? "Pairing…" : "Pair securely")
                                Spacer()
                                if model.busy {
                                    ProgressView()
                                } else {
                                    Image(systemName: "arrow.right").accessibilityHidden(true)
                                }
                            }.frame(minHeight: 44)
                        }
                        .disabled(model.busy || address.isEmpty || pin.count != 6)
                        if let errorMessage {
                            PairingNote(text: errorMessage)
                        }
                    }
                }
                .listRowBackground(Design.surface)
            }
            .disabled(model.interacting)
            .quietList()
            .navigationTitle("Make a connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        pairingTask?.cancel()
                        dismiss()
                    }
                }
            }
            .interactiveDismissDisabled(model.busy)
            .sheet(isPresented: $scanning) {
                ScanSheet { code in
                    scanning = false
                    switch code {
                    case .address(let found):
                        address = found
                        scanNote = "Address filled in. Type the PIN your computer shows."
                    case .ticket(let origin, let ticket):
                        pairingTask = Task {
                            scanNote = "Pairing with \(origin.host() ?? "your computer")…"
                            if await model.pair(ticket: ticket, origin: origin, name: name) {
                                dismiss()
                            } else {
                                scanNote = model.pairingError ?? "That code didn't pair this phone."
                            }
                        }
                    }
                }
            }
            .onDisappear {
                pairingTask?.cancel()
                pin = ""
                certificateCode = ""
            }
        }
    }
}

/// A result beside the control that made it: a calm dot and muted words, never a red card.
struct PairingNote: View {
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Design.caution).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(text).font(.callout).foregroundStyle(Design.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
