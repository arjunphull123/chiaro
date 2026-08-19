# Roadmap

## Ship list (v1.0, beyond features — owner's list, 2026-08-19)

Features done → bug sweep → ADRs current → app icon → landing page
(chiaro.arjunphull.dev) → repo polish → open-source decision + monetization
framing → distribution (Sparkle/Homebrew/notarization) → LinkedIn launch post
("agent-native" framing) → competitive positioning check.
Culling flow: cut from the feature queue by owner decision.

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

## Tier 3 — AI via MCP (ADR 0008: no embedded agent)

- [x] Local MCP server: list_photos, get_edit, set_edit (live in UI), open_photo,
      get_preview, export · discovery at ~/.chiaro/mcp.json · repo .mcp.json
- [x] Agent presence pill + soft input lock while an agent edits
- [x] Portrait mask refinement (Mask slider: grow/shrink subject boundary)
- Generative remove / inpainting via pluggable provider layer
- Auto-culling (blink/focus detection, best-of-burst)
