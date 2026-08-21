# 0016 — Working in Core Image's linear space

## Status
Accepted

## Context
`RawEngine` creates its `CIContext` with
`.workingColorSpace: extendedLinearDisplayP3`. Every filter in the pipeline
therefore sees linear light. Nothing in the type system says so, no compiler
warning mentions it, and every value still sits in a familiar 0...1 range, so
code that assumes display-referred tone compiles and runs and looks almost
right.

Three separate defects in one week traced to exactly this, none of them caught
by a build and two of them not caught by measurement either:

- **Zone grading selected the wrong pixels.** `ColorGradeCube` weighted its
  shadow/mid/highlight bells on linear luminance while their centres (0, 0.5,
  1) were chosen for perceptual tone. The highlight bell only engaged above
  roughly 91% display, so it read as completely dead, while "shadows" reached
  to 54% display and "mids" centred on 74%.
- **A mask coefficient was mangled by a colour conversion.** `LumaRangeMask`
  used `CIColorCubeWithColorSpace` because grading does. That filter converts
  the result back into the working space, which is right for a colour and wrong
  for a coefficient: 0.5 came back as 0.218, so mid-feather pixels took a fifth
  of the adjustment instead of half.
- **Grain put its amplitude in the wrong units.** A delta fixed in linear light
  is a large perceptual jump where linear values crush toward zero. Display 0.1
  moved by 0.12 against the midtones' 0.05, which rendered as white salt over
  dark cloth and hair rather than as grain.

The pattern is worth naming. Each fix was one or two lines. Each defect
survived because the wrong version was plausible, produced output, and in two
cases produced *numbers* that looked healthy: whole-image gray-world means
moved by half a percent when highlight grading was entirely dead, because
midtones dominate any mean.

## Decision

Three rules, recorded here because they govern any future pixel work rather
than any one feature, and restated at each point of use because the general
form ("mind the colour space") is too vague to catch anything.

**1. A LUT declares its space when it emits a colour, and handles gamma itself
when it emits a coefficient.** `CIColorCubeWithColorSpace` converts the source
into the declared space, looks up the cube, and converts the result back. For a
colour that round trip is exactly right, so `HSLCube` and `ColorGradeCube` use
it with `displayP3`. For a mask or a weight the return leg corrupts the value,
so `LumaRangeMask` and the grain weight use the plain `CIColorCube` and
gamma-encode luminance themselves before comparing it against anything a human
named.

**2. An amplitude meant to be perceptually uniform carries the Jacobian.**
Weighting by tone decides *which* pixels an effect reaches. It does not decide
how much change the eye sees per unit of effect. Anything added or subtracted
in linear light needs a factor of `d(linear)/d(display)`, proportional to
`display^1.2`, or it will be violent in the shadows and invisible in the
highlights.

**3. Signed delta layers are not composited, they are blended between.** Core
Image treats images as premultiplied. A signed delta layer with alpha 1 makes
`CIAdditionCompositing` sum alpha to 2; with alpha 0 it is simply transparent
and contributes nothing, which is how grain once rendered byte-identical to no
grain. Blend between `image ± peak` instead and fold the weight into the mask:
`m' = 0.5 + w(m - 0.5)` resolves to `image + peak·w·(2m - 1)` exactly, with
every image in the graph opaque.

**Verification follows the defect, not the code.** An invisible property
(a cache key, a sign convention, a colour space) is settled by reading code or
by measuring a targeted statistic. A visible one is settled by rendering two
images and looking at them. Whole-image aggregates are not evidence about a
tonally-scoped control, and a filter that silently declines its input is not
evidence about anything: `CIUnsharpMask` clamps negative intensity to zero, so
negative clarity shipped as a no-op, and `CIColorKernel(source:)` returned nil
from a one-character typo, so an earlier grading implementation did nothing for
as long as it shipped.

## Consequences
- Any new cube must state which of the two cases it is. Both existing examples
  carry that note at the call site.
- The tuning constants in `ColorGradeCube` were fitted against the broken
  behaviour and are therefore suspect, not authoritative. `darkFloor = 0.15`
  was introduced to stabilise "near-black" and in linear light meant 42%
  display; it now means what its name says. The `0.3` chroma scale was pinned
  low to contain a blowout that no longer happens, so it is the dial to raise
  if grading feels thin.
- Shadow grading is gentler than it was at the same strength, because in linear
  light it had been clipping the opposing channel to zero. That read as force.
- This is the sort of trap that a future agent driving the pipeline will hit
  again, so the rules are stated in terms of what the code emits rather than in
  terms of the three bugs that produced them.
