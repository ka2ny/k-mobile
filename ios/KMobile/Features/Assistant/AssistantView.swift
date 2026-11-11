import SwiftUI

struct AssistantView: View {
    let isActive: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var goal = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.inset) {
                PageHeading(title: "Assistant", detail: "Start a task. Review its progress on your computer.")
                if !model.canUseAssistant && model.selected != nil && !model.online && model.refreshing
                    && model.connectionError == nil
                {
                    ProgressView("Connecting to your computer…").frame(maxWidth: .infinity).padding(Design.inset)
                } else if !model.canUseAssistant {
                    QuietEmptyState(title: blocker.title, detail: blocker.detail, icon: .assistant)
                } else if let job = model.assistant?.now {
                    if job.running {
                        VStack(alignment: .leading, spacing: Design.gap) {
                            MobileLabel(
                                job.needsDesktop ? "Waiting for you" : "Working on your computer", icon: .assistant
                            )
                            .font(.headline)
                            Text(job.goal ?? "Current task").font(.title3)
                            if job.needsDesktop {
                                Text(
                                    "Continue this conversation or approve the next step in the Assistant window on your computer."
                                )
                                .foregroundStyle(Design.muted)
                                Button("Show on computer", systemImage: "desktopcomputer") {
                                    Task { _ = await model.assistantAction("show") }
                                }.buttonStyle(QuietSecondaryStyle())
                            }
                            Button("Stop task", systemImage: "stop.circle", role: .destructive) {
                                Task { _ = await model.assistantAction("stop") }
                            }.buttonStyle(QuietSecondaryStyle())
                        }.quietCard().disabled(model.interacting)
                    } else {
                        composer
                    }
                } else if model.assistantError == nil {
                    ProgressView("Checking Assistant…").frame(maxWidth: .infinity).padding(Design.inset)
                }
                if let error = model.assistantError {
                    QuietEmptyState(title: "Assistant is unavailable", detail: error, icon: .assistant)
                    Button("Try again", systemImage: "arrow.clockwise") { Task { await model.refreshAssistant() } }
                        .buttonStyle(QuietSecondaryStyle())
                }
                Label("Approvals stay on your computer", systemImage: "lock.shield")
                    .font(.subheadline).foregroundStyle(Design.muted)
                if let receipt = model.lastReceipt, model.receiptContext == "assistant" {
                    Text(receipt).font(.callout).foregroundStyle(Design.muted)
                }
            }.quietPage().quietEntrance()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Design.background)
        .navigationTitle("Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refreshAssistant() }
        .onChange(of: model.selectedID) { goal = "" }
        .task(id: "\(model.selectedID?.uuidString ?? "none")-\(model.canUseAssistant)-\(scenePhase)-\(isActive)") {
            guard isActive, scenePhase == .active, model.canUseAssistant else { return }
            while !Task.isCancelled {
                await model.refreshAssistant()
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }

    /// Names the one thing standing between this device and Assistant, in the order a person would fix it.
    private var blocker: (title: String, detail: String) {
        guard let selected = model.selected else {
            return ("Connect to your computer", "Add a Computer connection to hand tasks to your desktop Assistant.")
        }
        if selected.kind != .computer {
            return (
                "Assistant needs a Computer connection",
                "The k-chain desktop service carries controls only. Choose a Computer connection in Connections."
            )
        }
        if !model.online {
            return ("Your computer is out of reach", "Keep your computer awake and on a network this device can reach.")
        }
        if model.hub?.stopped == true {
            return (
                "Paused on your computer", "Remote services are paused. Resume them on your computer to use Assistant."
            )
        }
        return ("Full control needed", "Approve full control for this device on your computer. You can ask from Home.")
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: Design.gap) {
            Text("New task").font(.title2.weight(.medium))
            TextField("Describe a task for your computer…", text: $goal, axis: .vertical)
                .lineLimit(4...10)
                .padding(Design.gap)
                .background(Design.background, in: .rect(cornerRadius: Design.controlRadius))
                .accessibilityLabel("Task for your computer")
            Text("Your default desktop Assistant will handle this task.")
                .font(.callout).foregroundStyle(Design.muted)
            Button("Send to computer", systemImage: "arrow.up") {
                Task {
                    if await model.assistantAction("start", text: goal.trimmingCharacters(in: .whitespacesAndNewlines))
                    {
                        goal = ""
                    }
                }
            }
            .buttonStyle(QuietProminentStyle())
            .disabled(model.interacting || goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.quietCard().disabled(model.interacting)
    }
}
