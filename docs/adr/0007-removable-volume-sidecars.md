# ADR 0007: Sidecars for removable volumes live in Application Support

**Status:** Accepted · 2026-08-18 · Amends ADR 0002

## Context

The primary workflow is editing straight off the plugged-in camera card — no import
step. Writing sidecars beside originals (ADR 0002) would litter the card, break when
the card is locked, and lose edits when the card is reformatted.

## Decision

Sidecar location is volume-aware:

- Local, writable volumes: beside the original (`DSC04002.chiaro.json`), as before.
- Removable, ejectable, or read-only volumes: in
  `~/Library/Application Support/Chiaro/Sidecars/`, named
  `<sha256(path) prefix>-<name>.chiaro.json` so identical filenames from different
  cards can't collide.
- Reads check both locations; writes fall back to Application Support on failure.
- EditState decodes tolerantly (missing keys → neutral), so sidecars survive schema
  growth across versions.
- Exports from removable volumes default to `~/Pictures/Chiaro Exports/`.

## Amendment · 2026-08-27: cloud-synced folders keep edits on the Mac too

A OneDrive, Dropbox, Google Drive, Box or iCloud Drive folder passes the
volume test above (it is a local, writable folder), so a beside-file there
synced to everyone the folder is shared with. Folders under
`~/Library/CloudStorage/` (where macOS mounts third-party providers) and
`~/Library/Mobile Documents/` (iCloud Drive) now use the Application Support
store as cards do. `isUbiquitousItem` is deliberately not consulted: with
Desktop & Documents syncing on it would move every `~/Documents` edit off the
photo for a folder nobody else sees.

Two rules follow. In these folders Chiaro reads only its own store: a
beside-file there was not written by this Mac, and reading it would show
someone else's edits that a revert could never clear (revert deletes what
Chiaro wrote, and nothing else). Edits on a shared folder are therefore per
Mac, which is the point; an import step was considered and rejected, since the
problem is where one small file goes, not where the photos are.

## Consequences

- Card edits survive ejects and reformats, but are keyed to the card's mount path —
  a renamed volume orphans its stored sidecars. Acceptable for v0.1.
- Sidecar debounce holds a latency-critical ProcessInfo activity: App Nap otherwise
  defers timer wakeups indefinitely while backgrounded (found live: MCP-driven edits
  never persisted until app quit).
