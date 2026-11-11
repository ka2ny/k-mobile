import SwiftUI

struct ActivityView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.activity.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: Design.inset) {
                        PageHeading(title: "Activity", detail: "Responses from your computer.")
                        QuietEmptyState(
                            title: "No actions yet",
                            detail:
                                "Responses to actions you take in this app appear here. Activity lasts for this app session.",
                            icon: .activity)
                    }.quietPage()
                }
            } else {
                List(model.activity) { entry in
                    HStack(alignment: .top, spacing: Design.gap) {
                        Image(systemName: entry.failed ? "exclamationmark.circle" : "checkmark.circle")
                            .foregroundStyle(entry.failed ? Design.danger : Design.success)
                            .accessibilityLabel(entry.failed ? "Failed" : "Accepted")
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.title).font(.headline)
                            Text(entry.detail).foregroundStyle(Design.muted).textSelection(.enabled)
                            Text(entry.date, format: .dateTime.hour().minute()).font(.footnote).foregroundStyle(
                                Design.muted)
                        }
                    }.padding(.vertical, 8).listRowBackground(Design.surface)
                }.quietList()
            }
        }
        .background(Design.background)
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
    }
}
