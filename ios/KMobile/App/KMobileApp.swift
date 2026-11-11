import SwiftUI

@main
struct KMobileApp: App {
    @State private var model = AppModel()
    @State private var accessory = AccessoryModel()

    @AppStorage("appearance.mode") private var appearance = "system"
    @AppStorage("appearance.accent") private var accent = "sage"

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(model)
                .environment(accessory)
                .environment(\.mobileAccent, (MobileAccent(rawValue: accent) ?? .sage).color)
                .tint((MobileAccent(rawValue: accent) ?? .sage).color)
                .preferredColorScheme((MobileAppearance(rawValue: appearance) ?? .system).scheme)
                .foregroundStyle(Design.ink)
                .symbolRenderingMode(.monochrome)
                .symbolVariant(.none)
        }
    }
}
