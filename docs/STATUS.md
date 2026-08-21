# Status, 2026-08-21

A working list, written before compacting a long session. Everything below is
either verified, outstanding, or deliberately deferred. Delete this file once
the shoot and launch are done.

## Verified working (by eye or by measurement)

Colour grading by tonal zone, all three zones, monochrome with per-band
luminance, monochrome plus grading giving toned black and white, all six Light
controls in both directions, temp and tint in the conventional direction
(positive warms, positive tint is magenta), vibrance, saturation, the tone
curve, vignette, clarity in both directions, all eight colour-mixer bands across hue,
saturation and luminance, radial and linear local adjustments, crop, straighten,
rotation, both flips, all six presets, background blur in Subject mode with the
subject staying sharp, RAW decode parameters, `get_stats`, the search field,
the library header at 1080, agent edits opening the photo they touch, the
before-and-after glyph with press-and-hold, auto-enhance leaving temp and
tint alone on RAW, and the agent status card in all three of its states.

## Outstanding bugs

1. **Focus peaking paints rather than tints.** The in-focus wash is amber at
   0.45 opacity composited over the image, which on a dark subject obliterates
   it: the shoot's peaking frame reads as a solid orange cat-shaped cutout with
   no cat in it. Around 0.2 would tint without erasing. Found by shooting it,
   not by testing it. The screenshot was dropped rather than reshot, since the
   3D scene covers the same ground better, so this is a product fix rather than
   a blocker.
2. **Depth blur may blur uniformly** rather than masking by distance. Reported
   by an automated test whose blur findings proved unreliable, so treat as
   unconfirmed until checked by eye with the depth model downloaded. The only
   bug left on the list.

Fixed 2026-08-21, all three confirmed by the owner by eye:

- **Highlight grading.** `ColorGradeCube` was the only LUT applied with plain
  `CIColorCube` instead of `CIColorCubeWithColorSpace` + displayP3, so it was
  fed linear light while its contents were authored gamma-encoded. That broke
  three things at once, not one: the zone bells classified by linear luminance
  (highlights engaged only above ~91% display), the additive chroma landed far
  harder on dark pixels than bright ones so equal strengths meant unequal
  force, and `protect` measured saturation in linear too, discarding about half
  the tint on a warm highlight. An earlier narrower fix that only corrected the
  bells was insufficient and is reverted. See ADR 0015. Shadow grading is now
  gentler at the same strength, because in linear it had been clipping the
  opposing channel to zero; if looks feel thin, raise the `0.3` chroma scale
  rather than going back to clipping.
- **Negative clarity.** `CIUnsharpMask` clamps negative intensity to zero, so
  it could only sharpen. Softening has its own path now. Un-breaks Portrait
  glow, which sets `clarity: -8` and had shipped as a no-op.
- **Unbounded client name.** Capped at 14 characters in `AgentStatus`.

## The agent status card, built 2026-08-21

Built to the owner's spec and approved by eye. One fixed-width card, the rail's
inner content column, in every state and in both views. State and brand icon on
the left, relative time on the right in mono, the agent's intent wrapping to
three lines under a hairline when it is working. The separately-composed intent
badge is gone, folded into the same card.

The fixed width is the point, and it should not be traded away later: the pill
overflowed three times while it sized to its content, and some of that content
is a string an agent supplies. Fixed width plus truncation means runtime text
can only shorten itself, never move an edge. The last activity line stays out
of the card for the same reason; it lives in the popover.

The app mark now dims with the photo header so the expanded card reads as one
layer over a receded rail rather than two things sharing a corner.

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

## Resuming after a compaction

Read this file first; it is the source of truth for what is left.

How to work from here, in order: luminance-range masking on locals, then grain,
then confirm depth blur by eye. Then update the `/chiaro` skill, which still
describes the engine as it was before the grading fix and before negative
clarity worked. Then the ground-truth captures and the shoot.

Process rules that were learned the hard way: one actor on the live app at a
time, since agents and I clobbered each other's photo state. Sonnet does
implementation and testing; judgment, specs and verdicts stay with the lead
model. Always rebuild and relaunch immediately before asking the owner to hand
test, and tell him exactly what to click. Verify the binary is newer than the
sources, since a comment-only change reports "Build complete" without relinking.
Launch the app by running `.build/debug/Chiaro --open <folder>` directly;
`swift run` and `open dist/Chiaro.app` leave a windowless process. `get_stats`
is not in the cached MCP tool list, so call it over HTTP against
`http://127.0.0.1:24242/mcp`, where `set_edit` takes its values under `edit`,
not `values`. To experiment on a photo carrying real edits, copy the ARW and its
sidecar to a scratch folder and open that instead of editing the original.

Two things measurement got wrong that the eye got right immediately: it called
working blur broken, and it declared highlight grading healthy when the whole
frame moved by half a percent. Whole-image means are a bad proxy for whether a
zone control is visible, because midtones dominate any mean. Render two previews
and look.

## Shoot: done, 2026-08-21

15 stills and one screen recording in `~/Desktop/chiaro shoot`. The recording is
950 MB, so it is a source for frame grabs rather than something to ship; the
"Claude is editing" moments in it are the only clean captures of the status card
mid-edit. Two pairs came out byte-identical (a double press, and the peaking
frame). Three frames have the wrong app name in the menu bar, which does not
matter because nothing on the site includes the menu bar.

The frames that earn their place: the paired shot with the terminal, which is
the only one that proves the claim and whose terminal text is the best copy in
the set; the 3D point cloud, which nothing on a competitor's site resembles; and
the black and white tram frame, which also closes the tungsten night question.

Verbatim transcript of the driven session is at
`chiaro-site/docs/demo-transcript.md`.

Next phase is the site, built close to cursor.com's structure by the owner's
call. Specs already in `chiaro-site/docs/`.

## Shoot dependencies (now historical)

Blur works, so the portrait shot is unblocked. The highlight and clarity fixes
have landed and the status card is approved. Still waiting on a look at a
tungsten night frame under the as-shot white balance. Frames are settled: hero is Wadi
Rum DSC02712, recording is DSC03055 with the Overcast recipe, depth scene is
the cat DSC00858. A new headshot for the LinkedIn post is also wanted, shot and
edited in Chiaro.
