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

## What Chiaro can and cannot grade

Chiaro selects colour **by hue band** through the colour mixer, and shapes
contrast through one curve that applies to all channels.

It has no split toning and no per-zone colour wheels, so you cannot tint the
shadows one colour and the highlights another. The canonical cinematic grade,
teal in the shadows and orange in the highlights, is defined by exactly that
move, so it can only be approximated here: push the hues that happen to live in
the dark parts of the frame, which at night and under overcast skies are
usually the blues and aquas, and warm the frame globally with `temp`.

Say this plainly when a user asks for a split-toned grade rather than pretending
the result is the same thing.

## Cinematic

The achievable version rests on three moves: a lifted matte black point, a
gentle S-curve, and hue separation between the warm and cool parts of the frame.

```json
{
  "contrast": 11,
  "shadows": 20,
  "blacks": 6,
  "highlights": -12,
  "temp": 4,
  "vibrance": 18,
  "curve": [[0, 0.02], [0.22, 0.25], [0.78, 0.82], [1, 1]],
  "hsl": {"blue": {"s": 12, "l": -8}, "aqua": {"s": 10}, "orange": {"s": 8}}
}
```

Send it in two passes, tone then colour, and look in between.

The difference between tasteful and cliché is entirely restraint in the colour
mixer. Keep band saturation under about 30. Once shadows read as cartoon teal
or skin reads orange, it has become a filter, and viewers see technique instead
of mood.

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

Use `saturation: -100`, then do all the work in tone.

```json
{"saturation": -100, "contrast": 20, "whites": 10, "blacks": -8, "clarity": 10}
```

Black and white tolerates harder contrast than colour, since there is no
saturation to blow out, so be more aggressive here than you would be otherwise.

One honest limitation: the classic darkroom control, mapping each original hue
to its own grey value so a blue sky darkens independently of skin, is not
available. Global desaturation happens before the colour mixer in the pipeline,
so per-hue luminance mapping has nothing left to select. If a user wants a dark
sky in a monochrome frame, a linear local adjustment across the horizon is the
route.

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
