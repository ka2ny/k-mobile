import Foundation

/// The OS input router accepts a browser key code in a `combo` message for an atomic tap.
enum RemoteKey: String, CaseIterable, Sendable {
    case escape = "Escape", tab = "Tab", delete = "Backspace", enter = "Enter"
    case left = "ArrowLeft", up = "ArrowUp", down = "ArrowDown", right = "ArrowRight"
    var message: [String: String] { ["t": "combo", "c": rawValue] }
}
