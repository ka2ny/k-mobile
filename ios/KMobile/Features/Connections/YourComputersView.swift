import SwiftUI

/// Every k-hole computer this phone can reach through the one it is paired with: `GET /app/computers`.
/// Open asks the paired computer for a two-minute ticket and pairs with the other one by it (pointer control).
/// Nothing here pairs on its own; pairing two computers stays on their screens.
struct YourComputersView: View {
    @Environment(AppModel.self) private var model
    @State private var me = ""
    @State private var computers: [(id: String, name: String)] = []
    @State private var others: [(id: String, name: String)] = []
    @State private var loaded = false
    @State private var readNote: String?
    @State private var notes: [String: String] = [:]
    @State private var opening: String?
    @State private var adding = false
    @State private var addNote: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.gap) {
                PageHeading(title: "Your computers", detail: "Open another k-hole computer with this phone's pairing.")
                if let readNote { PairingNote(text: readNote) }
                if !loaded && readNote == nil {
                    ProgressView("Asking your computer…").frame(maxWidth: .infinity)
                }
                if loaded {
                    row(name: me.isEmpty ? (model.selected?.name ?? "This computer") : me) {
                        Text("You're here").font(.footnote).foregroundStyle(Design.muted)
                    }
                    ForEach(computers, id: \.id) { computer in
                        VStack(alignment: .leading, spacing: 8) {
                            row(name: computer.name) {
                                Button(opening == computer.id ? "Opening…" : "Open") {
                                    Task { await open(computer.id, name: computer.name) }
                                }
                                .buttonStyle(QuietSecondaryStyle())
                                .disabled(opening != nil || model.busy)
                            }
                            if let note = notes[computer.id] { PairingNote(text: note) }
                        }
                    }
                    ForEach(others, id: \.id) { other in
                        row(name: other.name) {
                            Text("Turn on Your phones in Settings → Your devices there")
                                .font(.footnote).foregroundStyle(Design.muted)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add a computer").font(.headline)
                        Text("1. Open Settings → Your devices on both computers.\n2. Pair them and compare the six words.\n3. Turn on Your phones on the new one.")
                            .font(.callout).foregroundStyle(Design.muted)
                        Button(adding ? "Opening Your devices…" : "Open Your devices on this computer") {
                            Task { await add() }
                        }
                        .buttonStyle(QuietSecondaryStyle())
                        .disabled(adding)
                        if let addNote { PairingNote(text: addNote) }
                    }.quietCard()
                }
            }.quietPage()
        }
        .background(Design.background)
        .navigationTitle("Your computers")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func row<Trailing: View>(name: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: Design.gap) {
            MobileIcon(.computer).foregroundStyle(Design.muted)
            Text(name).font(.headline).lineLimit(2)
            Spacer(minLength: 8)
            trailing()
        }.quietCard()
    }

    private func load() async {
        guard let gateway = model.gateway else {
            readNote = "Connect to your computer first."
            return
        }
        do {
            let answer = try await gateway.get("/app/computers", as: JSONValue.self)
            me = Self.clean(answer["me"]?.string ?? "")
            computers = Self.list(answer["computers"])
            others = Self.list(answer["others"])
            readNote = nil
            loaded = true
        } catch is CancellationError {
        } catch {
            readNote = AssistantModel.words(error)
        }
    }

    private func open(_ id: String, name: String) async {
        guard let gateway = model.gateway else { return }
        opening = id
        notes[id] = nil
        defer { opening = nil }
        do {
            let answer = try await gateway.send("/app/computers/ticket", json: JSONValue.object(["id": .string(id)]),
                                                as: JSONValue.self)
            guard let url = answer["url"]?.string,
                  case .ticket(let origin, let ticket) = AppModel.readScannedCode(url)
            else {
                notes[id] = "Your computer sent a link this phone can't use."
                return
            }
            if await model.pair(ticket: ticket, origin: origin, name: name) {
                notes[id] = "Opened \(name). It starts at pointer control; ask for more there."
            } else {
                notes[id] = model.pairingError ?? "\(name) didn't let this phone in."
            }
        } catch {
            notes[id] = AssistantModel.words(error)
        }
    }

    private func add() async {
        guard let gateway = model.gateway else { return }
        adding = true
        defer { adding = false }
        do {
            _ = try await gateway.send("/app/computers/add", json: JSONValue.object([:]), as: JSONValue.self)
            addNote = "Your devices is open on your computer."
        } catch GatewayError.http(502, _) {
            addNote = "Your computer's desktop didn't answer. Open Settings → Your devices there."
        } catch {
            addNote = AssistantModel.words(error)
        }
    }

    private static func list(_ value: JSONValue?) -> [(id: String, name: String)] {
        (value?.array ?? []).compactMap { item in
            guard let id = item["id"]?.string, !id.isEmpty, id.count <= 64 else { return nil }
            return (id, clean(item["name"]?.string ?? "Computer"))
        }
    }

    /// Names come from another computer: no control or bidi characters, 40 at most.
    static func clean(_ s: String) -> String {
        let kept = s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0.properties.generalCategory != .format }
        return String(String.UnicodeScalarView(kept).prefix(40))
    }
}
