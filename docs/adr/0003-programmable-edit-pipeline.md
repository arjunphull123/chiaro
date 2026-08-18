# ADR 0003: Every edit is programmatically drivable

**Status:** Accepted · 2026-08-18

## Context

The roadmap includes agentic editing: a chat where Claude inspects an image and sets
edit parameters via tool use ("make this a clean LinkedIn headshot"). Decision made
now (design for it, build later) because retrofitting is expensive.

## Decision

The UI never applies an edit directly. Sliders, curves, and masks all mutate a single
`EditState` value; the render pipeline observes it. `EditState` is `Codable`, with
documented ranges and neutral defaults for every parameter.

This makes the future AI layer a thin adapter: expose `EditState` mutations as a tool
schema, hand Claude a preview + histogram, and every AI edit lands on the same
inspectable, reversible sliders the user sees.

## Consequences

- Undo/redo is EditState snapshots. Presets are partial EditStates. Copy/paste,
  sidecars, and batch-apply all fall out of the same model.
- Discipline required: no rendering shortcuts that bypass EditState, even when a
  one-off `CIFilter` tweak would be quicker.
- No AI/API code in v1 — only this structural constraint.
