import SwiftUI

enum Design {
    static let inset: CGFloat = 24
    static let gap: CGFloat = 16
    static let radius: CGFloat = 24
    static let background = Color("Canvas")
    static let surface = Color("Surface")
    static let accent = Color("AccentColor")
}

extension View {
    func quietCard() -> some View {
        padding(Design.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Design.surface, in: .rect(cornerRadius: Design.radius))
    }

    func quietPage() -> some View {
        frame(maxWidth: 760)
            .padding(Design.inset)
            .frame(maxWidth: .infinity)
    }
}
