import SwiftUI

/// Known MCP clients: friendly name, official brand color (Simple Icons data),
/// and bundled brand mark. Black-on-light brands tint to ink on our dark ground.
struct AgentBrand {
    let name: String
    let color: Color
    let iconFile: String?

    static let claude = AgentBrand(name: "Claude", color: Color(hex: 0xD97757), iconFile: "claude")
    static let known: [(keys: [String], brand: AgentBrand)] = [
        (["claude"], .claude),
        (["cursor"], AgentBrand(name: "Cursor", color: Theme.ink, iconFile: "cursor")),
        (["copilot"], AgentBrand(name: "Copilot", color: Theme.ink, iconFile: "githubcopilot")),
        (["codex", "openai"], AgentBrand(name: "Codex", color: Theme.ink, iconFile: "openai")),
        (["gemini"], AgentBrand(name: "Gemini", color: Color(hex: 0x8E75B2), iconFile: "googlegemini")),
    ]
    static let fallback = AgentBrand(name: "Agent", color: Theme.amber, iconFile: nil)

    static func match(_ clientName: String?) -> AgentBrand {
        guard let lower = clientName?.lowercased() else { return fallback }
        return known.first { $0.keys.contains(where: lower.contains) }?.brand ?? fallback
    }

    private static var imageCache: [String: NSImage] = [:]

    /// The brand mark in the brand color; sparkles for unknowns. The marks are
    /// solid-black SVGs, so they're masked rather than template-tinted — NSImage
    /// drops the template flag on SVG reps and they'd render black on black.
    @ViewBuilder var icon: some View {
        if let iconFile, let image = Self.image(named: iconFile) {
            color.mask { Image(nsImage: image).resizable().scaledToFit() }
        } else {
            Image(systemName: "sparkles")
                .resizable()
                .scaledToFit()
                .foregroundStyle(color)
        }
    }

    private static func image(named name: String) -> NSImage? {
        if let cached = imageCache[name] { return cached }
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "AgentIcons"),
              let image = NSImage(contentsOf: url) else { return nil }
        imageCache[name] = image
        return image
    }
}
