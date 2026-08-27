# Roadmap

## Status

Feature phase complete (2026-08-19). Tiers 1 and 2 shipped; Tier 3 is the MCP
surface, which is built. ADRs current through 0016.

Everything below is the record of what got built and — as usefully — what got
cut and why.

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

## Tier 4 — Grading (shipped, ADR 0015)

Both were found by auditing the render pipeline while writing the editing
skill, not by feature comparison.

- [x] Colour grading by tonal zone: shadow/mid/highlight hue and strength plus
      balance, as scalar rail rows rather than wheels, since a wheel is a
      two-dimensional control and ADR 0005 committed to one value at a time
- [x] Monochrome mixer: converts using the colour mixer's per-band luminance as
      channel weights, which the old pipeline order made unreachable
- [x] RAW decode parameters: `CIRAWFilter` already exposes `detailAmount`,
      `moireReductionAmount` and split luminance/colour noise reduction, and we
      set none of them. Decode-time detail and noise handling beats the
      post-demosaic filters we ship today, and moiré is unfixable afterwards.
      Design: `sharpness` and `noiseReduction` stay the only controls a user
      sees and route to the decode-time parameters for RAW files, rather than
      adding a parallel set — one set of controls implemented at the right point
      is what Lightroom and Capture One do. Colour noise reduction and moiré
      reduction are added as RAW-only rows, hidden for JPEGs. Accepted cost: an
      existing sidecar's `sharpness` on a RAW file renders slightly differently
      afterwards, since decode-time detail is a different operation and not
      merely a better one. Taken deliberately while pre-1.0, because the
      alternative is six overlapping detail controls forever

## Backlog (post-1.0)

Ranked, with the reasoning that put them here rather than in a tier.

- **Luminance-range masking on existing locals — shipped.** Two scalars
  (`lumaLow`/`lumaHigh`) added to a local, so "only the shadows inside this
  radial" is expressible. Composed with the masks already built instead of
  adding a concept, and stays agent-drivable.
- **Grain — shipped.** `grain` and `grainSize` in Effects. The missing piece
  for a film look; the skill no longer has to admit it cannot deliver one.
- **`chiaro` CLI.** A thin client of the same localhost server the app already
  runs — same EditState, live rendering when the window is open. MCP stays the
  session surface (presence, typed schemas, in-band previews, agents without a
  shell); the CLI is the throughput surface: dependent calls chain in one shell
  invocation and a whole shoot batches in one loop, where MCP costs a model
  turn per call. Deliberately not in 1.0 — the launch story is MCP.
- **Thumbnail virtualization.** `Library.loadThumbnails()` decodes every
  photo up front and `Photo.thumbnail` never evicts, so a 5,000-photo folder
  holds several GB. The justified gallery needs every aspect ratio before it
  can lay out rows, which is why plain laziness does not work. Plan: read
  aspect from image metadata only (`CGImageSourceCopyProperties`, no decode,
  milliseconds per file) so layout is complete immediately; decode thumbnails
  only for rows near the viewport, with a bounded LRU (~500 resident) and
  eviction. Held out of 1.0 because it touches the gallery the product shots
  depend on, days before launch, and needs testing on a real large folder.
- **Accessibility.** VoiceOver labels on icon-only buttons (cheap, an hour)
  and a decision on Dynamic Type against the fixed-width rail and toolbar.
- **Healing and clone.** Wanted by every photographer, and a real gap. Note
  ADR 0012 already cut generative inpainting on quality evidence, so this means
  classical patch-based healing, not a model.
- **Share pixel-statistics primitives between AutoEnhance and StatsSampler —
  shipped (`PixelStats`).** Both walked pixels to compute percentiles, clip
  fractions, saturation means and a gray-world average, with constants that
  had already diverged: 96x96 sRGB versus full-resolution Display P3, clip
  thresholds of 0.98/0.02 versus 254/255, and different neutral-pool gates.
  Nothing cross-checked one against the other, which is precisely why the
  inverted white balance in `temp` survived from the first commit until
  `f19516d`. Full unification was skipped, since AutoEnhance needs a fast
  downsample for interactive latency, but the percentile helper and the clip
  and saturation predicates are now one implementation with one set of
  constants.
- **Re-tune AutoEnhance's `temp` strength.** Its multiplier and clamp were
  hand-tuned while the pipeline rendered temperature backwards, so they have
  never been validated under the correct sign. Note the clamps are load-bearing
  rather than a backstop: unclamped the formula reaches about ±67 against a
  clamp of ±20, and a 5% channel imbalance already asks for half the maximum
  correction, so do not raise the multiplier without rechecking where the clamp
  bites.
- **Move the grading kernel off Core Image Kernel Language — shipped
  (`ColorGradeCube`).** `CIColorKernel(source:)` had been deprecated since
  macOS 10.14 and failed *silently*: a source typo returned nil, and grading
  shipped as a permanent no-op because of exactly that. The fix is a computed
  `CIColorCube`, matching what `HSLCube` already does, since zone grading is a
  pure function of RGB and expresses fine as a 3D LUT.

Considered and deliberately not planned:

- **Freehand brush masks.** A painted mask is a raster, so it either bloats the
  sidecar with base64 or breaks ADR 0002's one-readable-file model. It is also
  the least agent-authorable control in photography, which cuts directly
  against what this app is for. Would need an ADR overturning 0002.
- **Per-channel RGB curves.** Duplicates Tier 4's zone grading with a
  two-dimensional control per channel, and would mean maintaining two grading
  systems.
- **Camera calibration profiles.** Apple's RAW engine exposes no colour-matrix
  override, so there is nothing to build against.
