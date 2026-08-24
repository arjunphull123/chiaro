import SwiftUI
import TipKit

/// The window's agent-status card, cycling through the agent lifecycle:
/// "Connect your agent" → "<client> is connected" → "🔒 <client> is editing…",
/// with the agent's live intent wrapping underneath while it works.
///
/// The card is a FIXED WIDTH — the rail's inner content column — in every
/// state. That is the whole defence against overflow, which recurred three
/// times while this sized itself to its content: any string an agent supplies
/// (its self-reported name, its intent) could push the geometry around. Fixed
/// width plus truncation means runtime text can only ever shorten itself, never
/// move an edge. The same width applies in the library, which has no rail, so
/// the card is identical across both views.
struct AgentStatusStrip: View {
    private let agentTip = AgentTip()
    let library: Library
    @State private var showing = false

    /// The rail's inner column: `railWidth` less its 16pt horizontal padding.
    /// At a 16pt trailing inset the card's edges land exactly on the rail's
    /// own content edges, so it reads as part of that column rather than
    /// floating at an arbitrary width.
    static let width = Theme.railWidth - 32

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let editing = library.agentActive
            let connected = AgentStatus.shared.isConnected
            let brand = AgentStatus.shared.brand
            let active = editing || connected
            Button {
                agentTip.invalidate(reason: .actionPerformed)
                showing.toggle()
            } label: {
                VStack(alignment: .leading, spacing: 7) {
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
                        Spacer(minLength: 6)
                        trailing(active: active, now: ctx.date)
                    }
                    if editing, let intent = library.agentIntent {
                        Theme.hairline.frame(height: 1)
                        // Wraps rather than truncating: the intent is the one
                        // thing here worth reading in full, and vertical growth
                        // is free where horizontal growth was the bug.
                        Text(intent)
                            .font(Theme.ui(10, .medium))
                            .foregroundStyle(Theme.ink2)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .frame(width: Self.width, alignment: .leading)
                .background {
                    if editing {
                        RoundedRectangle(cornerRadius: 9).fill(brand.color.opacity(0.14))
                    }
                }
                // Glass only once an agent is in the picture: idle, this is a
                // hint and should stay light over the photo. Active, it carries
                // live text that has to stay legible over a bright frame.
                .background {
                    if active { Color.clear.chiaroGlass(cornerRadius: 9) }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(active ? brand.color.opacity(0.45) : Theme.hairline)
                }
            }
            .buttonStyle(.plain)
            .clickCursor()
            .animation(.easeOut(duration: 0.2), value: editing)
            .animation(.easeOut(duration: 0.2), value: library.agentIntent)
            .popoverTip(AgentTip.isEligible ? agentTip : nil, arrowEdge: .bottom)
            .popover(isPresented: $showing, arrowEdge: .bottom) { AgentConnectPopover() }
        }
    }

    /// Right column. Connected: how long since the agent last spoke, which is
    /// the question a glance up here is actually asking — is this live or
    /// stale. Idle: a chevron, because the card is a call to action and should
    /// read as one. Deliberately not the last activity line: that text is
    /// unbounded, it already has a home in the popover, and it is what caused
    /// the overflow this layout exists to prevent.
    @ViewBuilder
    private func trailing(active: Bool, now: Date) -> some View {
        if active, let seen = AgentStatus.shared.lastSeen {
            Text(elapsed(since: seen, now: now))
                .font(Theme.mono(9))
                .foregroundStyle(Theme.ink3)
                .fixedSize()
        } else if !active {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Theme.ink3)
        }
    }

    /// Under a minute reads as "now": the pill refreshes on a 30s tick, so
    /// second-level precision would be stale as often as it was right.
    private func elapsed(since: Date, now: Date) -> String {
        now.timeIntervalSince(since) < 60
        ? "now"
        : since.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
    }

    private func state(editing: Bool, connected: Bool) -> String {
        editing ? "\(AgentStatus.shared.displayName) is editing…"
        : connected ? "\(AgentStatus.shared.displayName) is connected"
        : "Connect your agent"
    }
}

/// "Connect agent": copyable orientation prompt pointing any coding agent at the
/// local MCP server (ADR 0008). The server self-describes via tools/list schemas;
/// this prompt is just the address and etiquette. Once an agent has done
/// something, it becomes that agent's activity log instead.
struct AgentConnectPopover: View {
    @State private var copied = false

    private var prompt: String { MCPServer.onboardingPrompt }

    var body: some View {
        Group {
            // Connected is what flips the popover, not activity: a connected
            // agent that hasn't acted yet should not be pitched the setup.
            if AgentStatus.shared.actions.isEmpty && !AgentStatus.shared.isConnected {
                connectContent
            } else {
                historyContent
            }
        }
        // One fixed size for every state: animated popover resizes crash NSPopover.
        .frame(width: 340, height: 312)
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
                    if AgentStatus.shared.actions.isEmpty {
                        Text("Connected. Activity will appear here")
                            .font(Theme.ui(11))
                            .foregroundStyle(Theme.ink3)
                    }
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
            Text("Paste this into any MCP-capable agent (Claude Code, Cursor, whatever you run) and it can see, edit, and export your photos, live in this window. It will confirm once connected.")
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
