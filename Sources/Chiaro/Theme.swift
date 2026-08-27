import SwiftUI
import CoreText

enum Theme {
    static let canvas = Color(hex: 0x1A1A1C)
    static let panel = Color(hex: 0x232326)
    static let ground = Color(hex: 0x131315)
    static let amber = Color(hex: 0xE8A33D)
    /// Anthropic's terracotta — used only for Claude connection state.
    static let claude = Color(hex: 0xD97757)
    /// Destructive actions only (Revert, delete).
    static let danger = Color(hex: 0xE05A4E)
    static let ink = Color.white.opacity(0.87)
    static let ink2 = Color.white.opacity(0.52)
    static let ink3 = Color.white.opacity(0.34)
    static let hairline = Color.white.opacity(0.08)

    static let railWidth: CGFloat = 268

    private static var fontsRegistered = false

    static func registerFonts() {
        guard !fontsRegistered else { return }
        fontsRegistered = true
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: Resources.url("Fonts"), includingPropertiesForKeys: nil
        ) else { return }
        for url in files where ["otf", "ttf"].contains(url.pathExtension) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name = switch weight {
        case .semibold, .bold: "Geist SemiBold"
        case .medium: "Geist Medium"
        default: "Geist Regular"
        }
        return .custom(name, size: size)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(weight == .medium ? "Geist Mono Medium" : "Geist Mono Regular", size: size)
    }

    /// Fraunces: the wordmark voice. Sentence case, never uppercase.
    /// Two bundled static instances — variable axes don't survive Google's TTF export.
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        switch weight {
        case .semibold, .bold: .custom("Fraunces-SemiBold", size: size)
        default: .custom("Fraunces-Regular", size: size)
        }
    }

    /// Archivo ExtraBold: display headlines, the same voice as the site's
    /// hero. Pair with kerning at -0.032em (size × -0.032), the site's
    /// tracking, at the call site.
    static func headline(_ size: CGFloat) -> Font {
        .custom("Archivo-ExtraBold", size: size)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .displayP3,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
