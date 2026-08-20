# Roadmap

## Ship list (v1.0, beyond features — owner's list, 2026-08-19)

Feature phase declared complete 2026-08-19 (owner).
Done: bug sweep (2026-08-19: 20 findings fixed, including sidecar hsl/locals
decode data loss) · ADRs current through 0014 · open-source decision (GPL-3.0,
2026-08-19) · repo polish (LICENSE, README with screenshots) · distribution
decided and built (ADR 0014: ad-hoc signing + personal Homebrew tap + GitHub
Releases update check; no Sparkle) · dist rebuilt at 1.0.0 with the new icon.
Remaining: publish arjunphull123/chiaro + tag v1.0.0 + create the tap repo →
landing page (chiaro.arjunphull.dev) → LinkedIn launch post ("agent-native"
framing) → competitive positioning check.
Culling flow: cut from the feature queue by owner decision.

Decisions (2026-08-18): first build spans Tiers 1+2; AI features are designed-for but
deferred (ADR 0003); personal tool first — no signing/App Store constraints yet.

## Tier 1 — Core editor

- [x] Folder picker → justified gallery (embedded-preview thumbnails; RAW+JPEG pairs collapse to one)
- [x] Edit view: GPU live preview, RGB histogram, hold-\ before/after
- [x] Develop panel: exposure, contrast, highlights, shadows, whites, blacks,
      white balance (temp/tint), vibrance, saturation, clarity, sharpening,
      noise reduction, vignette
- [x] Crop + straighten
- [x] Sidecar persistence (ADR 0002), undo/redo
- [x] Copy/paste edits across photos (⌘⇧C / ⌘⇧V)
- [x] Export: JPEG / HEIF / 16-bit TIFF, full resolution, quality control

## Tier 2 — Differentiators

- [x] Portrait mode: Vision person segmentation → ƒ-stop background blur
- [x] Depth-map blur: Depth Anything V2 on-demand model, focus-plane slider (ADR 0010)
- [x] Subject relight
- [x] Scrub-on-photo editing with glass readout + haptic detents (ADR 0005)
- [x] Tone curve + HSL color mixer (8-band Color mix)
- [x] Presets: six built-ins + user-saved, MCP list/apply
- [x] Starred flag (replaced 0–5 ratings 2026-08-19; P key, library filters, MCP set_starred)
- [x] Library views: gallery / grid / Finder-style list (sortable columns), search,
      filename toggle, folder recursion + chips, card import to Chiaro Library
- [x] Onboarding tips (TipKit): scrub, fine-tune scroll, agent discovery
- [x] App icon (pinwheel mark) + scripts/bundle.sh → Chiaro.app
- [x] Local adjustments: radial, linear, subject masks with per-mask tonal controls

## Tier 3 — AI via MCP (ADR 0008: no embedded agent)

- [x] Local MCP server: list_photos, get_edit, set_edit (live in UI), open_photo,
      get_preview, export · discovery at ~/.chiaro/mcp.json · repo .mcp.json
- [x] Agent presence pill + soft input lock while an agent edits
- [x] Portrait mask refinement (Mask slider: grow/shrink subject boundary)
- Albums: cut by owner decision (2026-08-19)
- SAM-assisted focus selection: built, tested, cut — SAM 2.1 tiny masks weren't
  good enough (owner decision 2026-08-19)
- Clean up (LaMa inpainting): built, tested, cut — fills weren't shippable
  (owner decision 2026-08-19, ADR 0012). Cloud provider layer possible post-release.
  Positioning stands: AI-driven editing, not generative content
- Auto-culling: not an in-app feature — an agent workflow over MCP
  (get_preview + set_starred; agent picks the keepers)
