import Testing
@testable import KMobileProtocol

struct RemoteKeyTests {
    @Test func keyboardUsesOSAtomicTapContract() {
        #expect(RemoteKey.enter.message == ["t": "combo", "c": "Enter"])
        #expect(RemoteKey.delete.message["c"] == "Backspace")
        #expect(RemoteKey.left.message["c"] == "ArrowLeft")
        #expect(RemoteKey.allCases.allSatisfy { $0.message["k"] == nil && $0.message["t"] == "combo" })
    }
}
