# Changelog

All notable changes to this project are documented in this file. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

First release.

### Added

- **Editing.** Real RAW decode through Apple's engine, rendered live on the
  GPU with Metal-backed Core Image. Light and color: exposure, contrast,
  highlights, shadows, whites, blacks, temperature, tint, vibrance,
  saturation, a tone curve, and an eight-band color mixer. Color grading by
  tonal zone (shadow/mid/highlight hue and strength, plus balance) and a
  monochrome mixer weighted by the color mixer's luminance values. Portrait
  blur graded in real ƒ-stops from Vision subject masks, person masks, or a
  monocular depth map (Depth Anything V2, downloaded on demand) with a
  movable focus plane inspectable in a 3D scene. Local adjustments: radial,
  linear, and subject masks, each with luminance-range confinement. Detail:
  clarity, sharpening, noise reduction, vignette, and film grain with its own
  coarseness control; RAW files add decode-time color-noise and moiré
  reduction. Crop and straighten with aspect presets, an arc ruler, and a
  one-click headshot crop. Six built-in presets plus user-saved ones, and
  named versions. Adjustments are scrubbed directly on the photo, with a hold
  for before/after.
- **Library.** Folder-based, no import step. Camera cards read straight from
  the card. A justified gallery grouped by day, plus grid and sortable
  Finder-style list views. Filters, search, and starring to mark and cull
  keepers. Export to full-resolution JPEG, HEIF, or 16-bit TIFF with quality
  and sizing control.
- **Non-destructive sidecars.** Edits live in a small sidecar file beside each
  photo; the original is never written to. For camera cards, read-only or
  network volumes, and cloud-synced folders (OneDrive, Dropbox, Google Drive,
  iCloud Drive), the sidecar is kept on the Mac instead, in
  `~/Library/Application Support/Chiaro/Sidecars/`.
- **Agent surface.** An MCP server at `http://127.0.0.1:24242/mcp`, on
  whenever the app runs, with ten tools: `list_photos`, `get_edit`,
  `set_edit`, `get_stats`, `apply_preset`, `list_presets`, `set_starred`,
  `open_photo`, `get_preview`, and `export`. Chiaro serves its own editing
  skill over the MCP prompts primitive, so a connecting agent can fetch the
  working method, every control's range and traps, and look recipes. A
  status pill shows what a connected agent is doing while it works, and
  soft-locks manual input so the two of you aren't fighting the same slider.
- **Start screen.** A welcome card on first run; after that, the last edit as
  a hero card, recent edits, recent folders, and any mounted camera card.
- **Distribution.** A DMG installer, a Homebrew tap
  (`arjunphull123/tap/chiaro`), and an in-app check against GitHub releases
  that points you at the release page when a newer version is out.
