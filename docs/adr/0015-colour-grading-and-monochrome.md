# 0015 — Colour grading by tonal zone, and a real monochrome mixer

## Status
Accepted

## Context
Two gaps surfaced while writing the editing skill (`.claude/skills/chiaro/`),
both found by reading the render pipeline rather than by guessing:

**No colour grading by tonal zone.** The colour mixer selects by hue and the
tone curve applies to all channels equally, so there is no way to put one colour
in the shadows and another in the highlights. That single move defines the
cinematic grade every photographer asks for by name, so the skill currently has
to say the look can only be approximated.

**Monochrome conversion has no craft in it.** Global `saturation` is applied
before the HSL cube in `RenderPipeline`, so `saturation: -100` leaves the mixer
nothing to select. The darkroom control that matters, mapping each original hue
to its own grey value so a blue sky darkens independently of skin, is therefore
unreachable. The Silver preset is a flat desaturation for this reason.

A third gap is deliberately not addressed here. Per-channel RGB curves would
also enable split toning, but they need a graph editor per channel, which fights
ADR 0005's one-value-at-a-time interaction and gives an agent a far clumsier
surface than scalars. Zone grading covers the same ground and fits both.

## Decision

**Colour grading expressed as scalar rows, not wheels.** Every other editor
ships colour wheels. A wheel is a two-dimensional control, and this app has one
dial and a canvas that scrubs a single value (ADR 0005), so wheels do not
belong here. Three zones, two values each:

- `shadowHue`, `shadowStrength`
- `midHue`, `midStrength`
- `highlightHue`, `highlightStrength`

Hue is 0–360 and wraps; strength is 0–100 and defaults to 0, so the whole
feature is inert until asked for. A seventh value, `gradeBalance` (-100…100),
shifts where shadows end and highlights begin.

Rendering computes luminance, weights each zone by a smooth falloff of that
luminance, and blends each zone's hue in at its strength — a pure function of
a pixel's RGB, so (like the HSL mixer) it's baked into a `CIColorCube` rather
than run per-pixel. An initial `CIColorKernel(source:)` version was reverted:
CIKL has been deprecated since macOS 10.14, and its C-like source silently
failed to compile from a one-character typo, doing nothing for as long as it
shipped. One pass, Metal-backed, no new dependency.

The cube must be applied with `CIColorCubeWithColorSpace` and an explicit
`displayP3`, as `HSLCube` and the tone curve already do. The context works in
extended-linear P3, so an untagged cube is fed linear light while its contents
were authored against gamma-encoded values. That shipped, and it broke the
feature three ways at once rather than one: the zone bells classified by linear
luminance, so highlights only engaged above roughly 91% display; the additive
chroma landed far harder on dark pixels than bright ones, so equal strengths
meant unequal force; and the saturation-protection term measured colour in
linear too, discarding about half the tint on a warm highlight. Both of this
feature's defects were a declaration the code failed to make and the compiler
had no reason to check. Prefer measuring a LUT's actual output over reading it.

**Monochrome as an explicit mode, not a pipeline reorder.** Add
`monochrome: Bool`. When true, the pipeline converts to grey *using the HSL
luminance values as channel weights*, before global saturation applies. The
existing per-band `l` values become the channel mixer, which is exactly how
Lightroom's black and white panel behaves, so the control is already familiar
and already in the rail.

Reordering the existing pipeline to fix this was rejected: it would silently
change the rendered result of every sidecar that already combines saturation
with the mixer.

## Consequences
- Eight new `EditState` fields, all scalars or a bool, all defaulting to inert.
  Additive sidecar growth, which ADR 0013's tolerant decode already covers.
- Both features are agent-drivable the moment they exist, with no MCP work,
  because every value is a field in `EditState` per the project's hard rule.
- The rail gains a Grading group (six rows plus balance) and a monochrome
  toggle in Color mix. Any existing screenshot of the rail becomes stale.
- The skill's honest limitations section shrinks: the cinematic recipe can then
  be the real move rather than an approximation, and monochrome conversion gains
  the per-hue control the craft actually requires.
- Silver should be revisited afterwards to use the mixer rather than a flat
  desaturation.
