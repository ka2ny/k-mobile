import SwiftUI

struct AssistantMemoryView: View {
    let assistant: AssistantModel
    @State private var persona: String
    @Environment(\.dismiss) private var dismiss
    init(assistant: AssistantModel, persona: String) {
        self.assistant = assistant; _persona = State(initialValue: persona)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Design.inset) {
                    PageHeading(title: "What it remembers", detail: "Knowledge your Assistant carries between tasks.")
                    if assistant.assistants.count > 1 {
                        Picker("Assistant", selection: $persona) {
                            ForEach(assistant.assistants) { Text($0.name).tag($0.id) }
                        }.pickerStyle(.menu)
                    }
                    if assistant.busy.contains(.memory) { ProgressView("Reading memory…") }
                    if let note = assistant.notes[.memory] {
                        Text(note.text).foregroundStyle(Design.caution)
                        Button("Try again") { Task { await assistant.loadMemory(persona) } }.buttonStyle(QuietSecondaryStyle())
                    }
                    if let memory = assistant.memory {
                        if memory.isEmpty {
                            ContentUnavailableView("No memories yet", systemImage: "brain", description: Text("What your Assistant learns from tasks will appear here."))
                        }
                        entries("Things it knows", memory.facts)
                        entries("How-to notes", memory.howTo)
                        entries("Lessons", memory.lessons)
                    }
                    Text("Manage pinned, locked and forgotten memories in Assistant on your computer.")
                        .font(.footnote).foregroundStyle(Design.muted)
                }.quietPage()
            }.background(Design.background)
                .navigationTitle(assistant.name(of: persona)).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .task(id: persona) { await assistant.loadMemory(persona) }
                .refreshable { await assistant.loadMemory(persona) }
        }
    }

    @ViewBuilder private func entries(_ title: String, _ items: [AssistantMemory.Entry]) -> some View {
        if !items.isEmpty {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title).font(.body.weight(.medium))
                    if !item.body.isEmpty { Text(item.body).font(.callout) }
                    if !item.detail.isEmpty { Text(item.detail).font(.footnote).foregroundStyle(Design.muted) }
                }.textSelection(.enabled).quietCard()
            }
        }
    }
}
