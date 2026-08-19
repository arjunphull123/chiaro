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

/// Icon glass button that reveals its label on hover — toolbars stay a tight
/// row of icons until the pointer asks for words.
struct HoverLabelButton: View {
    let title: String
    let icon: String
    var active = false
    var disabled = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                if hovering {
                    Text(title)
                        .font(Theme.ui(11, .medium))
                        .fixedSize()
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .foregroundStyle(active ? Theme.amber : Theme.ink2)
            .frame(height: 14)
            .padding(.horizontal, hovering ? 12 : 9)
            .padding(.vertical, 7)
            .chiaroGlass(cornerRadius: 10)
        }
        .buttonStyle(.plain)
        .clickCursor()
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.14)) { hovering = inside }
        }
        .help(title)
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

/// The mark: six curved aperture blades in pinwheel rotation, open at the core
/// (concept C1). Drawn in a 96pt design space, scaled to fit.
struct PinwheelMark: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 96
        let cx = rect.midX, cy = rect.midY
        func pt(_ r: Double, _ angle: Double) -> CGPoint {
            CGPoint(x: cx + r * cos(angle) * scale, y: cy + r * sin(angle) * scale)
        }
        var path = Path()
        let rOut = 40.0, rIn = 13.0, sweep = 0.85, curve = 0.42, tip = 1.02
        for k in 0..<6 {
            let t0 = 2 * .pi * Double(k) / 6
            let t1 = t0 + sweep
            let o0 = pt(rOut, t0)
            let o1 = pt(rOut, t1)
            let mid = pt(rOut * tip, (t0 + t1) / 2)
            let inner = pt(rIn, t1 + curve)
            // Closing control sits at 0.7x the chord midpoint (relative to center),
            // matching the SVG geometry the mark was designed in.
            let closeControl = CGPoint(
                x: cx + ((inner.x - cx) + (o0.x - cx)) / 2 * 0.7,
                y: cy + ((inner.y - cy) + (o0.y - cy)) / 2 * 0.7
            )
            path.move(to: o0)
            path.addQuadCurve(to: o1, control: mid)
            path.addLine(to: inner)
            path.addQuadCurve(to: o0, control: closeControl)
            path.closeSubpath()
        }
        return path
    }
}

struct AppMark: View {
    var size: CGFloat = 24

    var body: some View {
        PinwheelMark()
            .fill(Theme.amber)
            .frame(width: size, height: size)
    }
}

/// The app icon artwork: macOS-26 squircle tile, graphite ground lit from the
/// upper left, the pinwheel in amber. Rendered to PNG via --render-icon.
struct AppIconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 1024 * 0.2237, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0x2F2F35), Color(hex: 0x141416)],
                        center: UnitPoint(x: 0.32, y: 0.22),
                        startRadius: 60, endRadius: 1150
                    )
                )
            PinwheelMark()
                .fill(Theme.amber)
                .frame(width: 620, height: 620)
                .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
        }
        .frame(width: 1024, height: 1024)
    }
}
