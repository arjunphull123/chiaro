# ADR 0009: Native Claude chat panel via Agent SDK sidecar

**Status:** Accepted direction · 2026-08-18 · Amends ADR 0008 (embedded agent now planned)

## Context

ADR 0008 chose MCP-only, no embedded agent. That proved the concept: agents drive
Chiaro well. The next step is a chat panel inside Chiaro — a native drawer right of
the edit rail — funneling Claude through the same MCP tools, so the user converses
in-app and watches edits land live.

Research findings (verified against official docs, 2026-08):

- **No Swift SDK.** Agent SDK ships for Python and TypeScript; the supported pattern
  for native apps is a sidecar process (or driving `claude` CLI headless). The SDK
  sidecar (`ClaudeSDKClient`) is the robust choice for long-lived multi-turn chat;
  headless CLI (`claude -p`) is stateless per invocation (`--resume <session_id>`
  exists but is clunkier).
- **Auth: subscription OAuth is NOT available.** Headless/SDK contexts never read
  claude.ai OAuth credentials, and Anthropic explicitly disallows third parties
  offering claude.ai login for products built on the SDK. The panel must use an
  `ANTHROPIC_API_KEY` the user supplies.
- **Usage**: result messages carry `total_cost_usd` (+ per-model breakdown) —
  client-side estimates. Surface per-turn cost in the panel.
- **Model**: `model` option / `--model` with aliases (fable/opus/sonnet/haiku) —
  expose a model picker.
- **MCP attachment**: pass our server inline (`{"mcpServers":{"chiaro":{"type":"http",
  "url":"http://127.0.0.1:<port>/mcp"}}}`); pre-approve tools via
  `allowed_tools: ["mcp__chiaro__*"]` — no permission prompts in an embedded panel.
- **Errors to handle**: `rate_limit` (429), `overloaded` (529), `authentication_failed`,
  `billing_error`; CLI auto-retries up to 10 times, never mid-stream.

## Decision

Build the panel as: SwiftUI chat drawer ⇄ local Node sidecar running the TypeScript
Agent SDK ⇄ Claude API, with Chiaro's MCP server attached and all `mcp__chiaro__*`
tools pre-allowed. API key entered by the user, stored in the Keychain. Panel shows
streaming text, tool-call activity (mirroring the rail's agent pill), per-turn cost,
and a model picker. Errors surface as inline chat states with retry.

## Consequences

- Requires Node present (bundle a minimal runtime later if this ever ships).
- The "bring your own API key" step is real onboarding friction — unavoidable per
  Anthropic policy; the Connect Agent prompt remains the zero-setup alternative for
  people already running Claude Code.
- The MCP layer stays the single integration surface: the panel is just another client.
