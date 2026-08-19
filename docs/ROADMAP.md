# Roadmap

Decisions (2026-08-18): first build spans Tiers 1+2; AI features are designed-for but
deferred (ADR 0003); personal tool first — no signing/App Store constraints yet.

## Tier 1 — Core editor

- [x] Folder picker → justified gallery (embedded-preview thumbnails; RAW+JPEG pairs collapse to one)
- [x] Edit view: GPU live preview, RGB histogram, hold-\ before/after
- [x] Develop panel: exposure, contrast, highlights, shadows, whites, blacks,
      white balance (temp/tint), vibrance, saturation, clarity, sharpening,
      noise reduction, vignette
- [ ] Crop + straighten
- [x] Sidecar persistence (ADR 0002) — undo/redo still open
- [x] Copy/paste edits across photos (⌘⇧C / ⌘⇧V)
- [x] Export: JPEG / HEIF / 16-bit TIFF, full resolution, quality control

## Tier 2 — Differentiators

- [x] Portrait mode: Vision person segmentation → ƒ-stop background blur (depth-map upgrade later)
- [x] Subject relight
- [x] Scrub-on-photo editing with glass readout + haptic detents (ADR 0005)
- [ ] Tone curve + HSL color mixer
- [ ] Presets: built-in set + user-saved
- [x] Star ratings (keys 0–5) — dedicated culling flow still open
- [ ] Local adjustments: radial, linear, AI-subject masks

## Tier 3 — AI (deferred, architecture ready per ADR 0003)

- Agentic editing chat (Claude API tool-use driving EditState)
- Generative remove / inpainting via pluggable provider layer
- Auto-culling (blink/focus detection, best-of-burst)
