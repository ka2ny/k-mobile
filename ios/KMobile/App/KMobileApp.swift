import SwiftUI

@main
struct KMobileApp: App {
    @State private var model = AppModel()
    @State private var accessory = AccessoryModel()

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(model)
                .environment(accessory)
                .tint(Color("AccentColor"))
        }
    }
}
