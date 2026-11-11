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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("A connection you can trust", systemImage: "link.circle")
                        .font(.title2).bold().padding(.vertical, 8)
                    Text("Keep your computer nearby. Pairing and permissions stay in your hands.")
                        .foregroundStyle(.secondary)
                }
                Section("Connect to") {
                    Picker("Connection type", selection: $kind) {
                        ForEach(ConnectionProfile.Kind.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Name, such as Studio", text: $name)
                        .textContentType(.nickname)
                    TextField("https://your-computer", text: $address)
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
                    Text(kind == .computer
                         ? "In Settings → Remote, enable the browser view. Enter its HTTPS address and PIN. Join the same tailnet if required."
                         : "In Settings → Remote → k-chain, enable the companion. Enter its HTTPS address (usually port 8445), certificate code and PIN. Your phone must reach its home network.")
                }
                if let errorMessage {
                    Section { Label(errorMessage, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
                }
                Section {
                    Button {
                        pairingTask = Task {
                            errorMessage = nil
                            if await model.pair(name: name, address: address, kind: kind, pin: pin, code: certificateCode) {
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
                            if model.busy { ProgressView() } else { Image(systemName: "arrow.right") }
                        }.frame(minHeight: 44)
                    }
                    .disabled(model.busy || address.isEmpty || pin.count != 6)
                }
            }
            .disabled(model.interacting)
            .navigationTitle("Make a connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { pairingTask?.cancel(); dismiss() } } }
            .interactiveDismissDisabled(model.busy)
            .onDisappear { pairingTask?.cancel(); pin = ""; certificateCode = "" }
        }
    }
}
