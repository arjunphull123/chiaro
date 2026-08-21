import SwiftUI
import TipKit


/// "Connect agent": copyable orientation prompt pointing any coding agent at the
/// local MCP server (ADR 0008). The server self-describes via tools/list schemas;
/// this prompt is just the address and etiquette.
/// The window's agent-status pill, cycling through the agent lifecycle:
/// "Connect agent" → "<client> connected" → "🔒 <client> is editing…". State
/// only — every string here is one of a handful of known phrases, so the pill's
/// width is bounded and it can never overhang the canvas. The live intent is
/// deliberately NOT part of this view: it's unbounded (whatever text the
/// driving agent sends), so it renders as its own floating line — see
/// `AgentIntentBadge` below, composed as an independent sibling in RootView
/// rather than nested in here, so it can never resize or shift this pill.
struct AgentStatusStrip: View {
    private let agentTip = AgentTip()
    let library: Library
    @State private var showing = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let editing = library.agentActive
            let connected = AgentStatus.shared.isConnected
            let brand = AgentStatus.shared.brand
            let active = editing || connected
            Button {
                agentTip.invalidate(reason: .actionPerformed)
                showing.toggle()
            } label: {
                HStack(spacing: 7) {
                    if active {
                        brand.icon.frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.ink3)
                    }
                    Text(state(editing: editing, connected: connected))
                        .font(Theme.ui(11.5, .medium))
                        .foregroundStyle(active ? Theme.ink : Theme.ink2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if editing {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(brand.color)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(editing ? brand.color.opacity(0.12) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(active ? brand.color.opacity(0.45) : Theme.hairline)
                )
            }
            .buttonStyle(.plain)
            .clickCursor()
            .animation(.easeOut(duration: 0.2), value: editing)
            .popoverTip(AgentTip.isEligible ? agentTip : nil, arrowEdge: .bottom)
            .popover(isPresented: $showing, arrowEdge: .bottom) { AgentConnectPopover() }
        }
    }

    /// One of three known phrases — never runtime text, so this never needs
    /// a width cap the way the intent does.
    private func state(editing: Bool, connected: Bool) -> String {
        editing ? "\(AgentStatus.shared.displayName) is editing…"
        : connected ? "\(AgentStatus.shared.displayName) is connected"
        : "Connect your agent"
    }
}

/// The agent's live, unbounded intent string, as its own floating glass label —
/// the same transient-surface treatment as the filmstrip nav pill and the
/// scrub-dial HUD (ADR 0004), not a rail element. Composed as an independent
/// sibling of `AgentStatusStrip` in RootView, positioned by absolute padding
/// rather than sharing a layout container with the pill, so nothing it does —
/// growing, truncating, appearing, disappearing — can ever displace or resize
/// the pill above it. Shows only while an agent is actually working, and
/// clears with the same 3s timer that clears `Library.agentIntent`.
struct AgentIntentBadge: View {
    let library: Library

    var body: some View {
        if library.agentActive, let intent = library.agentIntent {
            Text(intent)
                .font(Theme.ui(10, .medium))
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .chiaroGlass(cornerRadius: 7)
                // Same 16pt trailing inset as the pill above, so a maxed-out
                // line's leading edge lands exactly on the rail's own leading
                // edge — it can share the pill's trailing edge without ever
                // reaching past the rail into the canvas.
                .frame(maxWidth: Theme.railWidth - 16, alignment: .trailing)
                .transition(.opacity)
        }
    }
}

struct AgentConnectPopover: View {
    @State private var copied = false

    private var prompt: String { MCPServer.onboardingPrompt }

    var body: some View {
        Group {
            if AgentStatus.shared.actions.isEmpty {
                connectContent
            } else {
                historyContent
            }
        }
        // One fixed size for every state: animated popover resizes crash NSPopover.
        .frame(width: 380, height: 312)
        .presentationBackground(.ultraThinMaterial)
    }

    /// Once an agent has done things, the popover becomes its activity log.
    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                AgentStatus.shared.brand.icon.frame(width: 14, height: 14)
                Text("\(AgentStatus.shared.displayName) in Chiaro")
                    .font(Theme.ui(14, .semibold))
                    .foregroundStyle(Theme.ink)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(AgentStatus.shared.actions) { action in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(action.date.formatted(date: .omitted, time: .shortened))
                                .font(Theme.mono(9))
                                .foregroundStyle(Theme.ink3)
                            Text(action.text)
                                .font(Theme.ui(11))
                                .foregroundStyle(Theme.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            DisclosureGroup("Connection prompt") {
                promptBlock(scrollHeight: 80).padding(.top, 6)
            }
            .font(Theme.ui(11, .medium))
            .tint(Theme.ink3)
            .foregroundStyle(Theme.ink2)
        }
        .padding(18)
    }

    private var connectContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Drive Chiaro with any agent")
                .font(Theme.ui(14, .semibold))
                .foregroundStyle(Theme.ink)
            Text("Paste this into any MCP-capable agent — Claude Code, Cursor, whatever you run — and it can see, edit, and export your photos, live in this window. It will confirm once connected.")
                .font(Theme.ui(11.5))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            promptBlock(scrollHeight: 128)
        }
        .padding(18)
    }

    private func promptBlock(scrollHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                Text(prompt)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.ink2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: scrollHeight)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.3)))
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(prompt, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Text(copied ? "Copied ✓" : "Copy prompt")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AmberButtonStyle())
            .clickCursor()
        }
    }
}
