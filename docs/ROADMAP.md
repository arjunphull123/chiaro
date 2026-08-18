# Roadmap

Decisions (2026-08-18): first build spans Tiers 1+2; AI features are designed-for but
deferred (ADR 0003); personal tool first — no signing/App Store constraints yet.

## Tier 1 — Core editor

- [ ] Folder picker → gallery (fast thumbnails via embedded RAW previews, RAW/JPEG badges)
- [ ] Edit view: Metal-backed live preview, histogram, before/after toggle
- [ ] Develop panel: exposure, contrast, highlights, shadows, whites, blacks,
      white balance (temp/tint), vibrance, saturation, clarity, sharpening,
      noise reduction, vignette
- [ ] Crop + straighten
- [ ] Sidecar persistence (ADR 0002), undo/redo
- [ ] Copy/paste edits across photos
- [ ] Export: JPEG / HEIF / 16-bit TIFF, full resolution, quality control

## Tier 2 — Differentiators

- [ ] Portrait mode: subject segmentation + depth map → f-stop-style background blur
- [ ] Subject relight (adjust person independently of background)
- [ ] Tone curve + HSL color mixer
- [ ] Presets: built-in set + user-saved
- [ ] Star ratings / culling flow
- [ ] Local adjustments: radial, linear, AI-subject masks

## Tier 3 — AI (deferred, architecture ready per ADR 0003)

- Agentic editing chat (Claude API tool-use driving EditState)
- Generative remove / inpainting via pluggable provider layer
- Auto-culling (blink/focus detection, best-of-burst)
