import SwiftUI

/// Liquid Glass for transient surfaces (ADR 0004), with a material fallback so the
/// app still builds if the glass APIs shift under us.
struct ChiaroGlass: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // The dark underlay keeps glass chrome legible over bright photo
            // regions — glass alone washes out on white.
            if let tint {
                content.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
                    .background(RoundedRectangle(cornerRadius: cornerRadius).fill(Color.black.opacity(0.28)))
            } else {
                content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                    .background(RoundedRectangle(cornerRadius: cornerRadius).fill(Color.black.opacity(0.28)))
            }
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .background((tint ?? .clear).opacity(0.8), in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.white.opacity(0.14)))
        }
    }
}

extension View {
    func chiaroGlass(cornerRadius: CGFloat = 16, tint: Color? = nil) -> some View {
        modifier(ChiaroGlass(cornerRadius: cornerRadius, tint: tint))
    }

    /// Pointing-hand cursor on hover — every clickable control should read as one.
    func clickCursor() -> some View {
        onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
