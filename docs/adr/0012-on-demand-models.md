# ADR 0012: On-demand ML models: the pattern, and what got cut

**Status:** Accepted · 2026-08-19

## Context
ML features need weights the app shouldn't bundle. ADR 0010 set the pattern
for Depth Anything; more models followed — some shipped, some measured and cut.

## Decision
The pattern (any future model follows it):
- Weights live in `~/Library/Application Support/Chiaro/Models/`, downloaded
  file-by-file from Hugging Face with pinned byte sizes (drift fails loudly),
  compiled once via `MLModel.compileModel` to `.mlmodelc`, source package
  deleted after compile.
- Downloads are **always user-opt-in** from the UI with visible progress;
  stores are `@Observable` state machines (missing → downloading → preparing
  → ready → failed) woken eagerly at launch so compiled models load without UI.
- Compute units are per-model: default `.all`, but **models with FFT ops
  (LaMa-family) hang the ANE compiler — load those `.cpuAndGPU`**.

Measured and cut (resurrect from git if revisited):
- **SAM 2.1 tiny** (box-prompted focus selection): masks too coarse to earn
  80 MB. Note: Apple's prompt encoder emits plural output names
  ("sparse_embeddings") that the decoder wants singular.
- **LaMa Clean up** (object removal): fills too mushy at 512px for a
  photography tool.
- **Edge-fill background plates** for halo-free bokeh (LaMa and a pure-CI
  normalized-convolution variant): the halo is the mask's alpha transition at
  hair, not the plate — plates made backlit hair *worse*. The wins that stayed:
  `CIEdgePreserveUpsampleFilter` on depth maps and subject masks, and
  `.accurate` person segmentation.

## Consequences
- Only Depth Anything V2 (49.8 MB) ships as a download today.
- Every removal is evidence-based and recorded here rather than re-litigated.
