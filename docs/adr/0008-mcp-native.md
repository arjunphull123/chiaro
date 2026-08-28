# ADR 0008: MCP-native; no embedded agent

**Status:** Accepted · 2026-08-18 · Supersedes the embedded-chat plan in ADR 0003 ·
Tool list amended 2026-08-23 · Origin check hardened 2026-08-25

## Context

ADR 0003 kept the door open for an in-app agentic editing chat. Meanwhile every
edit was already a programmatic EditState mutation, and coding agents (Claude Code
etc.) already speak MCP. Embedding an agent means owning API keys, a chat UI, and a
model choice; exposing MCP means any agent the user already runs can drive Chiaro.

## Decision

Chiaro ships an MCP server, on whenever the app runs:

- Streamable HTTP at `http://127.0.0.1:24242/mcp` (falls back to an ephemeral port);
  discovery file at `~/.chiaro/mcp.json`; repo `.mcp.json` preconfigures Claude Code.
- Tools: `list_photos`, `get_edit`, `set_edit`, `open_photo`, `get_preview` (rendered
  JPEG so agents can see their work), `export`.
  Amended 2026-08-23: the surface has grown to: `list_photos`, `get_edit`,
  `set_edit`, `set_starred`, `list_presets`, `apply_preset`, `open_photo`,
  `get_preview`, `get_stats`, `export`.
- Tool calls mutate the same EditState as every other input (ADR 0003). If the photo
  is open in the editor, agent edits render live in the UI.
- **Agent presence**: while set_edit/open_photo calls arrive, the edit view shows an
  "AGENT EDITING" glass pill and soft-locks manual input (clears 3 s after the last
  call) — the user watches, the agent drives, no fighting over the same sliders.
- No embedded chat, agent, or API keys in the app for now. Revisit only if MCP proves
  insufficient.

### Why HTTP and not stdio

The usual guidance is stdio for local servers, HTTP for remote. What actually
decides it is who owns the server process. With stdio the client spawns the
server as a child and talks over its pipes, which fits a tool the client starts
on demand: a filesystem server, a database wrapper, a CLI.

Chiaro inverts that ownership. The server is a GUI app the user launched, with
a window in front of them and a photo open, and the whole point is that the
agent edits that photo in that window. Under stdio, a client would spawn a
second Chiaro: not the window in use, a fresh instance with no folder open,
contending for the discovery file and the sidecar store. Avoiding that would
mean shipping a separate stdio shim that forwards to the running app over local
IPC, which is a socket with an extra hop and an extra binary to distribute. Two
clients would mean two subprocesses, neither of them the app.

Loopback HTTP makes the running app the server: one instance, the one holding
the user's photos, reachable by any number of clients by URL, with no knowledge
of where the app is installed and no coupling to how it was launched.

The cost is a listening port, which is why the server binds loopback only,
compares the Origin header by exact host, and caps request bodies. stdio would
have no network surface at all. That tradeoff is accepted here and documented
in SECURITY.md.

## Consequences

- "AI editing" costs Chiaro no model integration; capability rides on the user's agents.
- The server trusts localhost. Accepted for 1.0 as shipped: the listener binds
  loopback only, Origin is validated against 127.0.0.1/localhost (DNS-rebinding
  defense), and the surface holds no secrets — it reads and edits the photos of
  the user already at the keyboard. Authentication becomes required work only if
  the server ever binds beyond loopback.
  - **Amended 2026-08-25:** the Origin check was a substring match
    (`origin.contains("127.0.0.1")`), so an attacker-registered host such as
    `127.0.0.1.evil.com` passed it — a webpage the user merely visited could
    drive tools from the browser. Now the Origin's host is parsed and compared
    for exact equality against 127.0.0.1/::1/localhost. Request bodies are also
    capped (16 MB) and inspection-render dimensions clamped (4096 px) so no
    single call can exhaust memory. Verified live: a spoofed Origin returns 403.
- Sidecar writes triggered by background (MCP) edits must not rely on nappable timers
  (see ADR 0007).
