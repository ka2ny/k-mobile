import SwiftUI
import ESPProvision

/// Setting up a k-chain (the companion board): it takes your Wi-Fi from this phone over Bluetooth on first boot
/// (k-chain-os `k-moon/main/link/link.c`: Espressif's Wi-Fi provisioning, scheme BLE), then pairs with this computer.
///
/// 1. The board's screen shows a setup code: a QR in Espressif's format ({"ver":"v1","name":"k-chain-…","pop":…,
///    "transport":"ble","security":"2","username":"wifiprov"}) or the same code in words. Its proof of possession opens
///    a Security 2 session (SRP6a, then AES-GCM), so nothing nearby can read what follows or pose as the board.
/// 2. The phone asks the computer for what a board needs (GET /app/companion/setup: the home-network addresses and
///    port boards reach, the companion PIN, the certificate's code) and hands it over on the board's `khole-pair`
///    endpoint: the board pairs itself and pins the certificate whose code matches.
/// 3. The board lists the networks it can hear; you pick yours and type its password once; the board joins.
struct KChainSetupView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var setup = KChainSetup()
    @State private var scanning = false
    @State private var password = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content.padding(.horizontal, 20)
            }
            .navigationTitle("k-chain").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("close") { setup.stop(); dismiss() } } }
        }
        .foregroundStyle(Ink.text)
        .sheet(isPresented: $scanning) {
            QRScannerView { text in scanning = false; setup.start(code: text, model: model) }.ignoresSafeArea()
        }
    }

    @ViewBuilder private var content: some View {
        switch setup.step {
        case .intro:
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 54, weight: .light)).foregroundStyle(Ink.accent)
                Text("set up a k-chain").font(.system(size: 28)).kerning(-0.6)
                Text("turn it on. on first start its screen shows a setup code: scan it, and this phone gives it your wi-fi and pairs it with your computer.")
                    .font(.system(size: 16)).foregroundStyle(Ink.muted).multilineTextAlignment(.center)
                Spacer()
                Button { scanning = true } label: { Label("scan its code", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity, minHeight: 54) }
                    .buttonStyle(GlassButton(primary: true))
            }
        case .working(let words):
            VStack(spacing: 18) { Spacer(); ProgressView().tint(Ink.accent).scaleEffect(1.3); Text(words).foregroundStyle(Ink.muted); Spacer() }
        case .networks(let list):
            VStack(alignment: .leading, spacing: 10) {
                Text("its wi-fi").font(.system(size: 22)).padding(.top, 12)
                Text("the networks the k-chain hears. pick your home network.").font(.system(size: 14)).foregroundStyle(Ink.muted)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(list, id: \.ssid) { net in
                            Button { setup.pick(net.ssid) } label: {
                                HStack {
                                    Image(systemName: net.bars).foregroundStyle(Ink.accent).frame(width: 28)
                                    Text(net.ssid).font(.system(size: 17))
                                    Spacer()
                                    if net.locked { Image(systemName: "lock.fill").font(.system(size: 13)).foregroundStyle(Ink.muted) }
                                }.frame(minHeight: 54)
                            }
                            Divider().overlay(.white.opacity(0.1))
                        }
                    }
                }
            }
        case .password(let ssid):
            VStack(alignment: .leading, spacing: 16) {
                Text(ssid).font(.system(size: 22)).padding(.top, 12)
                SecureField("its password", text: $password)
                    .textContentType(.password).padding(14)
                    .background(Ink.glass, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("it goes to the k-chain over the secure link only; this phone keeps no copy.").font(.system(size: 13)).foregroundStyle(Ink.muted)
                Spacer()
                Button { setup.join(ssid: ssid, password: password); password = "" } label: { Text("join").frame(maxWidth: .infinity, minHeight: 54) }
                    .buttonStyle(GlassButton(primary: true)).disabled(password.isEmpty)
            }
        case .done(let name):
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "checkmark.circle").font(.system(size: 56, weight: .light)).foregroundStyle(Ink.accent)
                Text("\(name) is on your wi-fi").font(.system(size: 24)).multilineTextAlignment(.center)
                Text("it pairs with your computer by itself now. its screen shows the computer's words: they match the ones in settings, remote, k-chain.")
                    .font(.system(size: 15)).foregroundStyle(Ink.muted).multilineTextAlignment(.center)
                Spacer()
                Button { dismiss() } label: { Text("done").frame(maxWidth: .infinity, minHeight: 54) }.buttonStyle(GlassButton(primary: true))
            }
        case .failed(let words):
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "exclamationmark.triangle").font(.system(size: 48, weight: .light)).foregroundStyle(Ink.warn)
                Text(words).font(.system(size: 17)).multilineTextAlignment(.center)
                Spacer()
                Button { setup.step = .intro } label: { Text("try again").frame(maxWidth: .infinity, minHeight: 54) }.buttonStyle(GlassButton())
            }
        }
    }
}

