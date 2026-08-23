# Chiaro v0.1 — Build Spec

> Historical document. This is the original v0.1 build spec, kept for the
> record; the current state of the app is described by `ROADMAP.md`,
> `DESIGN.md`, and the ADRs in `docs/adr/`. Where this file and those
> disagree, they win (ratings became a starred flag, and the edit surface
> has grown well past this table).

Native macOS 26 app, Swift 6 / SwiftUI, built with SPM (`swift run` for development,
`scripts/bundle.sh` assembles `Chiaro.app`). Everything below follows ADRs 0001–0006
and DESIGN.md.

## Module map

```
Sources/Chiaro/
  ChiaroApp.swift        @main App; window, activation, theme
  Theme.swift              colors, fonts, metrics (single source of design tokens)
  Models/
    EditState.swift        the whole edit, Codable (ADR 0003)
    Photo.swift            one photo: URL, thumbnail, rating, sidecar binding
    Library.swift          folder scan → [Photo]; observable app state
  Engine/
    RawEngine.swift        CIRAWFilter decode + preview cache
    RenderPipeline.swift   pure (CIImage, EditState) → CIImage
    PortraitEngine.swift   Vision person mask; blur + relight nodes
    HistogramSampler.swift CIAreaHistogram → [Float] bins
    Exporter.swift         full-res render → JPEG / HEIF / TIFF-16
  Persistence/
    Sidecar.swift          <name>.chiaro.json read/write, versioned
  Views/
    LibraryView.swift      justified rows, selection, ratings
    EditView.swift         canvas + rail + filmstrip composition
    CanvasView.swift       preview image, scrub gesture, readout overlay
    RailView.swift         frosted rail: histogram plate + slider sections
    Sliders.swift          DRSlider (track/fill/knob per DESIGN.md)
    FilmstripView.swift    glass pill, GlassEffectContainer
    ExportSheet.swift      format/quality/destination
```

## EditState (ADR 0003 — the contract)

All parameters `Double`, neutral default 0 unless noted. Serialized in the sidecar,
mutated by every input path, observed by the pipeline.

| group | param | range | notes |
|---|---|---|---|
| light | exposure | −3…+3 EV | CIExposureAdjust |
| light | contrast | −100…+100 | CIColorControls (mapped 0.6…1.4) |
| light | highlights | −100…+100 | CIHighlightShadowAdjust |
| light | shadows | −100…+100 | CIHighlightShadowAdjust |
| light | whites | −100…+100 | tone-curve top knee |
| light | blacks | −100…+100 | tone-curve bottom knee |
| color | temp | −100…+100 | CITemperatureAndTint around 6500K |
| color | tint | −100…+100 | 〃 |
| color | vibrance | −100…+100 | CIVibrance |
| color | saturation | −100…+100 | CIColorControls (mapped 0…2) |
| effects | clarity | −100…+100 | wide-radius unsharp mask |
| effects | vignette | 0…100 | CIVignette |
| detail | sharpness | 0…100 | CISharpenLuminance |
| detail | noiseReduction | 0…100 | CINoiseReduction |
| portrait | blurF | ƒ16…ƒ1.4 (stored 0…1) | masked variable blur; 0 = off |
| portrait | relight | −100…+100 | subject-masked exposure |
| meta | rating | 0…5 Int | |

Pipeline order (fixed): decode → temp/tint → exposure → highlights/shadows →
whites/blacks curve → contrast/saturation → vibrance → clarity → noiseReduction →
sharpness → portrait (mask blur + relight) → vignette.

## Sidecar (ADR 0002)

`DSC04002.ARW` → `DSC04002.chiaro.json`, `{ "version": 1, "edit": EditState }`.
Written debounced (500 ms) after any change; read at library scan. Missing/corrupt
sidecar ⇒ neutral EditState, never an error dialog.

## Rendering

- Decode once per photo via `CIRAWFilter` (extended-range linear output), downscale to
  ≤2048 px for the working preview; cache both. Adjustments re-render the preview
  through RenderPipeline on a background queue, coalescing to the latest EditState
  (drop intermediate frames, never queue them).
- Histogram recomputed from the rendered preview, 64 bins, luminance + RGB overlay.
- Export renders the full-resolution decode through the same pipeline —
  identical function, different input scale.

## Portrait engine

`VNGeneratePersonSegmentationRequest` (balanced) on the preview, mask cached per photo.
- **Blur ƒ**: background = inverted mask; `CIMaskedVariableBlur`, radius = t·16 px at
  preview scale (scaled proportionally at export).
- **Relight**: subject-masked `CIExposureAdjust` blend.
- No person detected ⇒ Portrait section shows "no subject found," controls disabled.

## Interactions (ADR 0005)

- Clicking a slider row arms its parameter; the canvas becomes its control surface:
  horizontal drag scrubs value with fixed per-param sensitivity, glass readout
  (name + value + scale) appears bottom-center. 1:1 tracking, no easing.
- Haptic detents (`NSHapticFeedbackManager`, `.alignment`) at whole f-stops and
  bipolar zero-crossings.
- Esc disarms → second Esc returns to Library.
- Hold `\` = original (before). ⌘C/⌘V on photos = copy/paste EditState.
- Ratings: keys 1–5, 0 clears. Arrow keys in filmstrip/library move selection.

## Materials & type (ADR 0004/0006, DESIGN.md)

- Rail: heavy-frost glass (dark tint at high opacity over blur); histogram on solid
  `#232326` plate. Filmstrip pill + readout: Liquid Glass via `glassEffect()`,
  sharing a `GlassEffectContainer` where they coexist.
- Geist (chrome) + Geist Mono (all numerals, tabular), bundled OTFs registered at
  launch via CTFontManager; system-font fallback if registration fails.
- Amber `#E8A33D` per DESIGN.md. Window is borderless-title (content under titlebar).

## Export

Sheet: format (JPEG / HEIF / TIFF-16), quality (JPEG/HEIF), destination folder.
Default: JPEG q0.92 → `<folder>/Chiaro Exports/<name>.jpg`. Color space Display P3.
Batch: exports every selected photo with its own sidecar edits.

## v0.1 cut line

**In:** everything above.
**Out (next):** crop/straighten, tone curve + HSL UI, presets, local masks beyond
portrait, depth-map blur (Depth Anything), agentic editing (ADR 0003 keeps the door open).

## Performance budgets

Library of 150 RAWs interactive < 2 s (embedded thumbnails only, no full decode).
First full decode of a photo ≤ 2 s; slider-to-preview ≤ 50 ms at 2048 px.
Memory: previews evicted LRU beyond ~12 photos.
