import SwiftUI

/// Liquid Glass for transient surfaces (ADR 0004), with a material fallback so the
/// app still builds if the glass APIs shift under us.
struct ChiaroGlass: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.white.opacity(0.14)))
        }
    }
}

extension View {
    func chiaroGlass(cornerRadius: CGFloat = 16) -> some View {
        modifier(ChiaroGlass(cornerRadius: cornerRadius))
    }

    /// Pointing-hand cursor on hover — every clickable control should read as one.
    func clickCursor() -> some View {
        onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
