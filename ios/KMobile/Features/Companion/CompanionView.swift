import SwiftUI

struct CompanionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var confirmLock = false
    @State private var decision: GatewayModels.Companion.Decision?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.inset) {
                Text("A small gesture.\nA little more flow.")
                    .font(.largeTitle).bold().tracking(-1)
                Text("The same desktop companion service your k-chain uses.")
                    .foregroundStyle(.secondary)
                if !model.online {
                    ContentUnavailableView("Your companion is out of reach", systemImage: "wave.3.right.circle", description: Text("Select a connection and keep your computer awake."))
                } else {
                    if let error = model.companionError {
                        Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                    }
                    if model.device?.control != "full" {
                        Label("Full control needs approval on your computer.", systemImage: "hand.raised")
                            .foregroundStyle(.secondary)
                    }
                    controls
                    if model.hub?.stopped == true { Label("Controls paused on your computer", systemImage: "pause.circle") }
                    if model.busy { ProgressView("Waiting for your computer…") }
                    if let receipt = model.lastReceipt, model.receiptContext == "controls" {
                        Label(receipt, systemImage: "checkmark.circle")
                            .font(.callout).foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                    agentCard
                    if let answer = model.companion?.answer, !answer.isEmpty {
                        VStack(alignment: .leading, spacing: Design.gap) {
                            Label("From your companion", systemImage: "quote.bubble").font(.headline)
                            Text(answer).textSelection(.enabled)
                        }.quietCard()
                    }
                }
            }.quietPage().quietEntrance()
                .quietStateAnimation(value: model.lastReceipt)
        }
        .background(Design.background)
        .navigationTitle("Controls")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
        .sheet(item: $decision) { DecisionView(decision: $0) }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Design.inset) {
            Label("Set the pace", systemImage: "music.note").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 120), spacing: Design.gap)], spacing: Design.gap) {
                ForEach(CompanionCommand.allCases.filter { $0 != .lock }) { command in
                    Button { Task { await model.command(command) } } label: {
                        VStack(spacing: 12) {
                            Image(systemName: command.symbol).font(.title2).accessibilityHidden(true)
                            Text(command.title).font(.subheadline).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 84)
                        .padding(8)
                    }.buttonStyle(QuietControlStyle())
                }
            }.disabled(!model.canControl || model.companion == nil)
            Button("Lock computer", systemImage: "lock") { confirmLock = true }
                .buttonStyle(.bordered).controlSize(.large).disabled(!model.canControl)
                .confirmationDialog("Lock your computer now?", isPresented: $confirmLock, titleVisibility: .visible) {
                    Button("Lock computer") { Task { await model.command(.lock) } }
                }
        }.quietCard()
    }

    private var agentCard: some View {
        VStack(alignment: .leading, spacing: Design.gap) {
            Label("A moment of your attention", systemImage: "hand.raised.fingers.spread").font(.headline)
            if let agents = model.companion?.agents {
                Text("\(agents.working) working · \(agents.needs) waiting")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let top = agents.top {
                    Text(top.name).font(.title3).bold()
                    Text(top.summary ?? "Review the request on your computer.")
                    Button("Review request", systemImage: "arrow.up.right") { decision = top }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canControl)
                } else {
                    Text("Nothing needs a decision right now.").foregroundStyle(.secondary)
                }
            } else {
                Text("Agent status is unavailable. Enable the Agents connector on your computer.")
                    .foregroundStyle(.secondary)
            }
        }.quietCard()
    }
}
