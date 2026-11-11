import Foundation

struct ActivityEntry: Identifiable {
    let id = UUID()
    let date = Date.now
    let title: String
    let detail: String
    let failed: Bool
}
