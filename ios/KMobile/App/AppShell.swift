import SwiftUI

struct AppShell: View {
    private enum Destination: Hashable { case home, accessory, companion, assistant, activity }
    @Environment(AppModel.self) private var model
    @Environment(AccessoryModel.self) private var accessory
    @Environment(\.scenePhase) private var scenePhase
    @State private var showConnections = false
    @State private var showSettings = false
    @State private var selectedTab = Destination.home

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "square.grid.2x2", value: .home) {
                NavigationStack {
                    HomeView(showConnections: $showConnections)
                        .toolbar { connectionToolbar }
                }
            }
            Tab("k-chain", systemImage: "key.horizontal", value: .accessory) {
                NavigationStack { AccessoryView().toolbar { connectionToolbar } }
            }
            Tab("Controls", systemImage: "wave.3.right", value: .companion) {
                NavigationStack {
                    CompanionView()
                        .toolbar { connectionToolbar }
                }
            }
            Tab("Assistant", systemImage: "sparkle", value: .assistant) {
                NavigationStack {
                    AssistantView(isActive: selectedTab == .assistant)
                        .toolbar { connectionToolbar }
                }
            }
            Tab("Activity", systemImage: "clock", value: .activity) {
                NavigationStack {
                    ActivityView()
                        .toolbar { connectionToolbar }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { accessory.backgrounded() } }
        .sensoryFeedback(.success, trigger: model.acceptedActionCount)
        .sensoryFeedback(.error, trigger: model.failedActionCount)
        .sheet(isPresented: $showConnections) { ConnectionsView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .alert("From your computer", isPresented: Binding(
            get: { model.notice != nil }, set: { if !$0 { model.notice = nil } }
        )) { Button("OK") { model.notice = nil } } message: { Text(model.notice ?? "") }
        .task(id: "\(model.selectedID?.uuidString ?? "none")-\(scenePhase)-\(selectedTab)") {
            switch scenePhase {
            case .active:
                await model.monitor(includeCompanion: selectedTab == .companion, interactive: selectedTab == .home || selectedTab == .companion || selectedTab == .assistant)
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
            Button("Connections", systemImage: "desktopcomputer") { showConnections = true }
                .disabled(model.interacting)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Settings", systemImage: "slider.horizontal.3") { showSettings = true }
        }
    }
}
