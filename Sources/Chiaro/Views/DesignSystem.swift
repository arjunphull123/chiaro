import SwiftUI

// The component vocabulary. Every button in the app is one of these four;
// ad-hoc button chrome is a bug. Copy is sentence case, no trailing periods.

/// Primary action: filled amber, near-black text. One per surface.
struct AmberButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(12, .semibold))
            .foregroundStyle(Color(hex: 0x131315))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.amber))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Secondary action: quiet outline, ink text.
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(12, .medium))
            .foregroundStyle(Theme.ink2)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
            .opacity(configuration.isPressed ? 0.7 : 1)
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
