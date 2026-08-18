# ADR 0004: Liquid Glass for transient controls only; macOS 26 target

**Status:** Accepted · 2026-08-18 · Rail opacity amended by ADR 0006

## Context

macOS 26 (Tahoe) ships Liquid Glass with native SwiftUI APIs: `glassEffect()`,
`GlassEffectContainer` (merge/morph between glass elements), and tinted variants.
Glass samples the content beneath it, so its tint shifts with the photo — fine for
transient controls, harmful under surfaces used to judge color (histogram, sliders).
Design studies of three directions were rendered with real session frames; the
hybrid direction was chosen.

## Decision

Raise the deployment target to macOS 26. Material rule for all UI:

- **Graphite (opaque `#232326`) for anything you judge color against**: the right
  rail (histogram + adjustments), export sheet content, library chrome.
- **Liquid Glass for what comes and goes**: filmstrip pill, floating tool palette,
  toasts. These float over the edge-to-edge photo and fade when idle.
- Filmstrip and tool palette live in one `GlassEffectContainer` so they merge/morph.
- Active states on glass use tinted glass with safelight amber.
- Never glass-on-glass; never glass for large static panels.

## Consequences

- App requires macOS 26+. Acceptable: the target machine runs Tahoe.
- Edit canvas is edge-to-edge photo (no letterbox padding) since transients overlay it.
- No third-party UI libraries needed; Pow (micro-animations) may be considered later
  via its own ADR if wanted.