struct Network: Equatable {
    let ssid: String
    let rssi: Int
    let locked: Bool
    var bars: String { rssi > -60 ? "wifi" : rssi > -72 ? "wifi" : "wifi.exclamationmark" }
}

@MainActor
final class KChainSetup: NSObject, ObservableObject, ESPDeviceConnectionDelegate {
    enum Step: Equatable { case intro, working(String), networks([Network]), password(String), done(String), failed(String) }
    @Published var step: Step = .intro
    private var device: ESPDevice?
    private var pop = "", username = "wifiprov"

    /// The board's setup code: Espressif's QR JSON. Only a BLE board named k-chain-…, Security 2.
    func start(code: String, model: AppModel) {
        guard let data = code.data(using: .utf8),
              let q = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = q["name"] as? String, name.lowercased().hasPrefix("k-chain"),
              let pop = q["pop"] as? String, !pop.isEmpty,
              (q["transport"] as? String ?? "ble") == "ble" else {
            step = .failed("that isn't a k-chain's setup code. it shows on the board's screen on first start.")
            return
        }
        self.pop = pop
        self.username = q["username"] as? String ?? "wifiprov"
        step = .working("asking your computer for the pairing details…")
        Task {
            // what the board needs from the computer, before any radio: no point in a session the computer can't finish
            let answer: AppModel.PageAnswer
            do { answer = try await model.ask("/app/companion/setup") } catch {
                step = .failed("the computer didn't answer. open k-hole on your home network and try again."); return
            }
            guard answer.status == 200 else {
                step = .failed((answer.json["error"] as? String ?? "the computer said no.").lowercased()); return
            }
            step = .working("finding \(name)…")
            ESPProvisionManager.shared.createESPDevice(deviceName: name, transport: .ble, security: .secure2,
                                                       proofOfPossession: pop, username: self.username) { [weak self] dev, _ in
                Task { @MainActor in
                    guard let self else { return }
                    guard let dev else { self.step = .failed("no k-chain called \(name) nearby. keep it close and on its setup screen."); return }
                    self.device = dev
                    self.step = .working("opening a secure link…")
                    dev.connect(delegate: self) { status in
                        Task { @MainActor in
                            switch status {
                            case .connected: self.handOver(answer.json)
                            case .failedToConnect: self.step = .failed("the k-chain didn't take the code. check it shows the same code and try again.")
                            default: self.step = .failed("the link to the k-chain dropped. try again close to it.")
                            }
                        }
                    }
                }
            }
        }
    }

    /// The computer's details for the board, on its own endpoint, then the networks it hears.
    private func handOver(_ details: [String: Any]) {
        guard let device, let data = try? JSONSerialization.data(withJSONObject: details) else { return }
        step = .working("giving it your computer…")
        device.sendData(path: "khole-pair", data: data) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if error != nil { self.step = .failed("this k-chain's software can't take a computer yet. update it over usb first."); return }
                self.listNetworks()
            }
        }
    }

    private func listNetworks() {
        step = .working("listening for wi-fi…")
        device?.scanWifiList { [weak self] list, _ in
            Task { @MainActor in
                guard let self else { return }
                var seen = Set<String>()
                let nets = (list ?? []).filter { !$0.ssid.isEmpty && seen.insert($0.ssid).inserted }
                    .sorted { $0.rssi > $1.rssi }
                    .map { Network(ssid: $0.ssid, rssi: Int($0.rssi), locked: $0.auth != .open) }
                self.step = nets.isEmpty ? .failed("the k-chain hears no wi-fi. bring it closer to your router.") : .networks(nets)
            }
        }
    }

    func pick(_ ssid: String) { step = .password(ssid) }

    func join(ssid: String, password: String) {
        guard let device else { return }
        step = .working("joining \(ssid)…")
        device.provision(ssid: ssid, passPhrase: password) { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .success: self.step = .done(device.name); device.disconnect()
                case .configApplied: self.step = .working("it is joining \(ssid)…")
                case .failure: self.step = .failed("it couldn't join \(ssid). check the password and try again.")
                }
            }
        }
    }

    func stop() { device?.disconnect(); device = nil }

    // ESPDeviceConnectionDelegate: the code from the board's screen, and the Security 2 user
    nonisolated func getProofOfPossesion(forDevice: ESPDevice, completionHandler: @escaping (String) -> Void) {
        Task { @MainActor in completionHandler(self.pop) }
    }
    nonisolated func getUsername(forDevice: ESPDevice, completionHandler: @escaping (String?) -> Void) {
        Task { @MainActor in completionHandler(self.username) }
    }
}
