# Looks

Starting points, not destinations. Every recipe below assumes you have already
corrected the photograph: white balance neutral, exposure right, no cast. A look
applied over an uncorrected frame amplifies the fault.

Apply, look at a preview of 1400px or more, then adjust to the photograph.

- [What Chiaro can and cannot grade](#what-chiaro-can-and-cannot-grade)
- [Cinematic](#cinematic)
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

A useful rule: if the request names a mood, grade by zone. If it names an
object, use the mixer.

## Cinematic

Teal in the shadows, warmth in the highlights, over a lifted matte black point
and a gentle S-curve. Two passes: tone, look, then the grade.

Tone first:

```json
{
  "contrast": 11,
  "shadows": 20,
  "blacks": 6,
  "highlights": -12,
  "curve": [[0, 0.02], [0.22, 0.25], [0.78, 0.82], [1, 1]]
}
```

Then the grade:

```json
{
  "shadowHue": 195, "shadowStrength": 30,
  "highlightHue": 35, "highlightStrength": 22
}
```

Strength is where taste lives. Around 20 to 35 reads as a quality of light.
Past about 50 the shadows read as cartoon teal and the viewer sees technique
instead of mood. Move `gradeBalance` negative to pull the crossover down so
only the deepest tones take the cool cast.

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

There is no grain and no halation in Chiaro, so do not promise either.

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
then it reads as blown out rather than luminous.

## Punchy

Contrast first, vibrance second, clarity only if the subject has texture worth
having.

```json
{"contrast": 16, "blacks": -6, "vibrance": 18}
```

On landscape or architecture, add `clarity` between 15 and 30. On people, leave
clarity at 0, because it draws every pore and line.

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
selects it; darkening a white sky needs a linear local adjustment across the
horizon, not the mixer. And grading still applies in monochrome, so adding a
warm highlight tint or a cool shadow tint gives you toned black and white:
sepia and selenium are a grade away, not a separate feature.

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
