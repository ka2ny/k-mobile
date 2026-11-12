import Foundation
import Observation
import UIKit
@preconcurrency import AccessorySetupKit
@preconcurrency import CoreBluetooth

@MainActor @Observable
final class AccessoryModel: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    enum Mode: String { case relay, setup }
    static let setupService = CBUUID(string: "1775244D-6B43-439B-877C-060F2D9BED07")
    static let relayService = CBUUID(string: "9F030001-5402-4278-97A5-F37FA38CCE5E")
    private static let rxID = CBUUID(string: "9F030002-5402-4278-97A5-F37FA38CCE5E")
    private static let txID = CBUUID(string: "9F030003-5402-4278-97A5-F37FA38CCE5E")
    private static let infoID = CBUUID(string: "9F030004-5402-4278-97A5-F37FA38CCE5E")

    private(set) var mode = Mode.relay
    private(set) var status = "Your k-chain, close at hand."
    private(set) var name: String?
    private(set) var ready = false
    private(set) var setupAuthenticated = false
    private(set) var working = false
    private(set) var streams = 0
    private(set) var networks: [ProvisioningMessages.Network] = []
    private(set) var joinedAddress: String?
    private(set) var savedRelay = false
    var error: String?

    @ObservationIgnored private let session = ASAccessorySession()
    @ObservationIgnored private var activated = false
    @ObservationIgnored private var activating = false
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectAttempts = 0
    @ObservationIgnored private var pendingPicker = false
    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var retiring: Set<UUID> = []
    @ObservationIgnored private var retireTask: Task<Void, Never>?
    @ObservationIgnored private var activeService: CBService?
    @ObservationIgnored private var wantedID: UUID?
    @ObservationIgnored private var relayEnabled = false
    @ObservationIgnored private var rx: CBCharacteristic?
    @ObservationIgnored private var tx: CBCharacteristic?
    @ObservationIgnored private var endpoints: [String: CBCharacteristic] = [:]
    @ObservationIgnored private var descriptorsRemaining = 0
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private var requestTimeout: Task<Void, Never>?
    @ObservationIgnored private var reply: CheckedContinuation<Data, Error>?
    @ObservationIgnored private var replyCharacteristic: CBCharacteristic?
    @ObservationIgnored private var security: ProvisioningSecurity?
    @ObservationIgnored private var relay: PhoneRelay?
    @ObservationIgnored private var requiresReset = false
    @ObservationIgnored private var epoch = UUID()

    override init() {
        super.init()
        savedRelay = UserDefaults.standard.string(forKey: "accessory.relay.id") != nil
        // Recreate the central on launch for CoreBluetooth restoration only for a saved relay.
        if savedRelay {
            activateSession()
            relayEnabled = UserDefaults.standard.bool(forKey: "accessory.relay.enabled")
            if relayEnabled {
                wantedID = savedID
                startCentral()
            }
        }
    }
    private func activateSession() {
        guard !activated, !activating else { return }
        activating = true
        session.activate(on: .main) { [weak self] event in
            MainActor.assumeIsolated { self?.accessoryEvent(event) }
        }
    }
    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectAttempts = min(reconnectAttempts + 1, 6)
        let delay = min(30, 1 << (reconnectAttempts - 1))
        status = "Board disconnected. Reconnecting shortly…"
        reconnectTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, self.relayEnabled else { return }
            self.connectKnown()
        }
    }
    private func accessoryEvent(_ event: ASAccessoryEvent) {
        switch event.eventType {
        case .activated:
            activating = false; activated = true
            if pendingPicker { pendingPicker = false; showPicker() }
        case .accessoryAdded, .accessoryChanged:
            guard pendingPicker, let accessory = event.accessory, let id = accessory.bluetoothIdentifier else { return }
            pendingPicker = false
            selected(id: id, name: accessory.displayName)
        case .accessoryRemoved:
            // Compare against the saved accessory, never nil == nil while nothing is connected.
            guard let removed = event.accessory?.bluetoothIdentifier else { break }
            if removed == savedID {
                disconnect(); clearSaved()
                error = "Accessory access was removed in Settings."
            } else if removed == wantedID { disconnect() }
        case .pickerDidDismiss:
            // A dismissal without a selection leaves nothing to wait for.
            if pendingPicker { pendingPicker = false; status = savedRelay ? "Disconnected" : "Your k-chain, close at hand." }
        case .invalidated:
            activated = false; pendingPicker = false
            disconnect(); error = "Accessory access ended. Reopen the app to try again."
        default: break
        }
        if let failure = event.error { error = failure.localizedDescription }
    }
    func prepareSetup() { joinedAddress = nil; error = nil }
    private var savedID: UUID? { UserDefaults.standard.string(forKey: "accessory.relay.id").flatMap(UUID.init(uuidString:)) }

    func choose(_ nextMode: Mode) {
        guard !working else { return }
        disconnect()
        mode = nextMode
        error = nil; joinedAddress = nil
        pendingPicker = true
        if activated { showPicker() } else { activateSession() }
    }
    private func showPicker() {
        let descriptor = ASDiscoveryDescriptor()
        descriptor.bluetoothServiceUUID = mode == .relay ? Self.relayService : Self.setupService
        descriptor.bluetoothNameSubstring = "k-chain-"
        guard let image = UIImage(named: "KChainDevice") else { error = "The k-chain picture is missing from this build, so the system picker can't open. Reinstall the app."; return }
        let item = ASPickerDisplayItem(name: "k-chain", productImage: image, descriptor: descriptor)
        pendingPicker = true
        let current = epoch
        session.showPicker(for: [item]) { [weak self] error in
            Task { @MainActor in
                guard let self, self.epoch == current else { return }
                if let error { self.pendingPicker = false; self.error = error.localizedDescription }
            }
        }
    }
    /// Reauthorize the known accessory for its other firmware service without assuming the old GATT database survived.
    func useSaved(_ nextMode: Mode) {
        guard !working, activated,
              let id = savedID,
              let accessory = session.accessories.first(where: { $0.bluetoothIdentifier == id }) else { choose(nextMode); return }
        disconnect(); mode = nextMode; error = nil; joinedAddress = nil
        let descriptor = ASDiscoveryDescriptor()
        descriptor.bluetoothServiceUUID = nextMode == .relay ? Self.relayService : Self.setupService
        descriptor.bluetoothNameSubstring = "k-chain-"
        let displayName = accessory.displayName
        let current = epoch
        session.updateAuthorization(for: accessory, descriptor: descriptor) { [weak self] error in
            Task { @MainActor in
                guard let self, self.epoch == current else { return }
                if let error { self.error = error.localizedDescription }
                else { self.selected(id: id, name: displayName) }
            }
        }
    }
    private func selected(id: UUID, name: String) {
        wantedID = id; self.name = name
        if mode == .relay {
            relayEnabled = true; savedRelay = true
            UserDefaults.standard.set(id.uuidString, forKey: "accessory.relay.id")
            UserDefaults.standard.set(true, forKey: "accessory.relay.enabled")
        }
        status = "Connecting to \(name)…"
        startCentral()
        connectKnown()
    }
    private func startCentral() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main,
                options: [CBCentralManagerOptionRestoreIdentifierKey: "app.khole.mobile.relay"])
        }
    }
    private func connectKnown() {
        guard let central, central.state == .poweredOn, let wantedID, peripheral == nil, !retiring.contains(wantedID) else { return }
        guard let found = central.retrievePeripherals(withIdentifiers: [wantedID]).first else {
            error = "The saved accessory is unavailable. Open its pairing screen and choose it again."
            return
        }
        peripheral = found; found.delegate = self
        central.connect(found)
        if mode == .setup { armTimeout("The board did not enter Wi-Fi setup. Open Wi-Fi setup on the board and try again.") }
        else { status = "Waiting for your k-chain…" }
    }
    func disconnect() {
        pendingPicker = false
        reconnectTask?.cancel(); reconnectTask = nil
        reconnectAttempts = 0
        relayEnabled = false
        UserDefaults.standard.set(false, forKey: "accessory.relay.enabled")
        wantedID = nil
        if let peripheral {
            if peripheral.state != .disconnected { retire(peripheral.identifier) }
            central?.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        resetTransport()
        status = "Disconnected"
    }
    /// Wait for the old link's disconnect callback before reconnecting the same board, but never indefinitely:
    /// cancelling a connection that was still pending is not guaranteed to report one.
    private func retire(_ id: UUID) {
        retiring.insert(id)
        retireTask?.cancel()
        retireTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self, !self.retiring.isEmpty else { return }
            self.retiring.removeAll()
            self.connectKnown()
        }
    }
    func forget() {
        guard !working else { return }
        guard activated, let id = savedID else {
            // Never fail silently on a destructive action the person asked for.
            error = "Accessory access is not ready. Reopen the app, or remove k-chain in Settings → Privacy & Security → Accessories."
            return
        }
        disconnect()
        guard let accessory = session.accessories.first(where: { $0.bluetoothIdentifier == id }) else { clearSaved(); return }
        let current = epoch
        session.removeAccessory(accessory) { [weak self] error in
            Task { @MainActor in
                guard let self, self.epoch == current else { return }
                if let error { self.error = error.localizedDescription } else { self.clearSaved() }
            }
        }
    }
    private func clearSaved() {
        UserDefaults.standard.removeObject(forKey: "accessory.relay.id")
        savedRelay = false; name = nil
    }
    func backgrounded() {
        if mode == .setup && (ready || working || peripheral != nil) {
            disconnect(); error = "Wi-Fi setup stopped when the app left the foreground. Check the board, then reconnect."
        }
    }
    private func resetTransport() {
        epoch = UUID()
        timeout?.cancel(); timeout = nil
        finishReply(.failure(CancellationError()))
        relay?.stop(); relay = nil
        security = nil; setupAuthenticated = false; ready = false; requiresReset = false
        rx = nil; tx = nil; activeService = nil; endpoints.removeAll(); networks.removeAll(); streams = 0
    }
    private func fail(_ message: String) {
        finishReply(.failure(AccessoryFailure.invalid(message)))
        disconnect(); error = message; status = "Connection needs attention"
    }
    /// Cancellation means the transport was already reset by whoever cancelled it (the user, a disconnect or
    /// backgrounding), and that path owns the status and message.
    private func report(_ error: Error, hint: String = "") {
        if error is CancellationError { return }
        fail(error.localizedDescription + hint)
    }
    private func armTimeout(_ message: String) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            self?.fail(message)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            retiring.removeAll()
            if let peripheral, peripheral.state == .connected, activeService == nil {
                // Restored by the system while already connected; discovery waits for a powered-on central.
                armTimeout("The restored board did not answer. Reconnect Bluetooth.")
                peripheral.discoverServices([Self.relayService])
            } else {
                if let stale = peripheral, stale.state == .disconnected { peripheral = nil }
                connectKnown()
            }
        case .unknown: break
        case .resetting:
            peripheral = nil; resetTransport()
            status = "Bluetooth is restarting…"
        default:
            peripheral = nil; resetTransport()
            status = central.state == .unauthorized ? "Allow accessory access in Settings." : "Bluetooth is unavailable."
        }
    }
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard relayEnabled, let wantedID,
              let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first(where: { $0.identifier == wantedID }) else { return }
        // Adopt only a live or pending link. Anything else is reconnected normally once the central powers on.
        guard restored.state == .connected || restored.state == .connecting else { return }
        resetTransport()
        mode = .relay; peripheral = restored; restored.delegate = self
        status = "Waiting for your k-chain…"
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard self.peripheral === peripheral else { return }
        reconnectTask?.cancel(); reconnectAttempts = 0
        resetTransport()
        armTimeout("The board did not finish connecting. Confirm the pairing numbers on both devices and try again.")
        peripheral.discoverServices([mode == .relay ? Self.relayService : Self.setupService])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if retiring.remove(peripheral.identifier) != nil, self.peripheral !== peripheral { connectKnown(); return }
        guard self.peripheral === peripheral else { return }
        self.peripheral = nil; resetTransport()
        self.error = error?.localizedDescription ?? "Could not connect to the board."
        if mode == .relay && relayEnabled { scheduleReconnect() }
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if retiring.remove(peripheral.identifier) != nil, self.peripheral !== peripheral { connectKnown(); return }
        guard self.peripheral === peripheral else { return }
        self.peripheral = nil; resetTransport()
        if joinedAddress != nil { status = "Wi-Fi connected"; return }
        status = "Board disconnected"
        if mode == .relay && relayEnabled { scheduleReconnect() }
        else if working { self.error = "The board disconnected during setup. Check its screen before retrying." }
    }
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard self.peripheral === peripheral else { return }
        resetTransport()
        armTimeout("The board changed modes. Choose the matching setup or relay action again.")
        peripheral.discoverServices([mode == .relay ? Self.relayService : Self.setupService])
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard self.peripheral === peripheral else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == (mode == .relay ? Self.relayService : Self.setupService) }) else {
            fail(error?.localizedDescription ?? "The board is in a different mode. Open the matching Bluetooth or Wi-Fi setup screen."); return
        }
        activeService = service
        peripheral.discoverCharacteristics(nil, for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard self.peripheral === peripheral, activeService === service else { return }
        guard error == nil, let characteristics = service.characteristics else { fail("Could not read board services."); return }
        if mode == .relay {
            rx = characteristics.first { $0.uuid == Self.rxID }
            tx = characteristics.first { $0.uuid == Self.txID }
            guard let rx, rx.properties.contains(.writeWithoutResponse), let tx, tx.properties.contains(.notify),
                  let info = characteristics.first(where: { $0.uuid == Self.infoID }) else { fail("Unsupported board relay service."); return }
            peripheral.readValue(for: info)
        } else {
            descriptorsRemaining = characteristics.count
            guard descriptorsRemaining > 0 else { fail("Setup endpoints are missing."); return }
            for characteristic in characteristics { peripheral.discoverDescriptors(for: characteristic) }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral === peripheral, mode == .setup, activeService === characteristic.service else { return }
        guard error == nil, let description = characteristic.descriptors?.first(where: { $0.uuid == CBUUID(string: "2901") }) else {
            endpointFinished(); return
        }
        peripheral.readValue(for: description)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        guard self.peripheral === peripheral, mode == .setup, activeService === descriptor.characteristic?.service else { return }
        if error == nil, let name = descriptor.value as? String, let characteristic = descriptor.characteristic,
           characteristic.properties.contains(.read), characteristic.properties.contains(.write) {
            endpoints[name] = characteristic
        }
        endpointFinished()
    }
    private func endpointFinished() {
        descriptorsRemaining -= 1
        guard descriptorsRemaining == 0 else { return }
        guard ["proto-ver", "prov-session", "prov-config", "prov-scan", "prov-ctrl"].allSatisfy({ endpoints[$0] != nil }) else {
            fail("This firmware does not expose the documented secure setup endpoints."); return
        }
        timeout?.cancel(); ready = true; status = "Enter the Wi-Fi setup code from your board."
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral === peripheral, characteristic === tx else { return }
        guard error == nil, characteristic.isNotifying else { fail(error?.localizedDescription ?? "Bluetooth notifications were rejected."); return }
        timeout?.cancel(); ready = true
        status = "Bluetooth connected. Waiting for board traffic…"
        // Subscription is not evidence that SMP bonding succeeded. Never label this state "Paired".
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral === peripheral, activeService === characteristic.service else { return }
        if characteristic === replyCharacteristic {
            if let error { finishReply(.failure(error)) }
            else if let data = characteristic.value { finishReply(.success(data)) }
            else { finishReply(.failure(AccessoryFailure.invalid("Empty setup response."))) }
            return
        }
        guard mode == .relay else { return }
        if let error { fail(error.localizedDescription); return }
        guard let data = characteristic.value else { fail("Empty Bluetooth response."); return }
        if characteristic.uuid == Self.infoID {
            struct Info: Decodable { let v: Int; let window: Int; let streams: Int; let mtu: Int }
            guard let info = try? JSONDecoder().decode(Info.self, from: data), info.v == 0, info.window == 8192,
                  info.streams == 6, info.mtu == 256, let tx else { fail("Unsupported board relay version."); return }
            relay = PhoneRelay(maximumWrite: peripheral.maximumWriteValueLength(for: .withoutResponse), send: { [weak self] data in
                guard let self, let peripheral = self.peripheral, let rx = self.rx,
                      peripheral.state == .connected, peripheral.canSendWriteWithoutResponse else { return false }
                peripheral.writeValue(data, for: rx, type: .withoutResponse)
                return true
            }, changed: { [weak self] count in
                guard let self, self.streams != count else { return }
                self.streams = count
                self.status = count > 0 ? "Relay connected" : "Waiting for board traffic…"
            }, failed: { [weak self] message in self?.fail(message) })
            peripheral.setNotifyValue(true, for: tx)
        } else if characteristic === tx { relay?.receive(data) }
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard self.peripheral === peripheral else { return }
        relay?.flush()
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral === peripheral, characteristic === replyCharacteristic else { return }
        if let error { finishReply(.failure(error)) } else { peripheral.readValue(for: characteristic) }
    }
    private func finishReply(_ result: Result<Data, Error>) {
        requestTimeout?.cancel(); requestTimeout = nil
        let continuation = reply
        reply = nil; replyCharacteristic = nil
        continuation?.resume(with: result)
    }
    private func request(_ endpoint: String, _ data: Data) async throws -> Data {
        try Task.checkCancellation()
        guard reply == nil, let peripheral, peripheral.state == .connected, let characteristic = endpoints[endpoint],
              data.count <= peripheral.maximumWriteValueLength(for: .withResponse) else {
            throw AccessoryFailure.invalid("The board’s setup connection is unavailable.")
        }
        let current = epoch
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                reply = continuation; replyCharacteristic = characteristic
                requestTimeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                    self?.fail("The board did not answer. Reconnect before retrying setup.")
                }
                peripheral.writeValue(data, for: characteristic, type: .withResponse)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.epoch == current else { return }
                self.disconnect()
            }
        }
    }
    private func secured(_ endpoint: String, _ data: Data) async throws -> Data {
        guard let security, security.authenticated else { throw AccessoryFailure.invalid("Authenticate setup first.") }
        let encrypted = try security.exchange(data)
        return try security.exchange(await request(endpoint, encrypted))
    }
    func authenticate(code: String) async {
        guard mode == .setup, ready, !working else { return }
        working = true; error = nil
        defer { working = false }
        do {
            struct Version: Decodable {
                struct Provisioning: Decodable { let ver: String; let sec_ver: Int; let sec_patch_ver: Int?; let cap: [String] }
                let prov: Provisioning
            }
            let version = try JSONDecoder().decode(Version.self, from: await request("proto-ver", Data([0])))
            guard version.prov.ver == "v1.1", version.prov.sec_ver == 1, (version.prov.sec_patch_ver ?? 0) == 0,
                  !version.prov.cap.contains("no_pop"), !version.prov.cap.contains("no_sec") else {
                throw AccessoryFailure.invalid("This board does not support the required authenticated setup protocol.")
            }
            let security = ProvisioningSecurity()
            let response = try await request("prov-session", security.hello())
            let proof = try security.proof(response: response, code: code)
            try security.verify(await request("prov-session", proof))
            self.security = security; setupAuthenticated = true
            status = "Board verified. Choose its Wi-Fi network."
        } catch { report(error, hint: " Check the current code on the board; repeated wrong codes cause a one-minute pause.") }
    }
    func scan() async {
        guard setupAuthenticated, !working else { return }
        working = true; error = nil
        defer { working = false }
        do {
            _ = try ProvisioningMessages.scanResponse(await secured("prov-scan", Proto.message(0, 10,
                Proto.number(1, 1) + Proto.number(3, 0) + Proto.number(4, 120))), type: 1, field: 11)
            let state = try ProvisioningMessages.scanResponse(await secured("prov-scan", Proto.message(2, 12)), type: 3, field: 13)
            guard try state.number(1) == 1 else { throw AccessoryFailure.invalid("The Wi-Fi scan is still running. Try again.") }
            let count = Int(min(try state.number(2), 16))
            var found: [ProvisioningMessages.Network] = []
            for start in stride(from: 0, to: count, by: 4) {
                let result = try ProvisioningMessages.scanResponse(await secured("prov-scan", Proto.message(4, 14,
                    Proto.number(1, UInt64(start)) + Proto.number(2, UInt64(min(4, count - start))))), type: 5, field: 15)
                for entry in try result.repeated(1) {
                    let item = try Proto(entry)
                    if let ssid = String(data: try item.bytes(1), encoding: .utf8), !ssid.isEmpty, !found.contains(where: { $0.ssid == ssid }) {
                        found.append(.init(ssid: ssid, auth: try item.number(5)))
                    }
                }
            }
            networks = found
        } catch { report(error) }
    }
    func join(ssid: String, password: String) async -> Bool {
        guard setupAuthenticated, !working else { return false }
        working = true; error = nil
        let current = epoch
        defer { working = false }
        do {
            let configuration = try ProvisioningMessages.setNetwork(ssid: ssid, password: password)
            if requiresReset {
                let reset = try Proto(await secured("prov-ctrl", Proto.message(1, 11)))
                guard try reset.number(1) == 2, try reset.number(2) == 0 else { throw AccessoryFailure.invalid("The board could not reset Wi-Fi setup.") }
                requiresReset = false
            }
            _ = try ProvisioningMessages.configResponse(await secured("prov-config", configuration), type: 3, field: 13)
            _ = try ProvisioningMessages.configResponse(await secured("prov-config", Proto.message(4, 14)), type: 5, field: 15)
            status = "Waiting for the board to join Wi-Fi…"
            for _ in 0..<40 {
                try await Task.sleep(for: .milliseconds(1500))
                guard current == epoch else { throw CancellationError() }
                switch try ProvisioningMessages.station(await secured("prov-config", Proto.message(0, 10))) {
                case .connected(let address):
                    joinedAddress = address
                    disconnect()
                    status = "Wi-Fi connected"
                    return true
                case .failed(let message):
                    requiresReset = true; error = message; status = "Check the network details and try again."
                    return false
                case .connecting, .disconnected: continue
                }
            }
            throw AccessoryFailure.invalid("Wi-Fi setup timed out. Check the board before reconnecting.")
        } catch { report(error); return false }
    }
}
