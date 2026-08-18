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
  Light / Color / Portrait / Effects / Detail. Liquid Glass filmstrip pill and floating
  tool palette overlay the photo and fade when idle; filmstrip and tool palette share one
  GlassEffectContainer. Esc returns to Library.

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
- Typography: **Geist** for UI chrome (11–13pt controls, wordmark); **Geist Mono** for
  every numeral — slider values, ƒ-stops, EXIF, histogram labels — with tabular figures.
  Both bundled in-app (SIL OFL 1.1).

## Controls

- **Scrub-on-photo is primary** (ADR 0005): arming a parameter turns the canvas into
  its control surface — horizontal drag or trackpad scroll adjusts it, with a floating
  glass readout (name, value, scale). Tracking is strictly 1:1 with the gesture; haptic
  detents at full stops and zero-crossings.
- Sliders: thin track, amber fill from the neutral default point, scrubbable numeric
  value at right; hover + scroll adjusts; double-click resets to default.
- Before/after: hold `\` (press-and-hold, like Lightroom).
- Filmstrip thumbs: amber border = selected; small amber dot = has edits.
- Ratings: 1–5 keys in Library and Edit.

## Feel

- Every preview update renders live via Metal — no "processing" spinners on sliders.
- Animations: fast and few (view transitions ~150ms ease-out); no bounces.
- No modal dialogs for editing operations; export is a sheet.
