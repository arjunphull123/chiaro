# Status, 2026-08-21

A working list, written before compacting a long session. Everything below is
either verified, outstanding, or deliberately deferred. Delete this file once
the shoot and launch are done.

## Verified working (by eye or by measurement)

Colour grading by tonal zone (shadow and mid zones), monochrome with per-band
luminance, monochrome plus grading giving toned black and white, all six Light
controls in both directions, temp and tint in the conventional direction
(positive warms, positive tint is magenta), vibrance, saturation, the tone
curve, vignette, positive clarity, all eight colour-mixer bands across hue,
saturation and luminance, radial and linear local adjustments, crop, straighten,
rotation, both flips, all six presets, background blur in Subject mode with the
subject staying sharp, RAW decode parameters, `get_stats`, the search field,
the library header at 1080, agent edits opening the photo they touch, the
before-and-after glyph with press-and-hold, and auto-enhance leaving temp and
tint alone on RAW.

## Outstanding bugs

1. **Highlight grading zone does nothing.** Strength and hue both inert while
   shadow and mid work. Prime suspect: `highlightStrength`/`highlightHue`
   missing from the `NSCache` key in `ColorGradeCube`, so the cube is never
   rebuilt. Fix in progress.
2. **Negative clarity does nothing.** Positive works. Silently breaks the
   shipped Portrait glow preset, which sets `clarity: -8`. Fix in progress.
3. **Unbounded client name in the agent pill.** If an MCP client self-reports a
   long name it flows into the pill's phrase and can overflow. Needs a length
   cap. Not started.
4. **Depth blur may blur uniformly** rather than masking by distance. Reported
   by an automated test whose blur findings proved unreliable, so treat as
   unconfirmed until checked by eye with the depth model downloaded.

## Not yet seen by the owner

The agent activity overlay (the floating glass chip showing live intent beneath
the status pill).

## Feature roadmap, agreed 2026-08-21

Ship before launch: luminance-range masking on locals (two scalars on an
existing local, the highest-value item left), and grain (one or two values in
Effects, the missing piece for a film look).

Deferred deliberately: healing and clone (owner's call; note ADR 0012 already
cut generative inpainting on quality evidence, so this means classical
patch-based work). Apple Foundation Models, the on-device LLM: not now. Its
guided generation fits `EditState` well, but a ~3B model cannot see the
photograph and `AutoEnhance` already maps statistics to values deterministically
and without hallucinating. Revisit if Apple's multimodal tier becomes the
on-device default, or if the WWDC 2026 provider path matures enough to target
Claude through the same API.

## Testing lessons worth keeping

Measured smoke tests over the whole edit surface are good at tone and colour
controls and caught several real defects quickly. They are unreliable for
anything spatial: the blur "failures" were an artifact of test photos where
Vision had nothing to find, and two of four reported failures were not real.
Anything visible should be checked by eye. Anything invisible, such as sign
conventions, cache keys or persistence, needs code reading.

Judge colour at 1400px or larger. A 700px preview hid crushed shadows once and
a colourless highlight recovery read as warmth on a photo whose stone was
already warm.

## Shoot dependencies

Blur works, so the portrait shot is unblocked. Waiting on: the highlight and
clarity fixes, the owner seeing the activity overlay, and a look at a tungsten
night frame under the as-shot white balance. Frames are settled: hero is Wadi
Rum DSC02712, recording is DSC03055 with the Overcast recipe, depth scene is
the cat DSC00858. A new headshot for the LinkedIn post is also wanted, shot and
edited in Chiaro.
