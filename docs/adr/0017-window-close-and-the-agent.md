# ADR 0017: Closing the window quits, unless an agent is working

**Status:** Accepted · 2026-08-25

## Context
Chiaro is a single-window app (ADR 0004's one library, one window). On the
Mac, single-window apps quit when their window closes; document apps and
long-running utilities stay in the Dock. Chiaro is the former for a person and
the latter for an agent: the MCP server (ADR 0008) lives inside the app
process, so quitting on close would cut off an agent mid-edit because the
photographer tidied their screen.

The transport is stateless HTTP, so there is no disconnect event to consult.
`AgentStatus` records when the last request arrived; `isActive()` is a
ten-minute recency window over that.

## Decision
`applicationShouldTerminateAfterLastWindowClosed` returns true unless an agent
has been active, by that window. When it returns false the app runs headless
with the server up, and a once-a-minute check quits it as soon as the agent
has been quiet for the same window, so a Chiaro nobody is using never lingers
in the Dock. A Dock click or `open -a Chiaro` brings the window back with the
library state the agent left.

The recency window is the same constant the status strip uses for "active",
so the app never quits under an agent it is still showing as working, and
never stays up for one it shows as gone.

## Consequences
- Closing the window is the ordinary quit gesture for a person; Cmd-Q remains
  the unconditional one, and quits even under a live agent (edits are saved
  in `applicationWillTerminate`).
- An agent that pauses for longer than the window loses the app and must
  relaunch it; `open -a Chiaro` from the shell is the recovery, and the
  discovery file at `~/.chiaro/mcp.json` reappears with it.
- A headless Chiaro keeps its Dock icon, so the user can always see it is
  running and quit it themselves.
