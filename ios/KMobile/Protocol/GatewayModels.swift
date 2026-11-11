import Foundation

enum GatewayModels {
    struct Device: Codable, Equatable, Sendable {
        let id: String
        let name: String
        let control: String
        let kind: String
        let fp: String?
    }
    struct Pair: Decodable, Sendable {
        let token: String
        let device: Device
    }
    struct Hello: Decodable, Sendable {
        let device: Device
        let companion_link: Int?
        var supportsPhoneAssociation: Bool { device.kind == "phone" && companion_link == 1 }
    }
    struct Board: Decodable, Identifiable, Sendable { let id: String; let name: String }
    struct BoardLink: Decodable, Identifiable, Sendable {
        let board: Board
        let at: Double?
        let grants: [String]
        var id: String { board.id }
    }
    struct BoardLinks: Decodable, Sendable {
        let version: Int
        let links: [BoardLink]
        func validated() throws -> [BoardLink] {
            guard version == 1, links.allSatisfy({ $0.grants.isEmpty && !$0.board.id.isEmpty }),
                  Set(links.map(\.id)).count == links.count else { throw GatewayError.invalidResponse }
            return links
        }
    }
    struct Linked: Decodable, Sendable {
        let ok: Bool; let state: String; let already: Bool; let grants: [String]; let board: Board
        func requireAssociation() throws {
            guard ok, state == "linked", grants.isEmpty, !board.id.isEmpty else { throw GatewayError.invalidResponse }
        }
    }
    struct Unlinked: Decodable, Sendable { let ok: Bool; let state: String }
    struct Hub: Decodable, Sendable {
        let paired: Bool
        let stopped: Bool
        let remote: Bool
        let beam: Bool
        let agents: Bool
        let control: String
    }
    struct Receipt: Decodable, Sendable {
        let ok: Bool
        let said: String?
        let note: String?
        let error: String?
        func requireSuccess() throws {
            guard ok else { throw GatewayError.refused(error ?? note ?? said ?? "The computer declined the action.") }
        }
    }
    struct Failure: Decodable { let error: String?; let retry_after: Int? }
    struct Companion: Decodable, Equatable, Sendable {
        let seq: Int
        let phase: String?
        let line: String?
        let answer: String?
        let agents: Agents?
        struct Agents: Decodable, Equatable, Sendable {
            let needs: Int
            let working: Int
            let top: Decision?
        }
        struct Decision: Decodable, Equatable, Identifiable, Sendable {
            let id: String
            let name: String
            let engine: String?
            let tool: String?
            let summary: String?
            let decision: String
            var identity: String { id + ":" + decision }
        }
    }
    struct Assistant: Decodable, Sendable {
        let now: Job
        struct Job: Decodable, Sendable {
            let running: Bool
            let goal: String?
            let confirm: Prompt?
            let question: Prompt?
            let paused: Pause?
            struct Prompt: Decodable, Sendable { let id: String; let label: String?; let text: String? }
            struct Pause: Decodable, Sendable { let id: String? }
            var needsDesktop: Bool { confirm != nil || question != nil || paused != nil }
        }
    }
}
