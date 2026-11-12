import SwiftUI

enum MobileAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum MobileAccent: String, CaseIterable, Identifiable {
    case sage, ice, lilac, rose, amber
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .sage: Color("AccentColor")
        case .ice: Color("AccentIce")
        case .lilac: Color("AccentLilac")
        case .rose: Color("AccentRose")
        case .amber: Color("AccentAmber")
        }
    }
}

private struct MobileAccentKey: EnvironmentKey {
    static let defaultValue = Color("AccentColor")
}

extension EnvironmentValues {
    var mobileAccent: Color {
        get { self[MobileAccentKey.self] }
        set { self[MobileAccentKey.self] = newValue }
    }
}
