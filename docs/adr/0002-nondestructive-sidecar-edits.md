# ADR 0002: Non-destructive edits via JSON sidecars

**Status:** Accepted · 2026-08-18

## Context

Original RAW files are irreplaceable captures. Edits must be revisable forever,
survive app reinstalls, and travel with the photos.

## Decision

Never modify originals. All edits serialize to a JSON sidecar next to the source file
(`DSC04002.arw` → `DSC04002.darkroom.json`) containing a versioned `EditState`:
every adjustment parameter, crop, masks, and preset lineage. Rendering is a pure
function `(RAW, EditState) → image`.

No central library database in v1. The folder is the library; sidecars are the state.

## Consequences

- Deleting the app loses nothing; edits are plain text next to the photos.
- Copy/paste edits across photos = copy the EditState.
- Sidecar schema is versioned from day one so it can evolve without breaking old edits.
- Sidecars on a camera SD card imply users should import to disk first; the app's
  import flow should encourage that.
