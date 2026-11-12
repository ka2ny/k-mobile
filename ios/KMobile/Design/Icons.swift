import SwiftUI

/// k-hole's 24-unit, 1.5-unit outline family. Template assets keep geometry
/// unchanged for selected, disabled, light and dark appearances.
enum MobileGlyph: String, CaseIterable {
    case home, remote, beam, agents, assistant, files, settings
    case activity, accessory, controls, computer, connection
    var asset: String { "Glyph" + rawValue.prefix(1).uppercased() + String(rawValue.dropFirst()) }
}

struct MobileIcon: View {
    let glyph: MobileGlyph
    var size: CGFloat = 24
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    init(_ glyph: MobileGlyph, size: CGFloat = 24) {
        self.glyph = glyph
        self.size = size
    }

    var body: some View {
        Image(glyph.asset).renderingMode(.template)
            .resizable().scaledToFit()
            .frame(width: size * scale, height: size * scale)
            .accessibilityHidden(true)
    }
}

struct MobileLabel: View {
    let title: String
    let glyph: MobileGlyph
    init(_ title: String, icon: MobileGlyph) {
        self.title = title
        self.glyph = icon
    }
    var body: some View {
        Label {
            Text(title)
        } icon: {
            MobileIcon(glyph, size: 22)
        }
    }
}
