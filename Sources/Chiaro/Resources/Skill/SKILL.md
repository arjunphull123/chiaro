---
name: chiaro
description: Edit, grade, and cull photographs in Chiaro, a RAW editor that serves MCP from inside the app. Use when the user asks to edit, fix, grade, warm, brighten, crop, straighten, blur the background, split tone, soften skin, add grain, convert to black and white, or export photos; when they name a photo or a RAW file (.arw, .dng, .cr3, .nef); when they ask for a look such as cinematic, film, moody, airy, punchy, or golden hour; or when they want a folder culled, rated, or batch edited.
argument-hint: [photo or folder and what you want done]
---

# Editing photographs in Chiaro

Chiaro renders live. When a photo is open in the editor, every value you set
appears on screen immediately, and the user is watching. Work like someone is
looking over your shoulder, because they are.

## Before anything

Call `chiaro:list_photos`. It reports the open folder, which photo is in the
editor, and for each photo whether it is RAW and whether it already has edits.

If the tool is not available, Chiaro is not running. Say so and ask the user to
launch it. Never guess at edit state, never describe a photo you have not
rendered, and never claim an edit landed that you did not verify.

## The loop

Follow this for every photo. It is short on purpose.

```
- [ ] open_photo, so the user can watch
- [ ] get_preview at maxDimension 1400
- [ ] get_stats, when the fault is tonal or a cast
- [ ] name the fault in words
- [ ] one set_edit, with intent filled in
- [ ] get_preview again at the same size
- [ ] one refinement at most, then stop
- [ ] report what you diagnosed and what you changed
```

Details that matter:

**Open the photo first.** `chiaro:open_photo` brings Chiaro to the front and
puts the photo in the editor, so the user sees the work happen. Editing a photo
that is not open does the work invisibly, which wastes the best thing about this
app. The exception is a batch pass over many frames, where opening each one
would thrash the window.

**Always pass `maxDimension: 1400` or more to `get_preview`.** The default is
768, which is too small to judge tone. Crushed shadows and haloed edges are
invisible at that size. This is not a style preference; a preview that small has
produced wrong calls in practice.

**Fill in `intent` on every `set_edit`.** It is shown live in the app while you
work. Write it as a photographer would: "lifting the shadows off the floor",
"warming the stone", not "setting shadows to 24".

**Measure before you guess, then look before you believe the measurement.**
`chiaro:get_stats` reads the rendered pixels and answers the questions your eye
is bad at: how much of each channel is railed at the ceiling or the floor, where
the luminance percentiles sit, and whether neutrals carry a cast. Use it to
settle "is this flat or is it dull", "am I clipping", and "is that warmth real or
am I imagining it".

It has one blind spot worth knowing, because it has caused a wrong call. Every
figure except the clipping percentages is a whole-image aggregate, and midtones
dominate any average. A control scoped to one tonal zone can be doing nothing at
all while the means barely move. When you are judging a highlight or shadow
control, look at two previews instead.

**Stop after one refinement.** Two passes is a finished photo. Four passes is
mush, and you will not be able to tell which move did the damage.

Two things do not count against that budget. A recipe with a documented tone
phase and grade phase spends two calls by design, so the refinement comes after
both. And correcting a result that is genuinely wrong, not merely improvable,
is always allowed: shipping a visible fault to respect a counting rule is the
wrong trade. What the budget forbids is polishing.

## Verify the diagnosis, obey the intent

A request usually contains both. "DSC03055 is flat and gray, give it a cinematic
grade" is a *claim about the fault* plus a *statement of intent*.

Treat them differently. The claim is a hypothesis: check it against the image,
because people are often right that something is wrong and wrong about what it
is. The intent is the photographer's call: honour it, and never apply a look
nobody asked for.

If the user's diagnosis is off, say so in one line and edit the real fault:
"The flatness is mostly a green cast rather than missing contrast, so I
neutralised that first."

## Diagnosis

Name the fault before you touch a control. These are the faults worth
distinguishing, because each has a different fix:

