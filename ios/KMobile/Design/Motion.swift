import SwiftUI

/// Finite, event-driven motion. No timers, perpetual effects or animated polling timestamps.
struct QuietControlStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(enabled ? Design.accent : .secondary)
            .background(Design.accent.opacity(configuration.isPressed ? 0.16 : 0.06), in: .rect(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Design.accent.opacity(contrast == .increased ? 0.5 : 0.14), lineWidth: 1) }
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.975)
            .animation(reduceMotion ? nil : .snappy(duration: 0.18, extraBounce: 0), value: configuration.isPressed)
    }
}

private struct QuietEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    func body(content: Content) -> some View {
        content
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 8)
            .onAppear {
                guard !appeared else { return }
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.28, extraBounce: 0)) { appeared = true }
            }
    }
}

private struct QuietStateAnimation<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: value)
    }
}

extension View {
    func quietEntrance() -> some View { modifier(QuietEntrance()) }
    func quietStateAnimation<Value: Equatable>(value: Value) -> some View { modifier(QuietStateAnimation(value: value)) }
}

struct ConnectionStatus: View {
    let online: Bool
    let checking: Bool
    let selected: Bool
    var body: some View {
        HStack(spacing: 6) {
            if checking { ProgressView().controlSize(.small) }
            else { Image(systemName: online ? "checkmark.circle.fill" : "circle.dashed").accessibilityHidden(true) }
            Text(checking ? "Connecting" : online ? "Connected" : selected ? "Offline" : "Not connected")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(online ? Design.accent : .secondary)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Design.accent.opacity(0.07), in: .capsule)
        .accessibilityElement(children: .combine)
        .quietStateAnimation(value: online)
    }
}
