import Foundation
import CryptoKit
import CommonCrypto

/// ESP-IDF Security 1. One CTR context is deliberately shared by both directions,
/// including the two proofs; restarting either direction would reuse the keystream.
final class ProvisioningSecurity {
    private let privateKey: Curve25519.KeyAgreement.PrivateKey
    init(privateKey: Curve25519.KeyAgreement.PrivateKey = .init()) { self.privateKey = privateKey }
    private var cipher: CCCryptorRef?
    private(set) var authenticated = false
    deinit { if let cipher { CCCryptorRelease(cipher) } }

    func hello() -> Data {
        Proto.number(2, 1) + Proto.bytes(11, Proto.message(0, 20, Proto.bytes(1, privateKey.publicKey.rawRepresentation)))
    }
    func proof(response: Data, code: String) throws -> Data {
        guard cipher == nil, code.count == 6, code.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw AccessoryFailure.invalid("Enter the six-digit Wi-Fi setup code on the board.")
        }
        let message = try session(response, type: 1, field: 21)
        guard try message.number(1) == 0 else { throw AccessoryFailure.invalid("The board rejected the secure session.") }
        let peerBytes = try message.bytes(2), iv = try message.bytes(3)
        guard peerBytes.count == 32, iv.count == 16 else { throw AccessoryFailure.invalid("Invalid board security parameters.") }
        let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerBytes)
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: peer)
        var key = shared.withUnsafeBytes { Array($0) }
        guard key.contains(where: { $0 != 0 }) else { throw AccessoryFailure.invalid("Invalid board public key.") }
        let digest = Array(SHA256.hash(data: Data(code.utf8)))
        for index in key.indices { key[index] ^= digest[index] }
        defer { for index in key.indices { key[index] = 0 } }
        let status = key.withUnsafeBytes { keyPointer in
            iv.withUnsafeBytes { ivPointer in
                CCCryptorCreateWithMode(CCOperation(kCCEncrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding), ivPointer.baseAddress, keyPointer.baseAddress, key.count,
                    nil, 0, 0, CCModeOptions(kCCModeOptionCTR_BE), &cipher)
            }
        }
        guard status == kCCSuccess else { throw AccessoryFailure.invalid("Could not create the secure setup session.") }
        return Proto.number(2, 1) + Proto.bytes(11, Proto.message(2, 22, Proto.bytes(2, try transform(peerBytes))))
    }
    func verify(_ response: Data) throws {
        let message = try session(response, type: 3, field: 23)
        guard try message.number(1) == 0 else { throw AccessoryFailure.invalid("The setup code was rejected. Check the board before retrying.") }
        let proof = try message.bytes(3)
        guard proof.count == 32 else { throw AccessoryFailure.invalid("Invalid board proof.") }
        let clear = try transform(proof)
        let expected = privateKey.publicKey.rawRepresentation
        var difference: UInt8 = 0
        for (left, right) in zip(clear, expected) { difference |= left ^ right }
        guard difference == 0 else { throw AccessoryFailure.invalid("The setup code did not authenticate the board.") }
        authenticated = true
    }
    func exchange(_ data: Data) throws -> Data {
        guard authenticated else { throw AccessoryFailure.invalid("Authenticate the board first.") }
        return try transform(data)
    }
    private func session(_ data: Data, type: UInt64, field: Int) throws -> Proto {
        let outer = try Proto(data)
        guard try outer.number(2) == 1 else { throw AccessoryFailure.invalid("The board requires an unsupported security version.") }
        let inner = try Proto(outer.bytes(11))
        guard try inner.number(1) == type else { throw AccessoryFailure.invalid("Unexpected security response.") }
        return try Proto(inner.bytes(field))
    }
    private func transform(_ data: Data) throws -> Data {
        guard let cipher else { throw AccessoryFailure.invalid("The secure setup session is unavailable.") }
        var output = Data(count: data.count + kCCBlockSizeAES128)
        let capacity = output.count
        var moved = 0
        let status = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                CCCryptorUpdate(cipher, input.baseAddress, data.count, out.baseAddress, capacity, &moved)
            }
        }
        guard status == kCCSuccess, moved == data.count else { throw AccessoryFailure.invalid("Secure setup failed.") }
        output.count = moved
        return output
    }
}
