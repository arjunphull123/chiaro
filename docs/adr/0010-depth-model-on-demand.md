# 0010 — Depth-map blur via an on-demand Core ML model

## Status
Accepted

## Context
Subject-mask blur (Vision person segmentation) is binary: person sharp,
everything else uniformly blurred. Real lenses blur by distance. Apple ships no
public monocular-depth API, but publishes a Core ML conversion of Depth
Anything V2 (small) on Hugging Face under `apple/coreml-depth-anything-v2-small`.

## Decision
- Use the **F16 variant** (49.8 MB): fp16 is the ANE-native precision; INT8 and
  pruned variants save disk but not enough to justify the quality risk.
- **Not bundled.** The app stays a small download; the model is a one-click,
  opt-in download from the Portrait section (Subject | Depth chips).
- Files download individually (HF serves mlpackage contents as separate blobs)
  into `~/Library/Application Support/Chiaro/Models/`, compile once via
  `MLModel.compileModel` to `.mlmodelc`, and the source package is deleted.
- Inference through Vision (`VNCoreMLRequest`, scale-fill); output disparity is
  min/max-normalized per image on the GPU with a 2-pixel readback.
- `EditState` gains `depthBlur: Bool` + `focusDepth: Double` (0 near … 1 far) —
  both serialize to sidecars and are settable over MCP like everything else.
- Blur amount mask = |normalized disparity − focus plane| × 1.6, clamped, into
  the same `CIMaskedVariableBlur` the subject path uses.

## Consequences
- First use needs a network connection; the UI owns download/compile state
  (`DepthModelStore`) and fails visibly with retry.
- Export and MCP previews share the same depth cache (12-entry LRU, keyed by
  photo URL); depth inference runs on Offload queues, never the cooperative pool.
- If Apple pulls or moves the weights, the pinned byte sizes make the failure
  loud, not silent.
