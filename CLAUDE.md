# Chiaro

Named for the "light" half of chiaroscuro — composing with light against dark.

A native macOS RAW photo editor. Simple, sleek, fast — Lightroom-grade RAW editing
without the subscription. Built for a Sony RX100 IV (.arw) workflow but camera-agnostic
via Apple's RAW engine.

## Stack

- Swift + SwiftUI (macOS 26+; Liquid Glass per ADR 0004)
- Core Image (`CIRAWFilter`) for RAW decode, Metal-backed rendering
- Vision + Core ML for subject segmentation / depth (portrait blur, relight)
- Non-destructive: edits live in sidecar files next to originals; originals are never modified

## Conventions

- **Lean code.** Comments only for constraints the code can't express. No narration,
  no restating the obvious, no "this function does X" headers.
- **ADRs for architectural decisions.** Anything that shapes structure, dependencies,
  or data formats gets a numbered record in `docs/adr/`. Small implementation choices don't.
- **Every edit operation is a value in the `EditState` model** — serializable, diffable,
  programmatically settable. This is a hard rule: it keeps sidecar persistence, copy/paste
  edits, undo, and future agentic (Claude-driven) editing all trivial.
- Prefer Apple frameworks over dependencies. Justify any third-party package in an ADR.
- **No AI attribution anywhere.** No `Co-Authored-By` trailers, no "Generated with"
  lines in commits, PRs, code, or docs. Commits are authored by the repo owner, period.
- SwiftUI-first; drop to AppKit only where SwiftUI genuinely can't (and note why inline).
- **Typography roles:** Fraunces = headers/wordmark (sentence case, never uppercase);
  Geist = all UI text; Geist Mono = data only (values, EXIF, counts, timestamps).
- **UI copy:** sentence case, no trailing periods on labels/tips.
- **Buttons come from DesignSystem.swift** (Amber/Outline/Glass/GlassIcon styles, Chip);
  ad-hoc button chrome is a bug.

## MCP

While Chiaro runs it serves MCP at `http://127.0.0.1:24242/mcp` (ADR 0008; repo
`.mcp.json` preconfigures Claude Code; discovery at `~/.chiaro/mcp.json`). Tools:
list_photos, get_edit, set_edit (renders live if the photo is open), open_photo,
get_preview, export. Prefer driving the running app over spawning new instances.

## Dev harness

`swift run Chiaro -- --open <folder> [--edit <name>] [--snapshot <png>] [--export-test <name>]
[--quiet (no focus steal)] [--click <x> <y-from-top> [n]] [--show-tips] [--download-depth] [--render-icon <png>]`
`scripts/bundle.sh` builds dist/Chiaro.app (icns + Info.plist + ad-hoc signing).

## Roadmap

See `docs/ROADMAP.md`. Current phase: v0.1 shipped; next: crop, curves, presets, undo.
