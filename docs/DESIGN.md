# Design

Chiaro is a dark, quiet, photo-first Mac app. The chrome recedes; the photograph is
the interface. One signature color — safelight amber — marks what's active or edited.

## Structure

Two views, one window:

- **Library** — justified rows (photos keep aspect ratio, packed into even-height rows,
  portfolio-style). Toolbar: folder name, count, sort, thumbnail-size slider. Metadata
  appears on hover only. Double-click or ⏎ enters Edit.
- **Edit** — photo fills the window; heavy-frost Liquid Glass right rail floats over it
  (ADR 0006): histogram on a solid graphite plate, then grouped adjustments:
  Light / Color / Portrait / Effects / Detail. The Liquid Glass nav pill and toolbar
  float over the photo. Esc returns to Library.

Material rule: **everything floats on glass except what you judge color against — the
histogram plate is solid, and rail frost is heavy enough to read as material, not photo.**

## Appearance

Always dark; ignores system light mode (neutral chrome keeps eyes calibrated to the
photo's colors).

- Canvas behind photos: `#1A1A1C`
- Panels / rails: `#232326`
- Hairline separators: white at 8%
- Primary text: white at 85% · secondary: white at 50%
- **Accent — safelight amber `#E8A33D`**: active slider fills, selection borders,
  edited badge, focused control. Used sparingly; never on large surfaces.
- Typography: **Fraunces** for the wordmark ("Chiaro", sentence case, never
  uppercase); **Archivo ExtraBold** for display headlines (the start-screen
  greeting, kerned -0.032em, matching the site's hero); **Geist** for all UI
  text; **Geist Mono** sparingly, for data only (values, ƒ-stops, EXIF, counts)
  with tabular figures. All bundled (SIL OFL 1.1).
- UI copy is sentence case with no trailing periods on labels and tips.
- Components live in DesignSystem.swift: AmberButtonStyle (one primary per surface),
  OutlineButtonStyle (secondary), GlassButtonStyle/GlassIconButtonStyle (canvas
  overlays), Chip (selectable pills).

## Controls

- **One slider in the app** (v3 interaction, refines ADR 0005): rail rows show name +
  value only. Clicking a row arms it — the canvas becomes its control surface and the
  single floating glass dial appears bottom-center (draggable, with detent ticks).
  Drag the photo, drag the dial, or scroll over the row: same EditState, strictly 1:1,
  haptic detents at full stops and zero-crossings. Double-click a row resets it.
- Top action cluster (glass, right of canvas): Copy Edits · Paste Edits (appears once
  something is copied) · Export. Library button top-left, clear of traffic lights.
- Library header (pinned frost): title + counts, continuous zoom slider (thumbnail
  size and days/months/years grouping share one value; trackpad pinch drives it too,
  haptic tick at each grouping change), Connect Agent, amber Export / Open Folder.
  Sections newest-first.
- Before/after: hold `\` (press-and-hold, like Lightroom).
- Starred: `P` toggles the flag in Library and Edit; the library filters by it.

## Feel

- Every preview update renders live via Metal — no "processing" spinners on sliders.
- Animations: fast and few (view transitions ~150ms ease-out); no bounces.
- No modal dialogs for editing operations; export is a sheet.
