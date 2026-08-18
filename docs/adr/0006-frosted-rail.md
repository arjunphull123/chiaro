# ADR 0006: Frosted glass rail

**Status:** Accepted · 2026-08-18 · Amends ADR 0004

## Context

ADR 0004 kept the adjustments rail opaque to avoid glass tint shifting with the photo
behind it. A material study showed heavy frost — ~72% graphite scrim over a ~30px
blur — makes the shift nearly imperceptible. And with scrub-on-photo as the primary
interaction (ADR 0005), the rail is more readout than instrument, lowering the
color-stability stakes further.

## Decision

The rail becomes heavy-frost Liquid Glass; the photo runs edge-to-edge underneath it.
Frost recipe: dark tint at high opacity over a strong blur — translucency should read
as material depth, not as photo content bleeding through.

Exception: **the histogram sits on a solid graphite backing plate** inside the rail.
It is the one surface where sampled tint could mislead.

ADR 0004's other rules stand: glass transients (filmstrip, tool palette) in one
GlassEffectContainer, amber-tinted active states, no glass-on-glass, macOS 26 target.

## Consequences

- One material language across rail and transients.
- Edit canvas is truly full-window; the rail floats over it.
- If real-world use shows tint interference while color grading, the escape hatch is
  raising scrim opacity — not reverting the layout.
