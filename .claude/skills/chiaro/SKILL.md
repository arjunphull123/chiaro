---
name: chiaro
description: Edit, grade, and cull photographs in Chiaro, a RAW editor that serves MCP from inside the app. Use when the user asks to edit, fix, grade, warm, brighten, crop, straighten, blur the background, convert to black and white, or export photos; when they name a photo or a RAW file (.arw, .dng, .cr3, .nef); when they ask for a look such as cinematic, film, moody, airy, punchy, or golden hour; or when they want a folder culled, rated, or batch edited.
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

**Stop after one refinement.** Two passes is a finished photo. Four passes is
mush, and you will not be able to tell which move did the damage.

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

**Flat and dull are different faults.** Flat is a tonal-range problem: the image
does not reach from black to white, and the fix is the black point and contrast.
Dull is a colour problem: the range is fine but the hues are lifeless, and the
fix is vibrance. Reaching for saturation on a flat photo is the single most
common way to produce something that looks like a preset. A photo can be both,
and then it needs both, in that order.

## The order of moves

Work in this order. It matches the order Chiaro's render pipeline applies
things, so your edits compose predictably instead of fighting each other:

1. White balance, `temp` and `tint`. Everything downstream assumes neutral.
2. `exposure`, to put the midtones roughly right.
3. Tone: `contrast`, `highlights`, `shadows`, `whites`, `blacks`.
4. `curve`, for finer contrast shaping than the sliders give.
5. Colour: `vibrance`, then `saturation`, then `hsl` per band.
6. `locals`, masked adjustments, once the global edit is settled.
7. Finishing: `clarity`, `noiseReduction`, `sharpness`, `vignette`.

Correct before you grade. A cast fixed after grading means the grade was built
on a lie.

## Never do these

Each of these has produced a bad photo in practice.

- **Never send more than four values in one `set_edit`.** You cannot attribute
  the damage.
- **Never set `contrast`, `clarity`, `vibrance` and `saturation` in the same
  pass.** All four increase apparent saturation. Choose one, occasionally two.
- **When shadows are too heavy, check three controls, not one.** `blacks`,
  `contrast`, and the curve's toe all pull the low end down. Easing one while
  the other two still crush is a wasted pass.
- **Once contrast and blacks are set, saturation rarely needs to exceed +20.**
  If contrast went up, saturation often needs to come down to compensate.
- **`clarity` is 0 on people.** +15 to +30 on landscape, architecture, and
  texture. Past about +35 it halos, and halos are the clearest sign of an
  over-processed photo.
- **Do not exceed 2 stops of `exposure`** without saying why. RAW tolerates
  about 3, and a JPEG about 2, before noise and banding take over.
- **Never apply a preset after refining.** `chiaro:apply_preset` overwrites
  `curve` and the whole `hsl` block. Preset first as a base, then refine.
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

Two systems do colour, and picking the right one matters. Grade **by tonal
zone** (`shadowHue`/`shadowStrength`, `midHue`/`midStrength`,
`highlightHue`/`highlightStrength`, `gradeBalance`) when the request names a
mood, since that is real split toning and preserves the colours already in the
frame. Use the **colour mixer** (`hsl`) when the request names an object, such
as foliage, skin, or a sky. Black and white is `monochrome: true`, never
`saturation: -100`.

Recipes are starting points keyed to a diagnosis, never destinations. Apply,
look, adjust to the photograph in front of you.

## Traps

Four behaviours that will fool you. Full detail in `references/controls.md`.

- **Setting `blurMode` does not turn blur on.** `blurF` defaults to 0, which is
  off. Set both, or nothing happens.
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
