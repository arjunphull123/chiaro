# ADR 0005: Scrub-on-photo is the primary editing interaction

**Status:** Accepted · 2026-08-18

## Context

Slider-only editing keeps eyes on the rail, not the photo. A live interaction study
(drag-to-adjust background blur with a floating glass readout) validated a
gesture-first model.

## Decision

Selecting a parameter arms the photo canvas as its control surface. Every parameter
is adjustable three ways, all writing to the same EditState:

1. **Scrub the photo** (primary): horizontal drag or trackpad scroll over the canvas
   adjusts the armed parameter; a floating glass readout shows name + value + scale.
2. **Rail slider** (precise): drag, or hover + scroll.
3. **Arrow keys** (nudge; Shift = coarse).

Requirements:

- **1:1 tracking.** The value indicator follows the gesture directly — no easing,
  smoothing, or acceleration between finger and readout. Render latency budget is
  one frame.
- Haptic detents (`NSHapticFeedbackManager`) at meaningful stops: whole f-stops for
  blur, zero-crossings for bipolar sliders.
- The armed parameter must always be visibly indicated (readout + highlighted rail row).
- Scrub sensitivity is fixed per parameter range, not velocity-adaptive.

## Consequences

- Canvas gesture handling and crop/pan gestures must not conflict: scrubbing only
  while a parameter is armed; Esc or clicking the photo disarms.
- The readout is another EditState observer — no special data path.
