import SwiftUI

struct AppShell: View {
    private enum Destination: Hashable { case computer, beam, agents, assistant, accessory }
    @Environment(AppModel.self) private var model
    @Environment(AccessoryModel.self) private var accessory
    @Environment(\.scenePhase) private var scenePhase
    @State private var showConnections = false
    @State private var showSettings = false
    @State private var selectedTab = Destination.computer
    @State private var beamDrafts: [UUID: String] = [:]
    @State private var assistantDrafts: [UUID: String] = [:]
    @State private var newBeamDraft = ""
    @State private var newAssistantDraft = ""
    @State private var agents: AgentsModel?
    @State private var agentsGeneration: UUID?

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Computer", image: MobileGlyph.computer.asset, value: .computer) {
                NavigationStack {
                    HomeView(showConnections: $showConnections) { selectedTab = .accessory }
                        .toolbar { connectionToolbar }
                }
            }
            Tab("Beam", image: MobileGlyph.beam.asset, value: .beam) {
                NavigationStack {
                    WorkspaceFeatureView(feature: .beam, showConnections: $showConnections, draft: beamDraft(for: model.selectedID)) {
                        BeamView(words: beamDraft(for: model.selectedID))
                    }
                        .toolbar { connectionToolbar }
                }
            }
            Tab("Agents", image: MobileGlyph.agents.asset, value: .agents) {
                NavigationStack {
                    if model.selected?.kind == .companion {
                        CompanionRequestsView().toolbar { connectionToolbar }
                    } else {
                        WorkspaceFeatureView(feature: .agents, showConnections: $showConnections) {
                            if let agents { AgentsView(agents: agents) }
                            else { ProgressView("Reading sessions…") }
                        }
                            .toolbar { connectionToolbar }
                    }
                }
            }
            Tab("Assistant", image: MobileGlyph.assistant.asset, value: .assistant) {
                NavigationStack {
                    WorkspaceFeatureView(feature: .assistant, showConnections: $showConnections, draft: assistantDraft(for: model.selectedID)) {
                        AssistantView(isActive: selectedTab == .assistant, goal: assistantDraft(for: model.selectedID))
                    }.toolbar { connectionToolbar }
                }
            }
            Tab("k-chain", image: MobileGlyph.accessory.asset, value: .accessory) {
                NavigationStack { AccessoryView().toolbar { connectionToolbar } }
            }
        }
        .task(id: "agents-\(model.connectionGeneration)-\(scenePhase)-\(selectedTab)-\(model.online)") {
            agents?.stop()
            guard selectedTab == .agents, scenePhase == .active, model.online, model.selected?.kind == .computer else { return }
            // Owned above NavigationStack so pushing a session does not cancel its requests.
            if agentsGeneration != model.connectionGeneration {
                agents = AgentsModel(app: model)
                agentsGeneration = model.connectionGeneration
            }
            agents?.start()
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { accessory.backgrounded() } }
        .onChange(of: model.selectedID) { previous, selected in
            guard previous == nil, let selected else { return }
            if !newBeamDraft.isEmpty { beamDrafts[selected] = newBeamDraft; newBeamDraft = "" }
            if !newAssistantDraft.isEmpty { assistantDrafts[selected] = newAssistantDraft; newAssistantDraft = "" }
        }
        .sensoryFeedback(.success, trigger: model.acceptedActionCount)
        .sensoryFeedback(.error, trigger: model.failedActionCount)
        .sheet(isPresented: $showConnections) { ConnectionsView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .alert(
            "From your computer",
            isPresented: Binding(
                get: { model.notice != nil }, set: { if !$0 { model.notice = nil } }
            )
        ) {
            Button("OK") { model.notice = nil }
        } message: {
            Text(model.notice ?? "")
        }
        .task(id: "\(model.selectedID?.uuidString ?? "none")-\(scenePhase)-\(selectedTab)") {
            switch scenePhase {
            case .active:
                await model.monitor(
                    includeCompanion: selectedTab == .computer || (selectedTab == .agents && model.selected?.kind == .companion),
                    interactive: selectedTab != .accessory)
            case .background:
                model.suspend()
            default:
                // Inactive is transient (system alerts, the accessory picker, the app switcher).
                // Polling stops with this task; live state is only invalidated once the app is backgrounded.
                break
            }
        }
    }

    @ToolbarContentBuilder
    private var connectionToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showConnections = true
            } label: {
                MobileLabel(model.selected?.name ?? "Connect", icon: .computer).lineLimit(1)
            }
            .labelStyle(.titleAndIcon).accessibilityLabel("Connections")
            .accessibilityValue(model.selected?.name ?? "No computer selected")
            .disabled(model.interacting)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showSettings = true
            } label: {
                MobileLabel("Settings", icon: .settings)
            }
            .labelStyle(.iconOnly).accessibilityLabel("Settings")
        }
    }

    /// Bind to a captured computer ID, including late acknowledgements from its old view.
    private func beamDraft(for id: UUID?) -> Binding<String> {
        Binding(get: { id.flatMap { beamDrafts[$0] } ?? (id == nil ? newBeamDraft : "") }, set: { value in
            if let id { beamDrafts[id] = value } else { newBeamDraft = value }
        })
    }

    private func assistantDraft(for id: UUID?) -> Binding<String> {
        Binding(get: { id.flatMap { assistantDrafts[$0] } ?? (id == nil ? newAssistantDraft : "") }, set: { value in
            if let id { assistantDrafts[id] = value } else { newAssistantDraft = value }
        })
    }
}
