import Foundation
import Testing
@testable import KMobileProtocol

struct GatewayContractTests {
    @Test func phoneAssociationRequiresExactCapabilityAndPhoneIdentity() throws {
        for (kind, version, supported) in [("phone", "1", true), ("phone", "2", false), ("phone", "null", false), ("companion", "1", false)] {
            let json = """
            {"device":{"id":"synthetic-phone","name":"Test","control":"view","kind":"\(kind)"},"companion_link":\(version)}
            """
            let hello = try JSONDecoder().decode(GatewayModels.Hello.self, from: Data(json.utf8))
            #expect(hello.supportsPhoneAssociation == supported)
        }
    }
    @Test func linkingIsAnAssociationWithNoGrants() throws {
        let linked = try JSONDecoder().decode(GatewayModels.Linked.self, from: Data(#"{"ok":true,"state":"linked","already":false,"grants":[],"board":{"id":"synthetic-board","name":"Test board"}}"#.utf8))
        try linked.requireAssociation()
        #expect(linked.board.id == "synthetic-board")
        let refused = try JSONDecoder().decode(GatewayModels.Linked.self, from: Data(#"{"ok":false,"state":"linked","already":false,"grants":[],"board":{"id":"synthetic-board","name":"Test board"}}"#.utf8))
        #expect(throws: GatewayError.self) { try refused.requireAssociation() }
    }
    @Test(arguments: [
        #"{"version":2,"links":[]}"#,
        #"{"version":1,"links":[{"board":{"id":"board","name":"Test"},"at":null,"grants":["control"]}]}"#,
        #"{"version":1,"links":[{"board":{"id":"","name":"Test"},"at":null,"grants":[]}]}"#,
        #"{"version":1,"links":[{"board":{"id":"board","name":"Test"},"grants":[]},{"board":{"id":"board","name":"Test"},"grants":[]}]}"#
    ])
    func rejectsUnrecognizedAssociationSchema(_ json: String) throws {
        let response = try JSONDecoder().decode(GatewayModels.BoardLinks.self, from: Data(json.utf8))
        #expect(throws: GatewayError.self) { try response.validated() }
    }
    @Test func validatesEmptyAndRevokedList() throws {
        let empty = try JSONDecoder().decode(GatewayModels.BoardLinks.self, from: Data(#"{"version":1,"links":[]}"#.utf8))
        #expect(try empty.validated().isEmpty)
    }
    @Test(arguments: ["http://desktop.local", "https://user:secret@desktop.local", "https://desktop.local/path",
                      "https://desktop.local?token=secret", "https://desktop.local#ticket=secret", "https://desktop.local:0", "file:///tmp"])
    func rejectsUnsafeOrigins(_ input: String) { #expect(throws: GatewayError.self) { try ConnectionProfile.validatedOrigin(input) } }

    @Test func originNormalization() throws {
        #expect(try ConnectionProfile.validatedOrigin(" https://DESKTOP.local:8445/ ").absoluteString == "https://desktop.local:8445")
        #expect(try ConnectionProfile.validatedOrigin("https://DESKTOP.local:443/").absoluteString == "https://desktop.local")
    }
    @Test func bareHostsAssumeHTTPSOnly() throws {
        #expect(try ConnectionProfile.validatedOrigin("Studio.local").absoluteString == "https://studio.local")
        #expect(try ConnectionProfile.validatedOrigin(" desktop.local:8445 ").absoluteString == "https://desktop.local:8445")
        for input in ["", "   ", "desktop.local/path", "user:secret@desktop.local", "desktop.local?token=secret", "ftp://desktop.local", "mailto:desktop.local"] {
            #expect(throws: GatewayError.self) { try ConnectionProfile.validatedOrigin(input) }
        }
    }
    @Test func certificateCodeNormalization() {
        #expect(ConnectionProfile.normalizedCertificateCode(" aplg 3uei ") == "APLG-3UEI")
        #expect(ConnectionProfile.normalizedCertificateCode("APLG-3UEI") == "APLG-3UEI")
        for input in ["", "APLG-3UE", "APLG-3UEI2", "APLG-3UE1", "APLG_3UEI", "ÀPLG-3UEI"] {
            #expect(ConnectionProfile.normalizedCertificateCode(input) == nil)
        }
    }
    @Test func missingControlFailsClosed() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GatewayModels.Hello.self, from: Data(#"{"device":{"id":"phone","name":"Phone","kind":"phone"}}"#.utf8))
        }
    }
    @Test func declinedCommandCannotBecomeSuccess() throws {
        let receipt = try JSONDecoder().decode(GatewayModels.Receipt.self, from: Data(#"{"ok":false,"said":"Nothing is playing."}"#.utf8))
        #expect(throws: GatewayError.self) { try receipt.requireSuccess() }
    }
}
