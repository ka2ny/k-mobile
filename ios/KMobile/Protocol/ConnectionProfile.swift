import Foundation

struct ConnectionProfile: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case computer, companion
        var id: Self { self }
        var title: String { self == .computer ? "Computer" : "k-chain desktop service" }
    }

    let id: UUID
    let name: String
    let origin: URL
    let kind: Kind

    static func validatedOrigin(_ input: String) throws -> URL {
        guard var parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              parts.port == nil || (1...65535).contains(parts.port ?? 0) else {
            throw GatewayError.invalidAddress
        }
        parts.scheme = "https"
        parts.host = host.lowercased()
        if parts.port == 443 { parts.port = nil }
        parts.path = ""
        guard let url = parts.url else { throw GatewayError.invalidAddress }
        return url
    }
}
