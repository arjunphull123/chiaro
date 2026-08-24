# ADR 0013: Sidecar schema growth and the compatibility contract

**Status:** Accepted · 2026-08-19

## Context
The sidecar began as {edit, rating}. The edit model grew (HSL bands, local
adjustments, blur modes, rotation/flips/skew) and photo-level state appeared
(starred, versions). Old sidecars must keep working forever.

## Decision
- **Tolerant decoding is the compatibility contract**: every field decodes
  with `decodeIfPresent` + a neutral default; unknown keys are ignored;
  removed fields (rating → starred, focusRange, depthBlur → blurMode,
  cleanup strokes, backdrop) simply stop being read. Migrations happen at
  decode (rating > 0 → starred) — never as file rewrites.
- Encoding stays sparse: only non-neutral values are written, so sidecars
  remain small, diffable, and human-readable.
- Photo-level state (starred, named versions) lives in the sidecar Document
  beside the edit; a sidecar is deleted only when edit is neutral AND
  unstarred AND versionless.
- MCP mirrors the same schema: parameters come from `EditParameter.allCases`
  plus special-cased structured keys, so the agent surface can't drift from
  the edit model.

## Consequences
- Any EditState addition needs: default value, tolerant decode, sparse
  encode, MCP mapping — and nothing else.
- Never rename a sidecar key in place; add the new one and migrate at decode.
