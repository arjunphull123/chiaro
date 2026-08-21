# Controls reference

Ranges, semantics, and the traps. Read this when you need a value's exact range,
when a control did not do what you expected, or when you are about to use
masks, blur, geometry, or the curve.

- [Ranges](#ranges)
- [Controls whose names mislead](#controls-whose-names-mislead)
- [Background blur](#background-blur)
- [The tone curve](#the-tone-curve)
- [The colour mixer](#the-colour-mixer)
- [Local adjustments](#local-adjustments)
- [Geometry](#geometry)
- [Presets](#presets)
- [Persistence and errors](#persistence-and-errors)

## Ranges

Every value is a field in one `EditState`. Out-of-range values are clamped,
except inside `locals` (see below).

| Control | Range | Default |
| --- | --- | --- |
| `exposure` | -3 to 3 | 0 (stops) |
| `contrast`, `highlights`, `shadows`, `whites`, `blacks` | -100 to 100 | 0 |
| `temp`, `tint` | -100 to 100 | 0 |
| `vibrance`, `saturation` | -100 to 100 | 0 |
| `clarity` | -100 to 100 | 0 |
| `vignette` | 0 to 100 | 0 |
| `sharpness`, `noiseReduction` | 0 to 100 | 0 |
| `blurF` | 0 to 1 | 0 (off) |
| `focusDepth` | 0 to 1 | 0.5 |
| `relight`, `maskReach` | -100 to 100 | 0 |
| `straighten` | -45 to 45 | 0 |
| `skewH`, `skewV` | -30 to 30 | 0 |
| `rotation` | 0, 90, 180, 270 | 0 |

`vibrance` protects colours that are already saturated and lifts the muted
ones, so it is the safer of the two on anything containing skin. `saturation`
moves everything equally.

## Controls whose names mislead

- **`blurF`** is a blur *amount* from 0 to 1, not an f-number. The app displays
  it as an aperture, where 0 reads as f16 (no blur) and 1 as f1.4 (maximum).
  Never write an f-number into it. Around 0.57 is what the UI calls f4.
- **`relight`** is not a relighting model. It is an exposure push confined to
  the subject mask, roughly 1.2 stops at full range.
- **`maskReach`** does not move anything. It grows or shrinks the subject mask
  itself before that mask is used for blur and relight.
- **`focusDepth`** is a one-sided plane, not a band. Everything nearer than the
  plane stays sharp; blur ramps in beyond it. 0 is nearest, 1 is farthest.
- **`skewV`** and **`skewH`** name the lines being corrected, verticals and
  horizontals, not the direction of the motion.

## Background blur

Three modes, and each one can fail differently:

- `subject` uses Vision's foreground instance mask. Works on people, animals,
  and objects with a clear figure-ground separation.
- `person` uses person segmentation. People only.
- `depth` uses a monocular depth model and blurs by distance from
  `focusDepth`. **Requires a roughly 50 MB model the user must download from
  the Portrait section of the app.** Nothing you can call triggers that
  download.

Two silent failures to guard against:

1. **`blurMode` alone does nothing.** `blurF` starts at 0. Send both, for
   example `{"blurMode": "person", "blurF": 0.57}`.
2. **A missing depth model does not error.** Depth mode falls back to subject
   blur silently. If the user wanted a focus plane, look at the result.

Vision returns no mask when it finds no clear foreground, or when the mask
covers under about 3% of the frame. Blur and relight then do nothing, and no
error is raised. Always confirm in a preview before reporting blur.

## The tone curve

`curve` is an array of `[x, y]` points, both 0 to 1, endpoints included, sorted
by x. The default is `[[0,0],[1,1]]`. One curve applies to all channels, so it
shapes contrast, not colour.

- **Steepen the middle for contrast**: `[[0,0],[0.25,0.2],[0.75,0.8],[1,1]]`
- **Lift the toe for a matte, film-like base**: start above zero, as in
  `[[0,0.05],[0.25,0.28],[0.75,0.8],[1,1]]`
- **The toe crushes shadows.** A point that maps 0.22 down to 0.17 is pulling
  the low end down as hard as a negative `blacks`. When you inherit a curve and
  the shadows are heavy, look here.

You send curve points as `[[x, y], ...]`, but `get_edit` returns them as
`[{"x": …, "y": …}, ...]`, which is also how the sidecar stores them. Same
data, two shapes; do not treat the difference as a mistake.

## The colour mixer

`hsl` takes a partial map of band names to `{h, s, l}`, each -100 to 100:

```json
{"hsl": {"orange": {"s": -30}, "blue": {"l": 20}}}
```

Bands and their hue centres: `red` 0, `orange` 30, `yellow` 60, `green` 120,
`aqua` 180, `blue` 240, `purple` 285, `magenta` 330.

Use it for hue-specific work: skin sits in `orange`, foliage in `green` and
`yellow`, skies in `blue` and `aqua`.

Because one shared curve and no per-zone tinting exist, this is the only route
to selective colour, and it selects by hue rather than by brightness. That
distinction is the main constraint on grading in Chiaro.

## Local adjustments

`locals` is an array. Sending it **replaces the whole array**; there is no
patch. `[]` clears all of them.

Coordinates are normalised 0 to 1 with y measured from the top.

- `kind: "radial"`, `ax`/`ay` the centre, `bx`/`by` the radii
- `kind: "linear"`, a gradient running from `a` (full effect) to `b` (none)
- `kind: "subject"`, uses the detected subject mask, no geometry needed

Each local carries `feather` 0 to 100, `invert`, and its own `exposure`,
`contrast`, `highlights`, `shadows`, `temp`, `tint`, `saturation`, `clarity`.

**Values inside `locals` are not clamped.** A local `exposure` of 40 will be
accepted and stored even though the sane range is -3 to 3. Stay inside the
documented ranges yourself, because nothing else will.

Reach for a local only when one global value cannot serve the whole frame: a
sky that needs to come down while the foreground stays put, a subject a stop
darker than its background, or shaping attention with a soft radial.

## Geometry

Applied in this order: flip, then 90° rotation, then skew, then straighten,
then crop. `straighten` auto-insets to the largest rectangle with no empty
corners, so a straighten alone loses a little frame.

`crop` is `{x, y, w, h}` normalised, y from the top. `w` and `h` must exceed
0.05.

Crops and rotations change composition, which is the photographer's decision.
Propose rather than apply unless asked directly.

## Presets

`apply_preset` carries tone and colour only: the light and colour sliders,
`clarity`, `vignette`, `sharpness`, `noiseReduction`, plus `curve` and `hsl`
wholesale. It never touches geometry, locals, or the portrait controls.

Because `curve` and `hsl` are overwritten wholesale, a preset applied after
manual colour work destroys that work. Preset first, refine second.

The built-ins, for reference:

| Preset | Values |
| --- | --- |
| Punch | contrast 18, vibrance 25, clarity 12, blacks -8 |
| Soft film | contrast -10, saturation -12, temp 6, lifted matte curve |
| Silver | saturation -100, contrast 15, whites 10, blacks -10, clarity 10 |
| Golden hour | temp 22, tint 4, vibrance 15, highlights -15, vignette 12 |
| Cool morning | temp -18, tint -2, contrast 8, saturation -8 |
| Portrait glow | temp 8, highlights -20, shadows 12, clarity -8, vibrance 10, sharpness 12 |

`list_presets` also returns the user's saved presets, mixed in with these and
not distinguishable in the response.

## Persistence and errors

Edits are non-destructive. Originals are never written. Each photo's state
lives in a sidecar JSON file beside it, or in application support when the
original sits on a camera card. Returning a photo to neutral, unstarred, with
no saved versions deletes its sidecar entirely, so a reset leaves no trace.

`reset: true` on `set_edit` starts from neutral and then applies the values in
the same call, which is the clean way to start over.

Saved versions are a UI feature. No tool can read or write them, so never offer
to snapshot a version.

Errors come back as a *successful* response carrying `isError: true` and a text
message. Check for it. The common ones: no photo by that name in the open
library, an unknown parameter, a crop smaller than 0.05, an unknown preset
name, and a curve with fewer than two points.
