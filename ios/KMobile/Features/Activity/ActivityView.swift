import SwiftUI

struct ActivityView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.activity.isEmpty {
                ContentUnavailableView("A quiet start", systemImage: "clock", description: Text("Responses to actions you take in this app appear here. Activity lasts for this app session."))
            } else {
                List(model.activity) { entry in
                    HStack(alignment: .top, spacing: Design.gap) {
                        Image(systemName: entry.failed ? "exclamationmark.circle" : "checkmark.circle")
                            .foregroundStyle(entry.failed ? Color.red : Design.accent)
                            .accessibilityLabel(entry.failed ? "Failed" : "Accepted")
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.title).font(.headline)
                            Text(entry.detail).foregroundStyle(.secondary).textSelection(.enabled)
                            Text(entry.date, format: .dateTime.hour().minute()).font(.footnote).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                }.scrollContentBackground(.hidden)
            }
        }
        .background(Design.background)
        .navigationTitle("Activity")
    }
}
