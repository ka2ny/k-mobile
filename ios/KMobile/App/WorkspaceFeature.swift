import SwiftUI

enum WorkspaceFeature: String {
    case remote = "Remote", beam = "Beam", agents = "Agents", assistant = "Assistant"
    var icon: MobileGlyph {
        switch self { case .remote: .remote; case .beam: .beam; case .agents: .agents; case .assistant: .assistant }
    }
    var purpose: String {
        switch self {
        case .remote: "View your desktop, hear its audio and control it with touch."
        case .beam: "Send text and files, collect incoming shares and browse your shared folder."
        case .agents: "Follow coding sessions, review changes and answer agent requests."
        case .assistant: "Start tasks, answer questions and continue conversations with your computer."
        }
    }
}
