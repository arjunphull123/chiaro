# Looks

Starting points, not destinations. Every recipe below assumes you have already
corrected the photograph: white balance neutral, exposure right, no cast. A look
applied over an uncorrected frame amplifies the fault.

Apply, look at a preview of 1400px or more, then adjust to the photograph.

- [How Chiaro grades](#how-chiaro-grades)
- [Cinematic](#cinematic)
- [Overcast](#overcast)
- [Film](#film)
- [Moody](#moody)
- [Airy](#airy)
- [Punchy](#punchy)
- [Golden hour](#golden-hour)
- [Black and white](#black-and-white)
- [Signs you went too far](#signs-you-went-too-far)

## How Chiaro grades

Two independent systems, and choosing the right one is most of the skill:

**By tonal zone**, which is the grading section: `shadowHue` and
`shadowStrength`, `midHue` and `midStrength`, `highlightHue` and
`highlightStrength`, plus `gradeBalance` to move where shadows end and
highlights begin. Hues are degrees, 0 to 360. Strengths are 0 to 100 and
default to 0, so grading is inert until you ask for it.

This is real split toning: it adds a chroma shift at the luminance you target
while preserving both brightness and the pixel's own hue, so tinting the
shadows teal does not flatten a red awning into grey. Use it for mood.

**By hue band**, which is the colour mixer (`hsl`): eight bands, each with hue,
saturation and luminance. Use it when the target is a *thing* rather than a
tonal range, such as foliage, skin, or a sky.

**By tone within a region**, which is a local carrying `lumaLow`/`lumaHigh`. Use
it when the target is a tonal band inside part of the frame rather than across
all of it: the bright half of a sky, the shadow side of a building, a white
overcast sky that has no hue for the mixer to grab.

A useful rule: if the request names a mood, grade by zone. If it names an
object, use the mixer. If it names a place in the frame, use a local.

Equal strengths across zones are not equally visible. Midtones are most of a
photograph, so `midStrength` 30 reads strongly where `highlightStrength` 30 may
barely show on a frame with little bright area. Set each by eye.

## Cinematic

Teal in the shadows, warmth in the highlights, over a lifted matte black point
and a gentle S-curve. Two passes: tone, look, then the grade.

Tone first. The curve's lifted toe is the matte floor, so `blacks` stays out of
this: on a flat photo the contrast and curve set the floor, and adding a
`blacks` lift here fights that.

```json
{
  "contrast": 11,
  "shadows": 20,
  "highlights": -12,
  "curve": [[0, 0.02], [0.22, 0.25], [0.78, 0.82], [1, 1]]
}
```

Then the grade. `gradeBalance` is part of the recipe, not an optional refinement:

```json
{
  "shadowHue": 195, "shadowStrength": 28,
  "highlightHue": 35, "highlightStrength": 20,
  "gradeBalance": -25
}
```

**Set `gradeBalance` from the subject, before you look.** Start at -25 whenever
broad evenly-lit mid-tone surfaces dominate the frame: architecture, overcast
scenes, snow, a pale wall behind a subject. Those frames have a lot of pixels
sitting in the middle of the range, and at 0 the shadow tint reaches them and
casts the whole photograph. Leave it at 0 only for genuinely high-contrast
frames with real darkness in them, such as a night street or a lit subject in a
dark room.

Strength is where taste lives. Around 15 to 30 reads as a quality of light.
Past about 50 the shadows read as cartoon teal and the viewer sees technique
instead of mood.

**When this look is wrong.** Teal and orange exists to separate a warm subject
from a cool surround, which is why it flatters skin at dusk. On a flat overcast
scene with no warm subject there is nothing for the warmth to land on, and all
the grade can do is cool the greys. Say so and offer the alternative below
rather than delivering a joyless teal version of a grey day.

## Overcast

For a grey day: give it the light it lacked instead of a mood it never had.
Warmth goes in the highlights only, the shadows stay honest, and the colour
already in the frame does the work. This is usually the right answer for
European streets, architecture under cloud, and anything shot in flat light.

Tone first, establishing a real floor since these frames are almost always
flat rather than dull:

```json
{"contrast": 12, "blacks": -8, "shadows": 15, "highlights": -10, "vibrance": 16}
```

Then warmth in the light, with the shadows left alone:

```json
{"highlightHue": 40, "highlightStrength": 18, "shadowStrength": 0}
```

If the frame has strong local colour, awnings, doors, foliage, bring those up
with the mixer rather than raising global saturation, which would also push the
grey.

## Film

Faded blacks, softened whites, slightly untrue colour. The app's Soft film
preset is a good base; this is the same idea by hand.

```json
{
  "contrast": -8,
  "saturation": -10,
  "temp": 6,
  "curve": [[0, 0.06], [0.25, 0.28], [0.75, 0.78], [1, 0.97]]
}
```

Then, optionally, a little colour infidelity, which is what actually reads as
film rather than as a vintage filter: greens toward olive, skin toward peach.

```json
{"hsl": {"green": {"h": -8, "s": -12}, "orange": {"h": 4}}}
```

Then grain, which is the part that actually reads as film rather than as a
filter. It is the last move, after everything else:

```json
{"grain": 22, "grainSize": 55}
```

Keep it under about 35. Grain is meant to be noticed at full size and invisible
in a thumbnail; past that it becomes the subject. There is no halation in
Chiaro, so do not promise that.

## Moody

Deep but never crushed. The mistake is confusing moody with underexposed.

```json
{
  "exposure": -0.3,
  "contrast": 8,
  "highlights": -25,
  "shadows": 10,
  "blacks": 4,
  "saturation": -12,
  "hsl": {"green": {"l": -20}, "blue": {"l": -15}}
}
```

Blacks go up, not down. Atmosphere comes from shadows that hold detail; pure
black just looks like a mistake. Keep skin out of the desaturation by leaving
`orange` alone.

## Airy

Bright, low contrast, nothing fully black.

```json
{
  "exposure": 0.25,
  "contrast": -6,
  "highlights": 10,
  "whites": 12,
  "shadows": 28,
  "blacks": 18,
  "clarity": -6,
  "curve": [[0, 0.08], [0.3, 0.4], [0.7, 0.78], [1, 1]]
}
```

Watch the whites: the look dies the moment highlights actually clip, because
then it reads as blown out rather than luminous. `get_stats` answers that
directly; a ceiling of more than two or three percent has gone too far.

The negative `clarity` here is the softening path and carries much of the look.

## Punchy

Contrast first, vibrance second, clarity only if the subject has texture worth
having.

```json
{"contrast": 16, "blacks": -6, "vibrance": 18}
```

On landscape or architecture, add `clarity` between 15 and 30. On people it goes
the other way: -8 to -20 softens skin while the eyes stay sharp. Zero is merely
neutral, and a face that was sharpened at decode usually wants less than that.

The app's Punch preset does this in one call. Prefer it when the user has not
asked for anything specific.

## Golden hour

Warmth in the light, not a wash over everything.

```json
{
  "temp": 16,
  "tint": 4,
  "highlights": -30,
  "blacks": 10,
  "vibrance": 14,
  "vignette": 10,
  "hsl": {"orange": {"h": 6, "s": -6}, "yellow": {"s": 10}}
}
```

That orange hue shift toward yellow with a slight saturation cut is what makes
skin glow instead of looking sunburnt. Pulling highlights down keeps warm
sunlight from turning into orange mush.

## Black and white

Set `monochrome: true`. Do NOT use `saturation: -100`, which throws away the
colour information the conversion needs.

Monochrome converts using the colour mixer's per-band **luminance** values as
channel weights, which is the darkroom control that matters: each original hue
becomes the grey value you choose for it. A blue sky darkens without touching
skin.

```json
{
  "monochrome": true,
  "contrast": 20,
  "whites": 10,
  "blacks": -8,
  "hsl": {"blue": {"l": -45}, "aqua": {"l": -35}, "orange": {"l": 15}}
}
```

Black and white tolerates harder contrast than colour, since there is no
saturation to blow out, so push further than you otherwise would.

Two things worth knowing. A neutral overcast sky has no chroma, so no band
selects it. Darkening a white sky wants a linear local across the horizon with a
luminance range on it, which catches the bright sky and leaves a dark roofline
alone in a way geometry by itself cannot:

```json
{"locals": [{"kind": "linear", "ax": 0.5, "ay": 0.0, "bx": 0.5, "by": 0.55,
             "feather": 60, "exposure": -0.7, "lumaLow": 55}]}
```

And grading still applies in monochrome, so a warm highlight tint or a cool
shadow tint gives you toned black and white: sepia and selenium are a grade
away, not a separate feature.

## Signs you went too far

Check these in a preview at 1400px or more before you report finished:

- A bright or dark rim along a high-contrast edge. That is a halo, from clarity
  or sharpening. Back off until it disappears.
- Texture everywhere, including in skies and out-of-focus areas. Nothing in the
  frame has a smooth gradient any more. That is the HDR look.
- Skin gone orange or red. Usually white balance rather than the colour mixer,
  so fix `temp` before touching `orange`.
- Shadows gone waxy and flat, from lifting them too far or over-applying noise
  reduction.
- Bands of flat colour in a sky, from pushing `blue` saturation too hard.

When any of these appear, the fix is to reduce the move that caused it, not to
add another move to compensate.
