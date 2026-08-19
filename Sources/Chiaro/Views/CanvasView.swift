import SwiftUI
import TipKit

/// The photo canvas: fits inside the region left of the rail, zoomable and pannable
/// (may slide under the rail when zoomed), and doubles as the scrub surface when a
/// parameter is armed (ADR 0005).
struct CanvasView: View {
    @Bindable var model: EditViewModel

    @State private var zoom: CGFloat = 1
    @State private var gestureZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var gesturePan: CGSize = .zero
    @State private var lastScrubX: CGFloat?
    @State private var lastDialX: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let fitRegion = CGSize(width: geo.size.width - Theme.railWidth, height: geo.size.height)
            ZStack {
                Color.black.opacity(0.001) // hit target for gestures on empty canvas
                if model.depthSceneVisible && model.edit.blurMode == .depth {
                    DepthSceneView(model: model, fitFraction: fitFraction(in: fitRegion))
                        .frame(width: fitRegion.width, height: fitRegion.height)
                        .position(x: fitRegion.width / 2, y: fitRegion.height / 2)
                        .overlay(alignment: .top) {
                            Button {
                                model.depthSceneCommand = .exit
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                                    Text("Exit 3D focus")
                                }
                            }
                            .buttonStyle(AmberButtonStyle())
                            .clickCursor()
                            .padding(.top, 14)
                            .help("Back to the photo (esc)")
                        }
                        .overlay(alignment: .topTrailing) {
                            ViewCubeView(model: model)
                                .frame(width: 78, height: 78)
                                .padding(.top, 52)
                                .padding(.trailing, 14)
                        }
                } else if let cg = model.showOriginal ? model.originalPreview : model.preview {
                    let imageSize = CGSize(width: cg.width, height: cg.height)
                    let fitScale = min(
                        (fitRegion.width - 48) / imageSize.width,
                        (fitRegion.height - 48) / imageSize.height
                    )
                    let fitSize = CGSize(width: imageSize.width * fitScale, height: imageSize.height * fitScale)
                    Image(cg, scale: 1, label: Text(model.photo.name))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: fitSize.width, height: fitSize.height)
                        .scaleEffect(zoom * gestureZoom)
                        .offset(x: pan.width + gesturePan.width, y: pan.height + gesturePan.height)
                        .position(x: fitRegion.width / 2, y: fitRegion.height / 2)
                        .shadow(color: .black.opacity(0.45), radius: 24, y: 8)
                    if model.cropMode {
                        CropOverlayView(
                            edit: $model.edit,
                            frameAspect: Double(cg.width) / Double(cg.height),
                            lockedAspect: model.cropAspect
                        )
                        .frame(width: fitSize.width, height: fitSize.height)
                        .position(x: fitRegion.width / 2, y: fitRegion.height / 2)
                    }
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .position(x: fitRegion.width / 2, y: fitRegion.height / 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(fitRegion))
            .gesture(magnifyGesture)
            .onTapGesture(count: 2) { if !model.cropMode { toggleZoom() } }

