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
                    DepthSceneView(
                        model: model, fitFraction: fitFraction(in: fitRegion),
                        yaw: model.sceneYaw, pitch: model.scenePitch,
                        focusDepth: model.edit.focusDepth, focusRange: model.edit.focusRange
                    )
                        .frame(width: fitRegion.width, height: fitRegion.height)
                        .overlay(alignment: .topTrailing) {
                            ViewCubeView(model: model, yaw: model.sceneYaw, pitch: model.scenePitch)
                                .frame(width: 78, height: 78)
                                .padding(.top, 54)
                                .padding(.trailing, 10)
                        }
                        .position(x: fitRegion.width / 2, y: fitRegion.height / 2)
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
                    if let localIndex = model.edit.locals.firstIndex(where: { $0.id == model.selectedLocalID }),
                       !model.cropMode, !model.depthSceneVisible {
                        localGizmo(index: localIndex, fitSize: fitSize)
                            .frame(width: fitSize.width, height: fitSize.height)
                            .scaleEffect(zoom * gestureZoom)
                            .offset(x: pan.width + gesturePan.width, y: pan.height + gesturePan.height)
                            .position(x: fitRegion.width / 2, y: fitRegion.height / 2)
                    }
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
                    if model.cropMode {
                        cropPanel
                    } else if model.depthSceneVisible && model.edit.blurMode == .depth {
                        depthSceneCard
                    } else {
                        readout
                    }
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
        return (Double(u.clamped(to: 0...1)), Double(v.clamped(to: 0...1)))
    }

    private func dragGesture(_ fitRegion: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if model.spacePan {
                    gesturePan = g.translation
                } else if model.armed != nil || model.armedHSL != nil {
                    let dx = g.location.x - (lastScrubX ?? g.startLocation.x)
                    lastScrubX = g.location.x
                    model.scrub(deltaX: dx)
                } else if zoom > 1 {
                    gesturePan = g.translation
                }
            }
            .onEnded { _ in
                lastScrubX = nil
                pan = CGSize(width: pan.width + gesturePan.width, height: pan.height + gesturePan.height)
                gesturePan = .zero
            }
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
            HStack(spacing: 6) {
                transformButton("Level", icon: "level") { model.autoLevel() }
                transformButton("Headshot", icon: "person.crop.square") { model.autoHeadshotCrop() }
                transformButton("Rotate", icon: "rotate.right") {
                    model.edit.rotation = (model.edit.rotation + 90) % 360
                }
                transformButton("Flip H", icon: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                    model.edit.flipH.toggle()
                }
                transformButton("Flip V", icon: "arrow.up.and.down.righttriangle.up.righttriangle.down") {
                    model.edit.flipV.toggle()
                }
            }
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

    private func transformButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 9, weight: .semibold))
                Text(title)
            }
        }
        .buttonStyle(OutlineButtonStyle())
        .clickCursor()
    }

    private func aspectChip(_ title: String, _ aspect: Double?) -> some View {
        Chip(title: title, selected: model.cropAspectName == title) {
            model.applyCropAspect(aspect, name: title)
        }
    }

    /// Gizmo for the selected local adjustment: draggable geometry over the photo.
    @ViewBuilder private func localGizmo(index: Int, fitSize: CGSize) -> some View {
        let local = model.edit.locals[index]
        ZStack {
            switch local.kind {
            case .radial:
                Ellipse()
                    .stroke(Theme.amber.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .frame(width: local.bx * 2 * fitSize.width, height: local.by * 2 * fitSize.height)
                    .position(x: local.ax * fitSize.width, y: local.ay * fitSize.height)
                    .allowsHitTesting(false)
                gizmoHandle(x: local.ax, y: local.ay, fitSize: fitSize) { u, v in
                    model.edit.locals[index].ax = u
                    model.edit.locals[index].ay = v
                }
                gizmoHandle(x: local.ax + local.bx, y: local.ay, fitSize: fitSize) { u, _ in
                    model.edit.locals[index].bx = max(0.02, abs(u - local.ax))
                }
                gizmoHandle(x: local.ax, y: local.ay + local.by, fitSize: fitSize) { _, v in
                    model.edit.locals[index].by = max(0.02, abs(v - local.ay))
                }
            case .linear:
                Path { path in
                    path.move(to: CGPoint(x: local.ax * fitSize.width, y: local.ay * fitSize.height))
                    path.addLine(to: CGPoint(x: local.bx * fitSize.width, y: local.by * fitSize.height))
                }
                .stroke(Theme.amber.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .allowsHitTesting(false)
                gizmoHandle(x: local.ax, y: local.ay, fitSize: fitSize) { u, v in
                    model.edit.locals[index].ax = u
                    model.edit.locals[index].ay = v
                }
                gizmoHandle(x: local.bx, y: local.by, fitSize: fitSize) { u, v in
                    model.edit.locals[index].bx = u
                    model.edit.locals[index].by = v
                }
            case .subject:
                EmptyView()
            }
        }
    }

    private func gizmoHandle(x: Double, y: Double, fitSize: CGSize, onDrag: @escaping (Double, Double) -> Void) -> some View {
        Circle()
            .fill(Theme.amber)
            .frame(width: 11, height: 11)
            .overlay(Circle().stroke(.black.opacity(0.5), lineWidth: 1))
            .contentShape(Circle().inset(by: -9))
            .position(x: x * fitSize.width, y: y * fitSize.height)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        onDrag(
                            Double((g.location.x / fitSize.width).clamped(to: 0...1)),
                            Double((g.location.y / fitSize.height).clamped(to: 0...1))
                        )
                    }
            )
            .clickCursor()
    }

    /// The one slider in the app: a floating glass dial for the armed parameter
    /// (ADR 0005). Drag it, drag the photo, or scroll — same EditState either way.
    @ViewBuilder private var readout: some View {
        if let armedHSL = model.armedHSL {
            let value = model.edit.hsl[armedHSL.band][keyPath: armedHSL.component.keyPath]
            let band = HSLBand.names[armedHSL.band]
            dialCard(
                label: "\(band.prefix(1).uppercased() + band.dropFirst()) \(armedHSL.component.rawValue.lowercased())",
                value: value == 0 ? "0" : String(format: "%+.0f", value),
                t: (value + 100) / 200,
                detents: [0.5],
                doneHelp: "Done — back to pan and zoom (esc)",
                onDrag: { dx in model.scrub(deltaX: dx * 1.6) },
                onDone: { model.armedHSL = nil }
            )
        } else if let armed = model.armed {
            let range = armed.range
            dialCard(
                label: armed.label,
                value: armed.format(armed.value(in: model.edit)),
                t: (armed.value(in: model.edit) - range.lowerBound) / (range.upperBound - range.lowerBound),
                detents: armed.detents.map { ($0 - range.lowerBound) / (range.upperBound - range.lowerBound) },
                doneHelp: "Done — back to pan and zoom (esc)",
                onDrag: { dx in model.scrub(deltaX: dx * 1.6) },
                onDone: { model.armed = nil }
            )
        }
    }

    /// The 3D scene's card: same glass dial, driving Range — Focus is set
    /// spatially (planes, dots) — and its checkmark exits the scene.
    private var depthSceneCard: some View {
        dialCard(
            label: "Range",
            value: EditParameter.focusRange.format(model.edit.focusRange),
            t: model.edit.focusRange,
            detents: [0.25],
            doneHelp: "Exit 3D focus (esc)",
            onDrag: { dx in
                model.edit.focusRange = (model.edit.focusRange + Double(dx) / 260).clamped(to: 0...1)
            },
            onDone: { model.depthSceneCommand = .exit }
        )
    }

    private func dialCard(
        label: String, value: String, t: Double, detents: [Double], doneHelp: String,
        onDrag: @escaping (CGFloat) -> Void, onDone: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                Text(label)
                    .font(Theme.ui(11, .medium))
                    .foregroundStyle(Theme.ink2)
                Text(value)
                    .font(Theme.mono(19, .medium))
                    .foregroundStyle(Theme.amber)
                    .monospacedDigit()
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18)).frame(height: 2)
                ForEach(detents, id: \.self) { dt in
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
                        onDrag(dx)
                    }
                    .onEnded { _ in lastDialX = nil }
            )
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .chiaroGlass(cornerRadius: 15)
        .overlay(alignment: .topTrailing) {
            Button(action: onDone) {
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
            .help(doneHelp)
        }
        .transition(.opacity)
    }
}
