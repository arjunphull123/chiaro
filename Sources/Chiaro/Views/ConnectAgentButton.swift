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
                            Spacer(minLength: 0)
                            Image(systemName: "handshake")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.ink3)
                        }
                        Text(editing
                            ? "\(AgentStatus.shared.displayName) is editing…"
                            : connected ? "\(AgentStatus.shared.displayName) is connected" : "Connect your agent via MCP")
                            .font(Theme.ui(11.5, .medium))
                            .foregroundStyle(active ? Theme.ink : Theme.ink2)
                            .lineLimit(1)
                        Spacer(minLength: 0)
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
        You are being connected to Chiaro, a RAW photo editor running on this Mac. \
        It serves MCP at \(url) (streamable HTTP; discovery file at ~/.chiaro/mcp.json).

        1. Connect using your MCP support. Claude Code: `claude mcp add --transport http chiaro \(url)`. \
        Other agents: add an HTTP MCP server named "chiaro" with that URL to your MCP configuration.
        2. Confirm the connection by calling the list_photos tool — Chiaro shows you as \
        connected the moment your first request arrives.
        3. Then tell the user you are connected, briefly summarize what is in their library, \
        and ask what they would like to do.

        Working notes: get_edit reads a photo's settings. get_preview returns the photo rendered \
        with its current edit — look before and after every change. set_edit changes only the \
        parameters you send and accepts an `intent` string that is shown to the user live. \
        open_photo displays a photo in the editor so the user can watch. export writes the \
        finished file. All edits are non-destructive and render live.
        """
    }

    var body: some View {
        Group {
            if AgentStatus.shared.actions.isEmpty {
                connectContent
            } else {
                historyContent
            }
        }
        // One fixed size for every state: animated popover resizes crash NSPopover.
        .frame(width: 380, height: 370)
        .background(Theme.ground)
    }

    /// Once an agent has done things, the popover becomes its activity log.
    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(AgentStatus.shared.displayName) in Chiaro")
                .font(Theme.serif(16))
                .foregroundStyle(Theme.ink)
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
                promptBlock(scrollHeight: 96).padding(.top, 6)
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
                .font(Theme.serif(16))
                .foregroundStyle(Theme.ink)
            Text("Paste this into any MCP-capable agent — Claude Code, Cursor, whatever you run — and it can see, edit, and export your photos, live in this window. It will confirm once connected.")
                .font(Theme.ui(11.5))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            promptBlock(scrollHeight: 150)
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
                Text(copied ? "Copied ✓" : "Copy Prompt")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AmberButtonStyle())
            .clickCursor()
        }
    }
}
