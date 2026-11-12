import SwiftUI

struct AppShell: View {
    private enum Destination: Hashable { case computer, beam, agents, assistant, accessory }
    @Environment(AppModel.self) private var model
    @Environment(AccessoryModel.self) private var accessory
    @Environment(\.scenePhase) private var scenePhase
    @State private var showConnections = false
    @State private var showSettings = false
    @State private var selectedTab = Destination.computer

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Computer", image: MobileGlyph.computer.asset, value: .computer) {
                NavigationStack {
                    HomeView(showConnections: $showConnections)
                        .toolbar { connectionToolbar }
                }
            }
            Tab("Beam", image: MobileGlyph.beam.asset, value: .beam) {
                NavigationStack {
                    WorkspaceFeatureView(feature: .beam, showConnections: $showConnections) { BeamView() }
                        .toolbar { connectionToolbar }
                }
            }
            Tab("Agents", image: MobileGlyph.agents.asset, value: .agents) {
                NavigationStack {
                    if model.selected?.kind == .companion {
                        CompanionRequestsView().toolbar { connectionToolbar }
                    } else {
                        WorkspaceFeatureView(feature: .agents, showConnections: $showConnections) { AgentsView() }
                            .toolbar { connectionToolbar }
                    }
                }
            }
            Tab("Assistant", image: MobileGlyph.assistant.asset, value: .assistant) {
                NavigationStack {
                    WorkspaceFeatureView(feature: .assistant, showConnections: $showConnections) {
                        AssistantView(isActive: selectedTab == .assistant)
                    }.toolbar { connectionToolbar }
                }
            }
            Tab("k-chain", image: MobileGlyph.accessory.asset, value: .accessory) {
                NavigationStack { AccessoryView().toolbar { connectionToolbar } }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { accessory.backgrounded() } }
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
                MobileLabel("Connections", icon: .computer)
            }
            .labelStyle(.iconOnly).accessibilityLabel("Connections")
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
}
