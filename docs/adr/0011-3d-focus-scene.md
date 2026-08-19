# 0011 — 3D focus scene on SceneKit

## Status
Accepted

## Context
Depth-mode blur is controlled by a focus plane in disparity space. Sliders
describe it; showing the scene *as* a space explains it. Prior art: Focos'
3D depth view, Autodesk's ViewCube for orientation.

## Decision
- SceneKit (system framework, no dependency): the photo becomes a color point
  cloud (128-wide grid from the depth map), one gridded slice plane marks the
  edge of sharpness, an orientation cube (ViewCube-style) syncs with orbit.
- **One knob**: with one-sided blur, focus depth and range collapsed into a
  single value — Focus *is* the plane. `focusRange` was removed from EditState
  (old sidecars decode tolerantly).
- Choreography: enter head-on (cloud matches the flat photo's screen size via
  camera-distance math), morph flat→depth with an SCNMorpher, swing to 3/4,
  planes grow from the ground; exit reverses.
- **Representable sync rule**: SwiftUI does not reliably re-invoke
  `updateNSView` for `@Observable` reads inside it — every value the scene
  reacts to (yaw, pitch, focus) is passed as an explicit view property.
- Line primitives for the plane lattice (1px at any distance); grab handles
  are the only plane hit-targets, everything else orbits; trackpad scroll
  orbits, wheel/pinch zooms.

## Consequences
- AppKit/SceneKit lives behind one representable; all edit state stays in
  EditState, so agents drive the same values the scene shows.
- Full 180° yaw + overhead pitch only — no under/behind views (the cloud is
  a relief, not a model; backside views read as garbage).
