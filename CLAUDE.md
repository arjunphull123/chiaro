# Darkroom

A native macOS RAW photo editor. Simple, sleek, fast — Lightroom-grade RAW editing
without the subscription. Built for a Sony RX100 IV (.arw) workflow but camera-agnostic
via Apple's RAW engine.

## Stack

- Swift + SwiftUI (macOS 14+)
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

## Roadmap

See `docs/ROADMAP.md`. Current phase: scaffolding / pre-build.
