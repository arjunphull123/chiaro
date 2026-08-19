import SwiftUI

/// All styles dim themselves when disabled — call sites never re-implement it.
private struct EnabledDim: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    func body(content: Content) -> some View {
        content.opacity(isEnabled ? 1 : 0.45)
    }
}

// The component vocabulary. Every button in the app is one of these four;
// ad-hoc button chrome is a bug. Copy is sentence case, no trailing periods.

/// Primary action: amber-tinted Liquid Glass, near-black text. One per surface.
struct AmberButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(12, .semibold))
            .foregroundStyle(Color(hex: 0x131315))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .chiaroGlass(cornerRadius: 8, tint: Theme.amber)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .modifier(EnabledDim())
    }
}

/// Secondary action: plain glass, ink text.
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(12, .medium))
            .foregroundStyle(Theme.ink2)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .chiaroGlass(cornerRadius: 8)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .modifier(EnabledDim())
    }
}

/// Floating action over the canvas: Liquid Glass pill. `tint` marks emphasis
/// (amber for Export / active states).
struct GlassButtonStyle: ButtonStyle {
    var tint: Color = Theme.ink2

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(11, .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .chiaroGlass(cornerRadius: 10)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .modifier(EnabledDim())
    }
}

/// Compact square glass button for icon-only actions.
struct GlassIconButtonStyle: ButtonStyle {
    var tint: Color = Theme.ink2

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 28)
            .chiaroGlass(cornerRadius: 10)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .modifier(EnabledDim())
    }
}

/// Selectable pill chip (aspect ratios, export formats, sizes, color spaces).
struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.ui(10.5, selected ? .medium : .regular))
                .foregroundStyle(selected ? Theme.amber : Theme.ink2)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(selected ? 0.08 : 0.03)))
                .overlay(Capsule().stroke(selected ? Theme.amber.opacity(0.5) : Theme.hairline))
        }
        .buttonStyle(.plain)
        .clickCursor()
    }
}

/// Interim brand mark: a sphere lit from the upper right — chiaroscuro itself.
/// Doubles as the app-icon motif until a real icon is designed.
struct AppMark: View {
    var size: CGFloat = 24

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Theme.amber, Color(hex: 0x8A5A2B), Color(hex: 0x17130E)],
                    center: UnitPoint(x: 0.68, y: 0.3),
                    startRadius: size * 0.05,
                    endRadius: size * 0.95
                )
            )
            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
            .frame(width: size, height: size)
    }
}
