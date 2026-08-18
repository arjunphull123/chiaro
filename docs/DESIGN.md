# Design

Darkroom is a dark, quiet, photo-first Mac app. The chrome recedes; the photograph is
the interface. One signature color — safelight amber — marks what's active or edited.

## Structure

Two views, one window:

- **Library** — justified rows (photos keep aspect ratio, packed into even-height rows,
  portfolio-style). Toolbar: folder name, count, sort, thumbnail-size slider. Metadata
  appears on hover only. Double-click or ⏎ enters Edit.
- **Edit** — classic pro layout: photo edge-to-edge on the canvas, fixed right rail
  (histogram on top, then grouped adjustments: Light / Color / Effects / Detail),
  session filmstrip along the bottom. Esc returns to Library.

## Appearance

Always dark; ignores system light mode (neutral chrome keeps eyes calibrated to the
photo's colors).

- Canvas behind photos: `#1A1A1C`
- Panels / rails: `#232326`
- Hairline separators: white at 8%
- Primary text: white at 85% · secondary: white at 50%
- **Accent — safelight amber `#E8A33D`**: active slider fills, selection borders,
  edited badge, focused control. Used sparingly; never on large surfaces.
- Typography: SF Pro (system), 11–13pt controls; slider values in SF Mono.

## Controls

- Sliders: thin track, amber fill from the neutral default point, scrubbable numeric
  value at right; double-click resets to default.
- Before/after: hold `\` (press-and-hold, like Lightroom).
- Filmstrip thumbs: amber border = selected; small amber dot = has edits.
- Ratings: 1–5 keys in Library and Edit.

## Feel

- Every preview update renders live via Metal — no "processing" spinners on sliders.
- Animations: fast and few (view transitions ~150ms ease-out); no bounces.
- No modal dialogs for editing operations; export is a sheet.
