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

    /// Accepts the desktop's `XXXX-XXXX` code typed with or without its dash, spaces or capitals.
    static func normalizedCertificateCode(_ input: String) -> String? {
        let characters = input.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard characters.count == 8, characters.allSatisfy({ ("A"..."Z").contains($0) || ("2"..."7").contains($0) }) else { return nil }
        return String(characters.prefix(4)) + "-" + String(characters.suffix(4))
    }

    static func validatedOrigin(_ input: String) throws -> URL {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // A bare host is the common way to type an address. Only HTTPS is ever assumed; explicit schemes are checked below.
        if !text.isEmpty, !text.contains("://") { text = "https://" + text }
        guard var parts = URLComponents(string: text),
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