| What you see | The fault | The fix |
| --- | --- | --- |
| Everything darker than it should be | Underexposed | `exposure` |
| Full brightness range but no true black, muddy or gray | **Flat** | `blacks`, `contrast`, curve |
| Real blacks and whites, but lifeless colour | **Dull** | `vibrance`, then `saturation` |
| A colour tint through neutrals | Cast | `temp`, `tint` |
| Distant detail washed out, low contrast in broad areas | Haze | `contrast` plus a little `clarity` |
| Shadow detail gone, hard edge at the histogram floor | Crushed | Raise `blacks`, lower `contrast`, lift the curve toe |
| Highlight detail gone | Clipped | Not recoverable. Say so rather than fighting it |
| Grain and colour speckle in shadows | Noise | `noiseReduction`, sparingly |
| Skin reads harsh, every pore drawn | Over-sharp | Negative `clarity`, around -8 to -20 |

`get_stats` settles most of the top half of that table faster than looking does.
A clipping ceiling above a few percent names Clipped; a floor above a few percent
names Crushed; `p05` well off zero with `p95` well short of one names Flat; and
`neutralCast` pulling away from `grayWorld` names a Cast in the neutrals rather
than a genuinely coloured scene.

**Flat and dull are different faults.** Flat is a tonal-range problem: the image
does not reach from black to white, and the fix is the black point and contrast.
Dull is a colour problem: the range is fine but the hues are lifeless, and the
fix is vibrance. Reaching for saturation on a flat photo is the single most
common way to produce something that looks like a preset. A photo can be both,
and then it needs both, in that order.

**One apparent contradiction, resolved.** Fixing flatness means establishing a
black point, and `blacks` goes down to do it. Several looks then *lift* blacks
on purpose, for a matte film floor. Both are right, and the order settles it:
set the floor first while correcting, then let the look lift it if that is the
look. On a photo that is flat and being graded, do not do both with `blacks`;
correct with contrast and the curve, and let the recipe's curve carry the matte
lift.

## The order of moves

Work in this order. It matches the order Chiaro's render pipeline applies
things, so your edits compose predictably instead of fighting each other:

1. White balance, `temp` and `tint`. Everything downstream assumes neutral.
2. `exposure`, to put the midtones roughly right.
3. Tone: `contrast`, `highlights`, `shadows`, `whites`, `blacks`.
4. `curve`, for finer contrast shaping than the sliders give.
5. Colour: `vibrance`, then `saturation`, then `hsl` per band.
6. Grading by tonal zone, once the colour underneath is honest.
7. `locals`, masked adjustments, once the global edit is settled.
8. Finishing: `clarity`, `noiseReduction`, `sharpness`, `vignette`.
9. `grain`, last of all. It belongs to the print, not to the light.

Correct before you grade. A cast fixed after grading means the grade was built
on a lie.

## Never do these

Each of these has produced a bad photo in practice.

- **Never improvise more than four values in one `set_edit`.** You cannot
  attribute the damage. A named recipe from `references/looks.md` is one
  coherent unit and may be sent whole; the cap governs values you are guessing
  at, not a recipe you are following.
- **Never set `contrast`, `clarity`, `vibrance` and `saturation` in the same
  pass.** All four increase apparent saturation. Choose one, occasionally two.
- **When shadows are too heavy, check three controls, not one.** `blacks`,
  `contrast`, and the curve's toe all pull the low end down. Easing one while
  the other two still crush is a wasted pass.
- **Once contrast and blacks are set, saturation rarely needs to exceed +20.**
  If contrast went up, saturation often needs to come down to compensate.
- **`clarity` goes negative on people, not to zero.** +15 to +30 on landscape,
  architecture, and texture; past about +35 it halos, and halos are the clearest
  sign of an over-processed photo. On faces, -8 to -20 softens skin without
  losing the eyes, which is what the Portrait glow preset does. Zero is merely
  neutral, and a portrait that was sharpened at decode often needs less than
  neutral.
- **Grain is the last move, and it is subtle at useful strengths.** 15 to 35
  reads as film stock; past about 60 it reads as a filter. `grainSize` is
  coarseness, and it does nothing at all while `grain` is 0.
- **Do not exceed 2 stops of `exposure`** without saying why. RAW tolerates
  about 3, and a JPEG about 2, before noise and banding take over.
