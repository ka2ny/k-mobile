import SwiftUI

struct AssistantView: View {
    let isActive: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var goal = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.inset) {
                Text("A thought here.\nA little progress there.")
                    .font(.largeTitle).bold().tracking(-1)
                Text("Give your computer something to work on.")
                    .foregroundStyle(.secondary)
                if !model.canUseAssistant {
                    ContentUnavailableView("Connect to your computer", systemImage: "sparkle", description: Text("Assistant needs a Computer connection with full control, and remote services must be running."))
                } else if let job = model.assistant?.now {
                    if job.running {
                        VStack(alignment: .leading, spacing: Design.gap) {
                            Label(job.needsDesktop ? "Waiting for you" : "Working on your computer", systemImage: job.needsDesktop ? "hand.raised" : "sparkle")
                                .font(.headline)
                            Text(job.goal ?? "Current task").font(.title3)
                            if job.needsDesktop {
                                Text("Continue this conversation or approve the next step in the Assistant window on your computer.")
                                    .foregroundStyle(.secondary)
                                Button("Show on computer", systemImage: "desktopcomputer") {
                                    Task { _ = await model.assistantAction("show") }
                                }.buttonStyle(.bordered).controlSize(.large)
                            }
                            Button("Stop task", systemImage: "stop.circle", role: .destructive) {
                                Task { _ = await model.assistantAction("stop") }
                            }.buttonStyle(.bordered).controlSize(.large)
                        }.quietCard().disabled(model.interacting)
                    } else {
                        composer
                    }
                } else if model.assistantError == nil {
                    ProgressView("Checking Assistant…").frame(maxWidth: .infinity).padding(Design.inset)
                }
                if let error = model.assistantError {
                    ContentUnavailableView("Assistant is unavailable", systemImage: "exclamationmark.bubble", description: Text(error))
                    Button("Try again", systemImage: "arrow.clockwise") { Task { await model.refreshAssistant() } }
                        .buttonStyle(.bordered).controlSize(.large)
                }
                Label("Approvals stay on your computer", systemImage: "lock.shield")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let receipt = model.lastReceipt {
                    Text(receipt).font(.callout).foregroundStyle(.secondary)
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

    private var composer: some View {
        VStack(alignment: .leading, spacing: Design.gap) {
            Text("What’s on your mind?").font(.title2).bold()
            TextField("Describe a task for your computer…", text: $goal, axis: .vertical)
                .lineLimit(4...10)
                .padding(Design.gap)
                .background(Design.background, in: .rect(cornerRadius: 16))
                .accessibilityLabel("Task for your computer")
            Text("Your default desktop Assistant will handle this task.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Send to computer", systemImage: "arrow.up") {
                Task {
                    if await model.assistantAction("start", text: goal.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        goal = ""
                    }
                }
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(model.interacting || goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.quietCard()
    }
}
