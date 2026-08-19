# ADR 0008: MCP-native; no embedded agent

**Status:** Accepted · 2026-08-18 · Supersedes the embedded-chat plan in ADR 0003

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
- Tool calls mutate the same EditState as every other input (ADR 0003). If the photo
  is open in the editor, agent edits render live in the UI.
- **Agent presence**: while set_edit/open_photo calls arrive, the edit view shows an
  "AGENT EDITING" glass pill and soft-locks manual input (clears 3 s after the last
  call) — the user watches, the agent drives, no fighting over the same sliders.
- No embedded chat, agent, or API keys in the app for now. Revisit only if MCP proves
  insufficient.

## Consequences

- "AI editing" costs Chiaro no model integration; capability rides on the user's agents.
- The server trusts localhost. Fine for a personal tool; authentication is required
  work before any public distribution.
- Sidecar writes triggered by background (MCP) edits must not rely on nappable timers
  (see ADR 0007).
