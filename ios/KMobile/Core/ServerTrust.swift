import CryptoKit
import Foundation
import Security

/// Computer connections use system TLS trust. Companion connections use the code
/// read from the desktop once, then retain the complete certificate digest.
final class ServerTrust: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let origin: URL
    private let pin: String?
    private let enrollmentCode: String?
    private let lock = NSLock()
    private var observedDigest: String?
    private var rejectedCertificate = false
    var certificateDigest: String? { lock.withLock { observedDigest } }
    var didRejectCertificate: Bool { lock.withLock { rejectedCertificate } }
    var pinnedDigest: String? { pin }

    init(origin: URL, pin: String? = nil, enrollmentCode: String? = nil) {
        self.origin = origin
        self.pin = pin
        self.enrollmentCode = enrollmentCode
    }

    static func digest(_ certificate: Data) -> String {
        SHA256.hash(data: certificate).map { String($0, radix: 16).leftPadded }.joined()
    }

    static func code(_ certificate: Data) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        let bytes = Array(SHA256.hash(data: certificate).prefix(5))
        let bits = bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let chars = (0..<8).map { alphabet[Int((bits >> (35 - $0 * 5)) & 31)] }
        return String(chars.prefix(4)) + "-" + String(chars.suffix(4))
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let host = origin.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard challenge.protectionSpace.host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]")) == host,
              challenge.protectionSpace.port == (origin.port ?? 443) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        guard pin != nil || enrollmentCode != nil else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let data = SecCertificateCopyData(leaf) as Data
        let digest = Self.digest(data)
        let matches = pin.map { $0 == digest } ?? (enrollmentCode == Self.code(data))
        guard matches else {
            lock.withLock { rejectedCertificate = true }
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        lock.withLock { observedDigest = digest }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    // Never forward tokens, PINs or gateway cookies through an HTTP redirect.
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private extension String {
    var leftPadded: String { count == 1 ? "0" + self : self }
}
