import Foundation
import Testing
@testable import KMobile

struct ConnectionTests {
    @Test(arguments: ["http://desktop.local", "https://user:secret@desktop.local", "https://desktop.local/path",
                      "https://desktop.local?token=secret", "https://desktop.local#ticket=secret", "https://desktop.local:0", "file:///tmp"])
    func rejectsUnsafeOrigins(_ input: String) {
        #expect(throws: GatewayError.self) { try ConnectionProfile.validatedOrigin(input) }
    }

    @Test func normalizesOriginsWithoutChangingCompanionPort() throws {
        #expect(try ConnectionProfile.validatedOrigin(" https://DESKTOP.local:8445/ ").absoluteString == "https://desktop.local:8445")
        #expect(try ConnectionProfile.validatedOrigin("https://DESKTOP.local:443/").absoluteString == "https://desktop.local")
    }

    @Test func certificateCodeMatchesDesktopBase32Contract() {
        let data = Data("certificate".utf8)
        #expect(ServerTrust.code(data) == "APLG-3UEI")
        #expect(ServerTrust.digest(data) == "03d66dd08835c1ca3f128cceacd1f31ac94163096b20f445ae84285bc0832d72")
    }

    @Test func negativeReceiptCannotBecomeSuccess() throws {
        let receipt = try JSONDecoder().decode(GatewayModels.Receipt.self,
            from: Data(#"{"ok":false,"said":"Nothing is playing."}"#.utf8))
        #expect(throws: GatewayError.self) { try receipt.requireSuccess() }
    }

    @Test func unavailableAgentsRemainUnknown() throws {
        let snapshot = try JSONDecoder().decode(GatewayModels.Companion.self,
            from: Data(#"{"seq":41,"phase":"idle","agents":null}"#.utf8))
        #expect(snapshot.agents == nil)
    }

    @Test func missingPermissionCannotDecodeAsFullControl() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GatewayModels.Hello.self,
                from: Data(#"{"device":{"id":"phone","name":"Phone","kind":"phone"}}"#.utf8))
        }
    }
}
