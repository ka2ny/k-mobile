import Foundation

enum GatewayError: LocalizedError {
    case invalidAddress, invalidResponse, missingCredential, certificateMismatch
    case refused(String)
    case http(Int, String)
    case rateLimited(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress: "Enter an HTTPS address without a path, password, query or fragment."
        case .invalidResponse: "The computer sent an unexpected response."
        case .missingCredential: "Pair this connection again. Its credentials are unavailable."
        case .certificateMismatch: "The certificate does not match. Check the address and certificate code on your computer."
        case .refused(let message): message
        case .rateLimited(let seconds, let message): "\(message) Try again after \(seconds) seconds."
        case .http(let code, let message): "\(message) (\(code))"
        }
    }
}
