import Foundation

struct AssistantMemory {
    struct Entry: Identifiable {
        let id = UUID()
        let title: String
        let body: String
        let detail: String
    }
    let facts: [Entry]
    let howTo: [Entry]
    let lessons: [Entry]
    var isEmpty: Bool { facts.isEmpty && howTo.isEmpty && lessons.isEmpty }

    init(_ value: JSONValue) {
        facts = (value["facts"]?.array ?? []).compactMap { fact in
            guard let text = fact["text"]?.string else { return nil }
            let detail = [fact["pinned"]?.bool == true ? "Pinned" : nil,
                          fact["locked"]?.bool == true ? "Locked" : nil].compactMap { $0 }.joined(separator: " · ")
            return Entry(title: text, body: "", detail: detail)
        }
        let notes = value["notes"]?.array ?? []
        func entries(_ kind: String) -> [Entry] {
            notes.compactMap { note in
                guard note["kind"]?.string == kind, let title = note["title"]?.string else { return nil }
                let used = note["used"]?.int ?? 0
                return Entry(title: title, body: note["body"]?.string ?? "",
                             detail: used == 0 ? "Not used yet" : used == 1 ? "Used once" : "Used \(used) times")
            }
        }
        howTo = entries("howto"); lessons = entries("lesson")
    }
}
