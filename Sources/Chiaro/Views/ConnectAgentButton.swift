import SwiftUI

/// "Connect Agent": copyable orientation prompt pointing any coding agent at the
/// local MCP server (ADR 0008). The server self-describes via tools/list schemas;
/// this prompt is just the address and etiquette.
struct ConnectAgentButton: View {
    @State private var showing = false
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
        Button {
            showing.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle().fill(Theme.amber).frame(width: 6, height: 6)
                Text("Connect Agent").font(Theme.ui(12, .medium))
            }
            .foregroundStyle(Theme.ink2)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing, arrowEdge: .bottom) { popover }
    }

    private var popover: some View {
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
