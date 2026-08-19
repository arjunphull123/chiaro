import SwiftUI


/// "Connect Agent": copyable orientation prompt pointing any coding agent at the
/// local MCP server (ADR 0008). The server self-describes via tools/list schemas;
/// this prompt is just the address and etiquette.
/// One pill at the top of the edit rail, cycling through the agent lifecycle:
/// "Connect Agent" → "<client> connected" → "🔒 Agent is editing…" (+ intent).
struct AgentRailStatus: View {
    let library: Library
    @State private var showing = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let editing = library.agentActive
            let connected = AgentStatus.shared.isConnected(now: context.date)
            let brand = AgentStatus.shared.brand
            let active = editing || connected
            Button {
                showing.toggle()
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        if active {
                            brand.icon.frame(width: 13, height: 13)
                        } else {
                            Image(systemName: "handshake")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.ink3)
                        }
                        Text(editing
                            ? "\(AgentStatus.shared.displayName) is editing…"
                            : connected ? "\(AgentStatus.shared.displayName) is connected" : "Connect Agent")
                            .font(Theme.ui(11.5, .medium))
                            .foregroundStyle(active ? Theme.ink : Theme.ink2)
                            .lineLimit(1)
                        Spacer()
                        if editing {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(brand.color)
                        } else if connected, let seen = AgentStatus.shared.lastSeenText(now: context.date) {
                            Text(seen).font(Theme.mono(8.5)).foregroundStyle(Theme.ink3)
                        }
                    }
                    if editing, let intent = library.agentIntent {
                        Text(intent)
                            .font(Theme.ui(10.5))
                            .foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(editing ? brand.color.opacity(0.12) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(active ? brand.color.opacity(0.45) : Theme.hairline)
                )
            }
            .buttonStyle(.plain)
            .clickCursor()
            .animation(.easeOut(duration: 0.2), value: editing)
        }
        .popover(isPresented: $showing, arrowEdge: .bottom) { AgentConnectPopover() }
    }
}

struct ConnectAgentButton: View {
    @State private var showing = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let connected = AgentStatus.shared.isConnected(now: context.date)
            let brand = AgentStatus.shared.brand
            Button {
                showing.toggle()
            } label: {
                HStack(spacing: 7) {
                    if connected {
                        brand.icon.frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "handshake")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.ink3)
                    }
                    Text(connected ? AgentStatus.shared.displayName + " is connected" : "Connect Agent")
                        .font(Theme.ui(12, .medium))
                }
                .foregroundStyle(connected ? Theme.ink : Theme.ink2)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(connected ? brand.color.opacity(0.45) : Theme.hairline)
                )
            }
            .buttonStyle(.plain)
            .clickCursor()
        }
        .popover(isPresented: $showing, arrowEdge: .bottom) { AgentConnectPopover() }
    }
}

struct AgentConnectPopover: View {
    @State private var copied = false

    private var prompt: String {
        let url = "http://127.0.0.1:\(MCPServer.shared.port == 0 ? MCPServer.preferredPort : MCPServer.shared.port)/mcp"
        return """
        Chiaro, a RAW photo editor, is running on this Mac with a local MCP server at \(url) \
        (streamable HTTP; discovery file at ~/.chiaro/mcp.json). Connect to it — with Claude Code: \
        `claude mcp add --transport http chiaro \(url)` — then call tools/list for the full schema.

        How to work: orient with list_photos; read a photo's settings with get_edit; LOOK at a photo \
        (rendered with its current edit) via get_preview before and after changes; adjust with \
        set_edit (send only the parameters you're changing, and include an `intent` string describing \
        what you're doing — it's shown to the user live in the app); open_photo displays a photo in \
        the editor so the user can watch; export writes the finished file. All edits are \
        non-destructive and render live. Iterate visually: edit, get_preview, judge, refine.
        """
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Drive Chiaro with any coding agent")
                .font(Theme.ui(14, .semibold))
                .foregroundStyle(Theme.ink)
            Text("Chiaro serves MCP while it runs. Paste this into Claude Code (or any MCP-capable agent) and it can see, edit, and export your photos — live in this window.")
                .font(Theme.ui(11.5))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(prompt)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.ink2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 150)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.3)))
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(prompt, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Text(copied ? "Copied ✓" : "Copy Prompt")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AmberButtonStyle())
        }
        .padding(18)
        .frame(width: 380)
        .background(Theme.ground)
    }
}
