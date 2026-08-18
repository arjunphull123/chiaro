# ADR 0001: Native macOS app on SwiftUI + Core Image

**Status:** Accepted · 2026-08-18

## Context

Chiaro needs to decode 20MB Sony ARW files, render slider adjustments in real time
at 5472×3648, and feel like a polished Mac app. Candidate platforms: web app,
Electron + LibRaw, native macOS.

Verified on the target machine: macOS's built-in RAW engine decodes RX100 IV `.arw`
natively (`sips`/`CIRAWFilter`) — full resolution, 16-bit, Display P3.

## Decision

Native macOS app: Swift + SwiftUI, Core Image `CIRAWFilter` for decode, a `CIFilter`
chain for adjustments, Metal-backed live preview. Vision framework for person/subject
segmentation; Core ML for depth estimation.

Development uses Swift Package Manager (CLI-buildable, no Xcode project churn);
migrate to an Xcode project only if signing/App Store distribution ever requires it.

## Consequences

- RAW decode, GPU rendering, segmentation, color management, and HEIF/TIFF export
  come from the OS — near-zero dependencies.
- macOS-only. Acceptable: it's a personal tool for a Mac.
- Camera support tracks Apple's RAW compatibility list rather than LibRaw's.
