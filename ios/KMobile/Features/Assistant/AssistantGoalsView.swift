import SwiftUI

struct AssistantGoalsView: View {
    let assistant: AssistantModel
    var body: some View {
        VStack(alignment: .leading, spacing: Design.gap) {
            Text("Ongoing goals").font(.title2.weight(.medium)).accessibilityAddTraits(.isHeader)
            Text("Scheduled work your Assistant checks in on. Manage goals and answer requests on your computer.")
                .font(.callout).foregroundStyle(Design.muted)
            ForEach(assistant.goals) { goal in
                VStack(alignment: .leading, spacing: 10) {
                    Text(goal.title).font(.headline)
                    Text("\(assistant.name(of: goal.assistant)) · \(goal.status)").font(.subheadline).foregroundStyle(Design.muted)
                    if !goal.progress.isEmpty { Text(goal.progress).font(.callout) }
                    if goal.needs > 0 {
                        Label(goal.needs == 1 ? "1 thing needs you at the computer" : "\(goal.needs) things need you at the computer", systemImage: "hand.raised")
                            .font(.callout).foregroundStyle(Design.caution)
                    }
                    if !goal.next.isEmpty { Text("Next: \(goal.next)").font(.callout) }
                    if goal.state == "active", !goal.cadence.isEmpty { Text(goal.cadence).font(.footnote).foregroundStyle(Design.muted) }
                    if goal.state == "active", goal.nextDue > 0 {
                        LabeledContent("Next check-in") { Text(Date(timeIntervalSince1970: goal.nextDue), style: .relative) }.font(.footnote)
                    }
                    if goal.lastRun > 0 {
                        LabeledContent("Last check-in") { Text(Date(timeIntervalSince1970: goal.lastRun), style: .relative) }.font(.footnote)
                    }
                }.textSelection(.enabled).quietCard()
            }
            NavigationLink { RemoteStreamView() } label: { MobileLabel("Open Remote", icon: .remote) }
                .buttonStyle(QuietSecondaryStyle())
        }
    }
}
