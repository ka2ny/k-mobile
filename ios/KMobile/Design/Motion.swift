import SwiftUI

/// Finite, event-driven motion. No timers, perpetual effects or animated polling timestamps.
struct QuietControlStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var enabled
    @Environment(\.mobileAccent) private var accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(enabled ? accent : Design.muted)
            .background(
                accent.opacity(configuration.isPressed ? 0.16 : 0.06), in: .rect(cornerRadius: Design.controlRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Design.controlRadius).strokeBorder(
                    accent.opacity(contrast == .increased ? 0.5 : 0.14), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: Design.controlRadius))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// Primary action keeps an opaque accent and a measured light/dark foreground pair.
struct QuietProminentStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @Environment(\.mobileAccent) private var accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(enabled ? Design.onAccent : Design.muted)
            .padding(.horizontal, 20)
            .frame(minHeight: 50)
            .background(
                enabled ? accent : Design.muted.opacity(0.12),
                in: .rect(cornerRadius: Design.controlRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Design.controlRadius - 2)
                    .strokeBorder(Design.onAccent.opacity(configuration.isPressed && enabled ? 0.45 : 0), lineWidth: 1)
                    .padding(2).allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: Design.controlRadius))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
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
    func quietStateAnimation<Value: Equatable>(value: Value) -> some View {
        modifier(QuietStateAnimation(value: value))
    }
}

struct QuietSecondaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.medium))
            .foregroundStyle(configuration.role == .destructive ? Design.danger : Design.ink)
            .padding(.horizontal, 16).frame(minHeight: 48)
            .background(
                Design.border.opacity(configuration.isPressed ? 0.3 : 0.12),
                in: .rect(cornerRadius: Design.controlRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Design.controlRadius)
                    .strokeBorder(contrast == .increased ? Design.muted : Design.border, lineWidth: 1)
            }
            .opacity(enabled ? 1 : 0.5)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct ConnectionStatus: View {
    let online: Bool
    let checking: Bool
    let selected: Bool
    var body: some View {
        HStack(spacing: 8) {
            if checking {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: online ? "checkmark.circle" : "circle.dashed")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(online ? Design.success : Design.muted)
                    .accessibilityHidden(true)
            }
            Text(checking ? "Connecting" : online ? "Connected" : selected ? "Offline" : "Not connected")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Design.muted)
        .accessibilityElement(children: .combine)
        .quietStateAnimation(value: online)
    }
}
