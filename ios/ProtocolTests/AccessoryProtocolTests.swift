import Foundation
import Testing
@testable import KMobileProtocol

struct AccessoryProtocolTests {
    @Test func publishedRelayFrames() throws {
        let open = try RelayFrame(Data([1, 9]) + Data("192.0.2.10:8445 100.64.0.7:8445".utf8))
        #expect(open.stream == 9)
        #expect(try RelayTarget.parse(open.payload) == [.init(host: "192.0.2.10", port: 8445), .init(host: "100.64.0.7", port: 8445)])
        let tlsBytes = Data([3, 9, 0x16, 0x03, 0x01, 0x00, 0xf1])
        #expect(try RelayFrame(tlsBytes).encoded == tlsBytes)
        #expect(try RelayFrame(Data([5, 9, 0, 8])).credit == 2048)
        #expect(try RelayFrame(Data([4, 9])).payload.isEmpty)
    }
    @Test(arguments: [Data(), Data([1]), Data([0x20, 1]), Data([5, 1, 0]), Data([4, 1, 1]), Data([3, 1]), Data([2, 1, 0, 1]), Data([6, 1, 65]), Data(repeating: 3, count: 254)])
    func rejectsMalformedFrames(_ data: Data) { #expect(throws: AccessoryFailure.self) { try RelayFrame(data) } }

    @Test(arguments: ["", "http://a:8445", "a:8445", "127.0.0.1:8445", "169.254.169.254:80", "1.2.3.256:80", "192.0.2.1:0", "192.0.2.1:65536", "192.0.2.1:80 ", "192.0.2.1:80\n", "0.0.0.0:80", "224.0.0.1:80"])
    func rejectsUnsafeTargets(_ target: String) { #expect(throws: AccessoryFailure.self) { try RelayTarget.parse(Data(target.utf8)) } }

    @Test func boundedCredits() throws {
        var window = RelayWindow()
        #expect(throws: AccessoryFailure.self) { try window.grant(1) }
        try window.consume(8192)
        #expect(window.available == 0)
        #expect(throws: AccessoryFailure.self) { try window.consume(1) }
        try window.grant(2048)
        try window.consume(250)
        #expect(window.available == 1798)
        #expect(throws: AccessoryFailure.self) { try window.grant(65535) }
        #expect(throws: AccessoryFailure.self) { try window.consume(-1) }
    }
    @Test func canonicalSetConfig() throws {
        // ESP-IDF v5.5.5: msg=2; field12 CmdSetConfig; SSID field1, password field2.
        #expect(try ProvisioningMessages.setNetwork(ssid: "AP", password: "password") == Data([
            0x08, 0x02, 0x62, 0x0e, 0x0a, 0x02, 0x41, 0x50, 0x12, 0x08,
            0x70, 0x61, 0x73, 0x73, 0x77, 0x6f, 0x72, 0x64]))
    }
    @Test func connectedRequiresAddress() throws {
        #expect(throws: AccessoryFailure.self) { try ProvisioningMessages.station(Data([8, 1, 90, 0])) }
        #expect(try ProvisioningMessages.station(Data([8, 1, 90, 2, 16, 1])) == .connecting)
        #expect(try ProvisioningMessages.station(Data([8, 1, 90, 4, 16, 3, 80, 1])) == .failed("Network not found. Check its name and range."))
        let connected = Data([8, 1, 90, 11, 90, 9, 10, 7]) + Data("1.2.3.4".utf8)
        #expect(try ProvisioningMessages.station(connected) == .connected("1.2.3.4"))
    }
    @Test(arguments: [Data([0]), Data([10, 4, 1]), Data([8, 128]), Data([8] + Array(repeating: 255, count: 10)), Data([9, 0]), Data(repeating: 0, count: 16385)])
    func rejectsMalformedProtobuf(_ data: Data) { #expect(throws: AccessoryFailure.self) { try Proto(data) } }

    @Test func rejectsDuplicateAndWrongType() throws {
        let duplicate = try Proto(Data([8, 1, 8, 1]))
        #expect(throws: AccessoryFailure.self) { try duplicate.number(1) }
        let wrongType = try Proto(Data([10, 0]))
        #expect(throws: AccessoryFailure.self) { try wrongType.number(1) }
    }
    @Test func multibyteSSIDBoundedByBytes() throws {
        #expect(throws: AccessoryFailure.self) { try ProvisioningMessages.setNetwork(ssid: String(repeating: "é", count: 17), password: "password") }
        #expect(throws: AccessoryFailure.self) { try ProvisioningMessages.setNetwork(ssid: "AP", password: "p\0ss") }
    }
    @Test func deterministicMalformedInputSweep() {
        // Every byte value at each of the first three positions. Parsing must not trap.
        for byte in UInt8.min...UInt8.max {
            for data in [Data([byte]), Data([10, byte, 0]), Data([8, 128, byte])] {
                _ = try? Proto(data)
                _ = try? RelayFrame(data)
            }
        }
    }
}
