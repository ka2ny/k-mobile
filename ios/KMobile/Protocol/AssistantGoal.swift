import Foundation

/// Standing goals are read-only on the phone; management stays in the desktop Assistant.
struct AssistantGoal: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let assistant: String
    let state: String
    let why: String
    let cadence: String
    let progress: String
    let next: String
    let needs: Int
    let nextDue: Double
    let lastRun: Double

    init?(_ value: JSONValue) {
        guard let id = value["id"]?.string,
              id.range(of: #"^g[0-9a-f]{10}$"#, options: .regularExpression) != nil else { return nil }
        self.id = id
        title = value["title"]?.string ?? value["goal"]?.string ?? "Goal"
        assistant = value["assistant"]?.string ?? "assistant"
        let supplied = value["state"]?.string ?? "paused"
        state = ["active", "paused", "reached", "stopped"].contains(supplied) ? supplied : "paused"
        why = value["why"]?.string ?? ""
        cadence = value["every"]?.string ?? ""
        progress = value["progress"]?.string ?? ""
        next = value["next"]?.string ?? ""
        needs = max(0, value["needs"]?.int ?? 0)
        nextDue = max(0, value["next_due"]?.number ?? 0)
        lastRun = max(0, value["last_run"]?.number ?? 0)
    }

    var status: String {
        switch state {
        case "active": "Active"
        case "reached": "Reached"
        case "stopped": "Stopped"
        default: why == "failed" ? "Paused after three failed tries" : why == "budget" ? "Paused — monthly budget reached" : "Paused"
        }
    }
}