            .overlay(alignment: .bottom) {
                Group {
                    if model.cropMode { cropPanel } else { readout }
                }
                .padding(.bottom, 78)
                .padding(.trailing, Theme.railWidth)
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    TipView(ScrubTip())
                    if model.armed != nil { TipView(FineTuneTip()) }
                }
                .frame(maxWidth: 340)
                .padding(.top, 52)
                .padding(.leading, 16)
            }
            .onContinuousHover { phase in
                if model.focusPicking, case .active = phase { NSCursor.crosshair.set() }
            }
            .onChange(of: model.photo.url) { resetView() }
            .onChange(of: model.cropMode) { resetView() }
        }
    }

    /// The flat photo's height as a fraction of the canvas, for the seamless
    /// head-on camera match in the 3D scene.
    private func fitFraction(in fitRegion: CGSize) -> CGFloat {
        guard let cg = model.preview else { return 0.85 }
        let imageSize = CGSize(width: cg.width, height: cg.height)
        let fitScale = min(
            (fitRegion.width - 48) / imageSize.width,
            (fitRegion.height - 48) / imageSize.height
        )
        return imageSize.height * fitScale / fitRegion.height
    }

    private func dragGesture(_ fitRegion: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if model.focusPicking {
                    return // resolves as a click on mouse-up
                } else if model.spacePan {
                    gesturePan = g.translation
                } else if model.armed != nil {
                    let dx = g.location.x - (lastScrubX ?? g.startLocation.x)
                    lastScrubX = g.location.x
                    model.scrub(deltaX: dx)
                } else if zoom > 1 {
                    gesturePan = g.translation
                }
            }
            .onEnded { g in
                if model.focusPicking {
                    if abs(g.translation.width) < 4, abs(g.translation.height) < 4,
                       let (u, v) = normalizedPoint(g.location, in: fitRegion) {
                        model.focusAt(u: u, v: v)
                    }
                    model.focusPicking = false
                    NSCursor.arrow.set()
                    return
                }
                lastScrubX = nil
                pan = CGSize(width: pan.width + gesturePan.width, height: pan.height + gesturePan.height)
                gesturePan = .zero
            }
    }

    /// Canvas point → normalized image coordinates (v top-down), accounting
    /// for fit, zoom, and pan.
    private func normalizedPoint(_ location: CGPoint, in fitRegion: CGSize) -> (Double, Double)? {
        guard let cg = model.preview else { return nil }
        let imageSize = CGSize(width: cg.width, height: cg.height)
        let fitScale = min(
            (fitRegion.width - 48) / imageSize.width,
            (fitRegion.height - 48) / imageSize.height
        )
        let fitSize = CGSize(width: imageSize.width * fitScale, height: imageSize.height * fitScale)
        let center = CGPoint(x: fitRegion.width / 2 + pan.width, y: fitRegion.height / 2 + pan.height)
        let u = (location.x - center.x) / (fitSize.width * zoom) + 0.5
        let v = (location.y - center.y) / (fitSize.height * zoom) + 0.5
        guard (0...1).contains(u), (0...1).contains(v) else { return nil }
        return (Double(u), Double(v))
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { g in gestureZoom = g.magnification }
            .onEnded { _ in
                zoom = max(1, min(8, zoom * gestureZoom))
                gestureZoom = 1
                if zoom == 1 { pan = .zero }
            }
    }

    private func toggleZoom() {
        withAnimation(.easeOut(duration: 0.15)) {
            if zoom > 1 { resetView() } else { zoom = 2.5 }
        }
    }

    private func resetView() {
        zoom = 1
        pan = .zero
        gesturePan = .zero
    }

    /// Crop mode controls: aspect presets, straighten, reset, done.
    private var cropPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 5) {
                aspectChip("Free", nil)
                aspectChip("Original", originalAspect)
                aspectChip("1:1", 1)
                aspectChip("4:5", 0.8)
                aspectChip("3:2", 1.5)
                aspectChip("16:9", 16.0 / 9)
            }
            HStack(spacing: 10) {
                Text("Straighten")
                    .font(Theme.ui(10))
                    .foregroundStyle(Theme.ink3)
                Slider(value: straightenBinding, in: -45...45)
                    .tint(Theme.amber)
                    .controlSize(.small)
                    .frame(width: 180)
                Text(EditParameter.straighten.format(model.edit.straighten))
                    .font(Theme.mono(10))
                    .foregroundStyle(model.edit.straighten == 0 ? Theme.ink3 : Theme.amber)
                    .frame(width: 42, alignment: .trailing)
                    .monospacedDigit()
            }
            HStack(spacing: 8) {
                Button("Reset") {
                    model.edit.crop = .full
                    model.edit.straighten = 0
                    model.cropAspect = nil
                }
                .buttonStyle(OutlineButtonStyle())
                .clickCursor()
                Button("Done") { model.cropMode = false }
                    .buttonStyle(AmberButtonStyle())
                    .clickCursor()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .chiaroGlass(cornerRadius: 15)
    }

    private var originalAspect: Double? {
        if let size = model.photo.pixelSize { return Double(size.width) / Double(size.height) }
        if let cg = model.preview { return Double(cg.width) / Double(cg.height) }
        return nil
    }

    private var straightenBinding: Binding<Double> {
        Binding(
            get: { model.edit.straighten },
            set: { newValue in
                let old = model.edit.straighten
                model.edit.straighten = newValue
                HapticDetents.tickIfCrossed(parameter: .straighten, from: old, to: newValue)
            }
        )
    }

    private func aspectChip(_ title: String, _ aspect: Double?) -> some View {
        Chip(title: title, selected: model.cropAspectName == title) {
            model.applyCropAspect(aspect, name: title)
        }
    }

    /// The one slider in the app: a floating glass dial for the armed parameter
    /// (ADR 0005). Drag it, drag the photo, or scroll — same EditState either way.
    @ViewBuilder private var readout: some View {
        if let armed = model.armed {
            let range = armed.range
            let t = (armed.value(in: model.edit) - range.lowerBound) / (range.upperBound - range.lowerBound)
            VStack(spacing: 7) {
                HStack(spacing: 10) {
                    Text(armed.label)
                        .font(Theme.ui(11, .medium))
                        .foregroundStyle(Theme.ink2)
                    Text(armed.format(armed.value(in: model.edit)))
                        .font(Theme.mono(19, .medium))
                        .foregroundStyle(Theme.amber)
                        .monospacedDigit()
                }
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18)).frame(height: 2)
                    ForEach(armed.detents, id: \.self) { d in
                        let dt = (d - range.lowerBound) / (range.upperBound - range.lowerBound)
                        Rectangle().fill(Color.white.opacity(0.3))
                            .frame(width: 2, height: 7)
                            .offset(x: dt * 260)
                    }
                    Capsule().fill(Theme.amber).frame(width: max(0, t * 260), height: 2)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Theme.amber)
                        .frame(width: 3, height: 14)
                        .shadow(color: Theme.amber.opacity(0.6), radius: 4)
                        .offset(x: t * 260 - 1.5)
                }
                .frame(width: 260, height: 14)
                .contentShape(Rectangle().inset(by: -10))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let dx = g.location.x - (lastDialX ?? g.startLocation.x)
                            lastDialX = g.location.x
                            model.scrub(deltaX: dx * 1.6)
                        }
                        .onEnded { _ in lastDialX = nil }
                )
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .chiaroGlass(cornerRadius: 15)
            .overlay(alignment: .topTrailing) {
                Button { model.armed = nil } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                        .overlay(Circle().stroke(Theme.hairline))
                }
                .buttonStyle(.plain)
                .clickCursor()
                .padding(5)
                .help("Done — back to pan and zoom (esc)")
            }
            .transition(.opacity)
        }
    }
}
