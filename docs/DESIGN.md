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
- The start screen has two forms. **First run** (no folder ever opened, no
  edits; a mounted card does not count) is the share card as a fixed 640×560
  window, which is also the scene's default size so a first launch opens at
  it with no resize: Caravaggio's *The Calling of Saint Matthew*
  (public domain) darkened to the card's recipe and run under the title bar,
  the lockup, the site's hero line in Archivo, three rows (RAW editing, your
  photos stay put, your agent), Open folder as the one primary with Connect
  your agent beside it; the agent strip hides here. The one place the hero
  line appears inside the app, because whoever clicked the card should land
  on it. **Returning** is a 900-wide page whose height follows its content:
  wordmark where the library header keeps it, greeting, the last edit as a
  fixed 450×300 (3:2) hero on the left (a "No recent edits" placeholder in
  its frame until there is one); on the right, up to three more
  recents as 3:2 tiles, up to three sources (cards first), Open folder; a
  footer. Cards are cropped around Vision's salient region, never sized by
  the photo's aspect, and cached on disk so the screen is complete at launch.
  A reverted photo leaves the recents. Neither form is resizable; the window
  becomes resizable again once a folder opens. No artwork behind the
  returning page: the user's own photo is its hero.
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

## Known limitations at 1.0

Scope lines drawn on purpose for the launch, not omissions. Both are in the
roadmap backlog.

- **Accessibility.** Icon-only buttons carry no VoiceOver labels and the UI
  does not follow Dynamic Type. The layout is fixed-width by design (the rail,
  the toolbar), so Dynamic Type is a layout decision, not a flag.
- **Very large folders.** Every photo's 480px thumbnail is decoded when a
  folder opens and stays resident for the session, about 0.7 MB each. A
  folder of a few hundred photos is the designed case; several thousand works
  but takes minutes to fill in and holds gigabytes.
- **Cloud folders that are not downloaded.** iCloud Drive and OneDrive can
  keep files as placeholders until opened. Chiaro reads what is on disk; a
  photo that has not been downloaded shows no thumbnail until it is. Edits in
  cloud-synced folders stay on this Mac (ADR 0007) and are keyed to the
  folder's path, so renaming the folder leaves them behind.
