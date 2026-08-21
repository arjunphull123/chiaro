import SwiftUI
import TipKit


/// "Connect agent": copyable orientation prompt pointing any coding agent at the
/// local MCP server (ADR 0008). The server self-describes via tools/list schemas;
/// this prompt is just the address and etiquette.
/// The window's one agent-status line, cycling through the agent lifecycle:
/// "Connect agent" → "<client> connected" → "🔒 Agent is editing…" (+ intent).
/// Lives in the title strip (see RootView) — one line, so state and intent are
/// a single truncating Text rather than the two stacked lines a rail pill could
/// afford.
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
                    Text(line(editing: editing, connected: connected))
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
            // Anchored to the pill, inside the 440pt frame below: attached
            // outside it, the popover points at the frame's centre instead.
            .popoverTip(AgentTip.isEligible ? agentTip : nil, arrowEdge: .bottom)
            .popover(isPresented: $showing, arrowEdge: .bottom) { AgentConnectPopover() }
        }
        // Caps growth so a long intent truncates instead of pushing the strip
        // toward the traffic lights or the window edge; short states just size
        // to fit under this. Trailing-aligned so the pill's own trailing edge
        // stays pinned to the window edge at any width — it grows leftward
        // rather than floating centred in the 440pt ceiling.
        .frame(maxWidth: 440, alignment: .trailing)
    }

    /// State phrase, plus the intent appended in a dimmer run when editing —
    /// one Text so the whole line truncates together (mirrors the mixed-style
    /// runs LibraryView's footer count builds).
    private func line(editing: Bool, connected: Bool) -> AttributedString {
        var text = AttributedString(
            editing ? "\(AgentStatus.shared.displayName) is editing…"
            : connected ? "\(AgentStatus.shared.displayName) is connected"
            : "Connect your agent"
        )
        text.font = Theme.ui(11.5, .medium)
        if editing, let intent = library.agentIntent {
            var suffix = AttributedString("  " + intent)
            suffix.font = Theme.ui(10.5)
            suffix.foregroundColor = Theme.ink2
            text += suffix
        }
        return text
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
