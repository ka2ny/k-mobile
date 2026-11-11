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
                if !model.online && model.selected != nil && model.refreshing && model.connectionError == nil {
                    ProgressView("Connecting to your computer…").frame(maxWidth: .infinity).padding(Design.inset)
                } else if !model.online {
                    ContentUnavailableView("Your companion is out of reach", systemImage: "wave.3.right.circle", description: Text("Select a connection and keep your computer awake."))
                } else {
                    if let error = model.companionError {
                        Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                    }
                    if model.device?.control != "full" {
                        Label("Full control needs approval on your computer.", systemImage: "hand.raised")
                            .foregroundStyle(.secondary)
                        if model.selected?.kind == .computer {
                            Button("Ask for full control") { Task { await model.requestControl() } }
                                .buttonStyle(.bordered).controlSize(.large).disabled(model.interacting)
                        }
                    }
                    if model.hub?.stopped == true { Label("Controls paused on your computer", systemImage: "pause.circle") }
                    controls
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
                .quietStateAnimation(value: model.busy)
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
            }
            // Permission decides how the keys look; a request in flight only holds further taps.
            .disabled(!model.controlAllowed || model.companion == nil)
            .allowsHitTesting(!model.interacting)
            Button("Lock computer", systemImage: "lock") { confirmLock = true }
                .buttonStyle(.bordered).controlSize(.large).disabled(!model.canControl)
                .confirmationDialog("Lock your computer now?", isPresented: $confirmLock, titleVisibility: .visible) {
                    Button("Lock computer") { Task { await model.command(.lock) } }
                }
            statusLine
        }.quietCard()
    }

    /// One fixed row for progress and receipts, so a key press never moves the controls under a thumb.
    private var statusLine: some View {
        Group {
            if model.busy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for your computer…")
                }
            } else if let receipt = model.lastReceipt, model.receiptContext == "controls" || model.receiptContext == "permission" {
                Label(receipt, systemImage: "checkmark.circle")
            } else if model.controlAllowed && model.companion == nil && model.companionError == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading controls…")
                }
            } else {
                Text("Responses from your computer appear here.")
            }
        }
        .font(.callout).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
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
                        .buttonStyle(QuietProminentStyle()).disabled(!model.controlAllowed)
                } else {
                    Text("Nothing needs a decision right now.").foregroundStyle(.secondary)
                }
            } else if model.companion == nil && model.companionError == nil {
                Text("Checking for agent requests…").foregroundStyle(.secondary)
            } else {
                Text("Agent status is unavailable. Enable the Agents connector on your computer.")
                    .foregroundStyle(.secondary)
            }
        }.quietCard()
    }
}
