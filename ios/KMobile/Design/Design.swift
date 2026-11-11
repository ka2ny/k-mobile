import SwiftUI

enum Design {
    static let inset: CGFloat = 24
    static let gap: CGFloat = 16
    static let radius: CGFloat = 20
    static let controlRadius: CGFloat = 12
    static let background = Color("Canvas")
    static let surface = Color("Surface")
    static let ink = Color("Ink")
    static let muted = Color("MutedInk")
    static let border = Color("Border")
    static let success = Color("Success")
    static let caution = Color("Caution")
    static let danger = Color("Danger")
    static let onAccent = Color("OnAccent")
}

private struct QuietCard: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.padding(Design.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Design.surface, in: .rect(cornerRadius: Design.radius))
            .overlay {
                RoundedRectangle(cornerRadius: Design.radius)
                    .strokeBorder(contrast == .increased ? Design.muted : Design.border.opacity(0.55), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

struct PageHeading: View {
    let title: String
    let detail: String
    var eyebrow: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let eyebrow {
                Text(eyebrow).font(.caption.monospaced()).tracking(1.4).foregroundStyle(Design.muted)
            }
            Text(title).font(.largeTitle.weight(.medium)).tracking(-0.6)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(detail).font(.body).foregroundStyle(Design.muted)
        }.padding(.vertical, 8)
    }
}

struct QuietEmptyState: View {
    let title: String
    let detail: String
    let icon: MobileGlyph
    var body: some View {
        VStack(alignment: .leading, spacing: Design.gap) {
            MobileIcon(icon, size: 32).foregroundStyle(Design.muted)
            Text(title).font(.title2.weight(.medium)).accessibilityAddTraits(.isHeader)
            Text(detail).foregroundStyle(Design.muted)
        }.quietCard()
    }
}

extension View {
    func quietCard() -> some View { modifier(QuietCard()) }

    func quietList() -> some View {
        scrollContentBackground(.hidden)
            .background(Design.background)
            .environment(\.defaultMinListRowHeight, 52)
            .listSectionSpacing(20)
    }

    func quietPage() -> some View {
        frame(maxWidth: 760)
            .padding(Design.inset)
            .frame(maxWidth: .infinity)
    }
}