- **Never apply a preset after refining.** `chiaro:apply_preset` writes every
  carried parameter unconditionally: `curve`, the whole `hsl` block, all seven
  grading values, `grain`, and `monochrome`. Preset first as a base, then refine.
- **Never report blur you have not seen.** Background blur has two silent
  failure modes, below.
- **Never apply a look nobody asked for.**

## Looks

`chiaro:list_presets` and `chiaro:apply_preset` give you the app's own looks:
Punch, Soft film, Silver, Golden hour, Cool morning, Portrait glow. Prefer one
of these as a base when it fits the request, because the user recognises the
name from the UI, then refine from there.

For anything else, read `references/looks.md`, which has each look as a starting
point in Chiaro's actual controls.

Three systems do colour, and picking the right one is most of the skill. Grade
**by tonal zone** (`shadowHue`/`shadowStrength`, `midHue`/`midStrength`,
`highlightHue`/`highlightStrength`, `gradeBalance`) when the request names a
mood, since that is real split toning and preserves the colours already in the
frame. Use the **colour mixer** (`hsl`) when the request names an object, such
as foliage, skin, or a sky. Use a **local with a luminance range**
(`lumaLow`/`lumaHigh`) when the target is neither a mood nor a hue but a tonal
band inside one part of the frame, such as the bright half of a sky. Black and
white is `monochrome: true`, never `saturation: -100`.

All three zones grade, and they are not equally forceful at equal numbers.
Midtones cover most of a photograph's pixels, so `midStrength` at 30 shows far
more than `highlightStrength` at 30 on a frame with little bright area. Set
strength by what you see, not by matching numbers across zones.

Recipes are starting points keyed to a diagnosis, never destinations. Apply,
look, adjust to the photograph in front of you.

## Traps

Four behaviours that will fool you. Full detail in `references/controls.md`.

- **Choosing a blur mode turns blur on.** Setting `blurMode` when blur is off
  also lifts `blurF` to a default amount, the same way clicking the mode chip
  does in the app. Send `blurF: 0` to turn blur off, and set `blurF` yourself
  when you want a specific amount.
- **`colorNoiseReduction` and `moireReduction` are RAW-only** and are refused
  on anything else, since they exist only as decode parameters.
- **Depth blur degrades silently.** If the depth model is not downloaded,
  `blurMode: "depth"` falls back to ordinary subject blur with no error. If the
  user asked for a focus plane, verify in a preview and tell them to download
  the model from the Portrait section if it looks wrong.
- **Subject detection can find nothing** and then blur and relight are silent
  no-ops. Vision returns nothing when there is no clear foreground, or when the
  subject covers under about 3% of the frame. "I applied blur and nothing
  changed" has these two distinct causes; a preview tells you which.
- **Errors arrive inside successful responses.** Check for `isError` rather
  than assuming a call worked.

## Folders and culling

For a whole folder: `chiaro:list_photos`, then one `get_preview` per frame
before deciding anything. Do not open each one.

Culling: `chiaro:set_starred` marks keepers. Ask what the user is selecting for
before you rate anything, since "the good ones" means different things for a
portfolio and for a client gallery.

Batch grading: a shared look is fine, but exposure is per frame. Apply the look,
then correct each frame's exposure to its own histogram. A single exposure value
across a set is how batch edits announce themselves.

Export with `chiaro:export`. It writes to a `Chiaro Exports` folder beside the
originals and never overwrites. Originals are never modified; edits live in
sidecar files.

## Reporting back

Say what was wrong, what you did, and what you deliberately left alone. Two or
three sentences, in photographer language, no slider dumps.

Good:

> It was flat rather than dull: full of midtones with no real black anywhere. I
> set the black point and added a little contrast, then let the colour come up
> on its own with a touch of vibrance. Highlights on the white fountain were
> close to clipping, so I left them alone.

Bad:

> I applied exposure +0.10, contrast +18, blacks -10, whites +6, highlights
> -12, vibrance +22, saturation +4, clarity +10, temp +3, and a curve.

The second one is a changelog. The first tells the photographer what you saw.
