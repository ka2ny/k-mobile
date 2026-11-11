import Foundation

enum ProvisioningMessages {
    struct Network: Identifiable {
        let ssid: String
        let auth: UInt64
        var id: String { ssid }
        var supported: Bool { [0, 2, 3, 4, 6, 7].contains(auth) }
    }
    enum Station: Equatable { case connected(String), connecting, disconnected, failed(String) }
    static func setNetwork(ssid: String, password: String) throws -> Data {
        let ssidData = Data(ssid.utf8), passwordData = Data(password.utf8)
        guard (1...32).contains(ssidData.count), passwordData.count <= 64,
              !ssid.contains("\0"), !password.contains("\0") else { throw AccessoryFailure.invalid("Check the network name and password lengths.") }
        return Proto.message(2, 12, Proto.bytes(1, ssidData) + Proto.bytes(2, passwordData))
    }
    static func configResponse(_ data: Data, type: UInt64, field: Int) throws -> Proto {
        let envelope = try Proto(data)
        guard try envelope.number(1) == type else { throw AccessoryFailure.invalid("Unexpected setup response.") }
        let response = try Proto(envelope.bytes(field))
        guard try response.number(1) == 0 else { throw AccessoryFailure.invalid("The board declined the Wi-Fi configuration.") }
        return response
    }
    static func station(_ data: Data) throws -> Station {
        let response = try configResponse(data, type: 1, field: 11)
        switch try response.number(2) {
        case 0:
            let joined = try Proto(response.bytes(11))
            guard let address = String(data: try joined.bytes(1), encoding: .utf8), !address.isEmpty else {
                throw AccessoryFailure.invalid("The board did not report a network address.")
            }
            return .connected(address)
        case 1: return .connecting
        case 2: return .disconnected
        case 3: return .failed(try response.number(10) == 1 ? "Network not found. Check its name and range." : "The network rejected the password.")
        default: throw AccessoryFailure.invalid("Unknown Wi-Fi state.")
        }
    }
    static func scanResponse(_ data: Data, type: UInt64, field: Int) throws -> Proto {
        let envelope = try Proto(data)
        guard try envelope.number(1) == type, try envelope.number(2) == 0 else { throw AccessoryFailure.invalid("The Wi-Fi scan failed.") }
        return try Proto(envelope.bytes(field))
    }
}
