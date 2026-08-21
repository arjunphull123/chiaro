import SwiftUI
import TipKit

/// The photo canvas: fits inside the region left of the rail, zoomable and pannable
/// (may slide under the rail when zoomed), and doubles as the scrub surface when a
/// parameter is armed (ADR 0005).
struct CanvasView: View {
    @Bindable var model: EditViewModel

    private var zoom: CGFloat {
        get { model.canvasZoom }
        nonmutating set { model.canvasZoom = newValue }
    }
    private var pan: CGSize {
        get { model.canvasPan }
        nonmutating set { model.canvasPan = newValue }
    }
    @State private var gestureZoom: CGFloat = 1
    @State private var gesturePan: CGSize = .zero
    @State private var lastScrubX: CGFloat?
    @State private var lastDialX: CGFloat?


    var body: some View {
        GeometryReader { geo in
            let fitRegion = CGSize(width: geo.size.width - Theme.railWidth, height: geo.size.height)
            ZStack {
                Color.black.opacity(0.001) // hit target for gestures on empty canvas
                if model.depthSceneVisible {
                    DepthSceneView(
                        model: model, fitFraction: fitFraction(in: fitRegion),
                        yaw: model.sceneYaw, pitch: model.scenePitch,
                        focusDepth: model.edit.focusDepth
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
            // Bottom left, beside the nav pill rather than over the photo's top
            // corner where it crowded the toolbar. A bare TipView draws no
            // surface of its own, so it needs the same glass treatment as every
            // other transient here (ADR 0004) or it is illegible over a bright
            // frame.
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    TipView(ScrubTip())
                        .chiaroGlass(cornerRadius: 12)
                    if model.armed != nil || model.armedLocal != nil {
                        TipView(FineTuneTip())
                            .chiaroGlass(cornerRadius: 12)
                    }
                }
                .frame(maxWidth: 320)
                .padding(.bottom, 16)
                .padding(.leading, 16)
                .padding(.trailing, Theme.railWidth)
            }
            .onChange(of: model.pixelZoomRequested) {
                guard model.pixelZoomRequested else { return }
                model.pixelZoomRequested = false
                guard let cg = model.preview else { return }
                let fitScale = min(
                    (fitRegion.width - 48) / CGFloat(cg.width),
                    (fitRegion.height - 48) / CGFloat(cg.height)
                )
                // zoom 1 shows fitScale× pixels; 1/fitScale shows them 1:1.
                withAnimation(.easeOut(duration: 0.2)) {
                    model.canvasZoom = fitScale >= 1 ? 1 : 1 / fitScale
                    model.canvasPan = .zero
                }
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
                } else if model.armed != nil || model.armedHSL != nil || model.armedLocal != nil {
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

    /// Whether a dial card (readout or depth focus) is on screen.
    private var dialActive: Bool { model.armed != nil || model.armedHSL != nil || model.armedLocal != nil }

    /// Crop mode controls: aspect dropdown, straighten arc, reset, done.
    /// Same grammar as the dial cards — the value being set sits centered up top.
    private var cropPanel: some View {
        VStack(spacing: 8) {
            ZStack {
                HStack(spacing: 6) {
                    aspectMenu
                    Spacer()
                    Button { model.edit.straighten = 0 } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(GlassIconButtonStyle())
                    .clickCursor()
                    .disabled(model.edit.straighten == 0)
                    .help("Clear straighten")
                    Button("Auto") { model.autoLevel() }
                        .buttonStyle(GlassButtonStyle(tint: Theme.amber))
                        .clickCursor()
                        .help("Level the horizon automatically")
                }
                // Centered alone so the number sits exactly over the arc's center tick.
                Text(EditParameter.straighten.format(model.edit.straighten))
                    .font(Theme.mono(17, .medium))
                    .foregroundStyle(Theme.amber)
                    .monospacedDigit()
                    .fixedSize()
            }
            .frame(width: 264)
            ArcRuler(value: straightenBinding)
                .frame(width: 264, height: 46)
            HStack(spacing: 8) {
                Button("Reset") {
                    model.edit.crop = .full
                    model.edit.straighten = 0
                    model.edit.skewV = 0
                    model.edit.skewH = 0
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
        .fixedSize()
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
                // The arc keeps its own unsnapped anchor, so capture alone
                // gives the detent feel — no accumulator needed here.
                let snapped = abs(newValue) < 0.5 ? 0 : newValue
                model.edit.straighten = snapped
                HapticDetents.ticks(span: 90, from: old, to: snapped, detent: 0)
            }
        )
    }

    private var aspectOptions: [(name: String, ratio: Double?)] {
        [("Free", nil), ("Original", originalAspect), ("1:1", 1), ("4:5", 0.8), ("3:2", 1.5), ("16:9", 16.0 / 9)]
    }

    private var aspectMenu: some View {
        let currentName = model.cropAspectName ?? "Free"
        let current = aspectOptions.first { $0.name == currentName }
        return Menu {
            ForEach(aspectOptions, id: \.name) { option in
                Button {
                    model.applyCropAspect(option.ratio, name: option.name)
                } label: {
                    if option.name == currentName {
                        Label(option.name, systemImage: "checkmark")
                    } else {
                        Text(option.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                aspectGlyph(current?.ratio ?? nil, selected: false)
                Text(currentName)
                    .font(Theme.ui(10.5, .medium))
                    .foregroundStyle(Theme.ink)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.05)))
            .overlay(Capsule().stroke(Theme.hairline))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .clickCursor()
        .help("Lock the crop to a ratio")
    }

    /// Mini frame preview inside an aspect chip — a dashed square stands
    /// in for "no fixed ratio" (Free, or Original when it's not yet known).
    @ViewBuilder private func aspectGlyph(_ aspect: Double?, selected: Bool) -> some View {
        let color = selected ? Theme.amber : Theme.ink2
        if let aspect {
            RoundedRectangle(cornerRadius: 1.5)
                .stroke(color, lineWidth: 1)
                .frame(width: min(16, 9 * aspect), height: 9)
        } else {
            Rectangle()
                .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .frame(width: 9, height: 11)
        }
    }

    /// Gizmo for the selected local adjustment: draggable geometry over the photo.
    @ViewBuilder private func localGizmo(index: Int, fitSize: CGSize) -> some View {
        let local = model.edit.locals[index]
        // The drag closures below escape past this render pass — capture the
        // adjustment's id, not this index, and re-resolve it when they fire
        // (an agent's set_edit can shrink `locals` mid-drag).
        let id = local.id
        let resolve: () -> Int? = { model.edit.locals.firstIndex(where: { $0.id == id }) }
        ZStack {
            switch local.kind {
            case .radial:
                Ellipse()
                    .stroke(Theme.amber.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .frame(width: local.bx * 2 * fitSize.width, height: local.by * 2 * fitSize.height)
                    .position(x: local.ax * fitSize.width, y: local.ay * fitSize.height)
                    .allowsHitTesting(false)
                gizmoHandle(x: local.ax, y: local.ay, fitSize: fitSize) { u, v in
                    guard let i = resolve() else { return }
                    model.edit.locals[i].ax = u
                    model.edit.locals[i].ay = v
                }
                gizmoHandle(x: local.ax + local.bx, y: local.ay, fitSize: fitSize) { u, _ in
                    guard let i = resolve() else { return }
                    model.edit.locals[i].bx = max(0.02, abs(u - local.ax))
                }
                gizmoHandle(x: local.ax, y: local.ay + local.by, fitSize: fitSize) { _, v in
                    guard let i = resolve() else { return }
                    model.edit.locals[i].by = max(0.02, abs(v - local.ay))
                }
            case .linear:
                Path { path in
                    path.move(to: CGPoint(x: local.ax * fitSize.width, y: local.ay * fitSize.height))
                    path.addLine(to: CGPoint(x: local.bx * fitSize.width, y: local.by * fitSize.height))
                }
                .stroke(Theme.amber.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .allowsHitTesting(false)
                gizmoHandle(x: local.ax, y: local.ay, fitSize: fitSize) { u, v in
                    guard let i = resolve() else { return }
                    model.edit.locals[i].ax = u
                    model.edit.locals[i].ay = v
                }
                gizmoHandle(x: local.bx, y: local.by, fitSize: fitSize) { u, v in
                    guard let i = resolve() else { return }
                    model.edit.locals[i].bx = u
                    model.edit.locals[i].by = v
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
                onReset: {
                    if let a = model.armedHSL { model.edit.hsl[a.band][keyPath: a.component.keyPath] = 0 }
                },
                onDone: { model.armedHSL = nil }
            )
        } else if let armedLocal = model.armedLocal,
                  let i = model.edit.locals.firstIndex(where: { $0.id == armedLocal.id }) {
            let local = model.edit.locals[i]
            let keyPath = armedLocal.keyPath
            let range = armedLocal.range
            let value = local[keyPath: keyPath]
            let isEV = range.upperBound <= 3
            let defaultValue = LocalAdjustment.defaults[keyPath: keyPath]
            let kindName = local.kind.rawValue.prefix(1).uppercased() + local.kind.rawValue.dropFirst()
            dialCard(
                label: "\(kindName) \(i + 1) · \(armedLocal.label)",
                value: isEV ? String(format: "%+.2f", value) : (value == 0 ? "0" : String(format: "%+.0f", value)),
                t: (value - range.lowerBound) / (range.upperBound - range.lowerBound),
                detents: [(defaultValue - range.lowerBound) / (range.upperBound - range.lowerBound)],
                doneHelp: "Done — back to pan and zoom (esc)",
                onDrag: { dx in model.scrub(deltaX: dx * 1.6) },
                onReset: {
                    if let idx = model.edit.locals.firstIndex(where: { $0.id == armedLocal.id }) {
                        model.edit.locals[idx][keyPath: keyPath] = defaultValue
                    }
                },
                onDone: { model.armedLocal = nil }
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
                onReset: { armed.set(armed.defaultValue, in: &model.edit) },
                onDone: { model.armed = nil }
            )
        }
    }

    /// The 3D scene's card: the same glass dial, driving the focus plane —
    /// exactly what dragging the plane does. Done exits the scene.
    private var depthSceneCard: some View {
        dialCard(
            label: "Focus",
            value: EditParameter.focusDepth.format(model.edit.focusDepth),
            t: model.edit.focusDepth,
            detents: [0.5],
            doneHelp: "Exit 3D focus (esc)",
            onDrag: { dx in model.scrubFocusDepth(deltaX: dx) },
            onReset: { model.edit.focusDepth = EditParameter.focusDepth.defaultValue },
            onDone: { model.depthSceneCommand = .exit }
        )
    }

    private func dialCard(
        label: String, value: String, t: Double, detents: [Double], doneHelp: String,
        onDrag: @escaping (CGFloat) -> Void, onReset: @escaping () -> Void, onDone: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(label)
                    .font(Theme.ui(13, .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(value)
                    .font(Theme.mono(19, .medium))
                    .foregroundStyle(Theme.amber)
                    .monospacedDigit()
            }
            // The scale slides under a fixed center marker — the current
            // value is always at the middle, ticks move with the drag.
            ZStack {
                Canvas { context, size in
                    let width = size.width
                    let offset = (0.5 - t) * width
                    for i in 0...48 {
                        let x = CGFloat(i) / 48 * width + offset
                        guard x >= 0, x <= width else { continue }
                        let major = i % 6 == 0
                        let height: CGFloat = major ? 13 : 9
                        context.fill(
                            Path(CGRect(x: x - 0.5, y: (size.height - height) / 2, width: 1, height: height)),
                            with: .color(.white.opacity(major ? 0.42 : 0.2))
                        )
                    }
                    for dt in detents {
                        let x = dt * width + offset
                        guard x >= 0, x <= width else { continue }
                        context.fill(
                            Path(CGRect(x: x - 0.75, y: (size.height - 13) / 2, width: 1.5, height: 13)),
                            with: .color(.white.opacity(0.6))
                        )
                    }
                    // Fixed center marker: the value.
                    context.fill(
                        Path(roundedRect: CGRect(x: width / 2 - 1.25, y: 1, width: 2.5, height: size.height - 2), cornerRadius: 1.25),
                        with: .color(Theme.amber)
                    )
                }
                .frame(width: 260, height: 20)
                .shadow(color: Theme.amber.opacity(0.25), radius: 3)
            }
            .contentShape(Rectangle().inset(by: -10))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let dx = g.location.x - (lastDialX ?? g.startLocation.x)
                        lastDialX = g.location.x
                        onDrag(-dx) // the scale follows the finger
                    }
                    .onEnded { _ in lastDialX = nil }
            )
            HStack(spacing: 14) {
                Button("Reset", action: onReset)
                    .buttonStyle(.plain)
                    .font(Theme.ui(10.5, .medium))
                    .foregroundStyle(Theme.ink3)
                    .clickCursor()
                Button("Done", action: onDone)
                    .buttonStyle(.plain)
                    .font(Theme.ui(10.5, .medium))
                    .foregroundStyle(Theme.amber)
                    .clickCursor()
                    .help(doneHelp)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .chiaroGlass(cornerRadius: 15)
        .transition(.opacity)
    }
}


/// Curved rotation ruler (the Photos-style arc): the degree scale slides
/// under a fixed center marker, following the finger.
struct ArcRuler: View {
    @Binding var value: Double
    @State private var startValue: Double?

    var body: some View {
        Canvas { context, size in
            let radius: CGFloat = 330
            let center = CGPoint(x: size.width / 2, y: radius + 10)
            for degree in stride(from: -45, through: 45, by: 1) {
                let relative = Double(degree) - value
                guard abs(relative) <= 20 else { continue }
                let angle = relative * .pi / 180 * 1.1 - .pi / 2
                let major = degree % 5 == 0
                let length: CGFloat = major ? 12 : 7
                let outer = CGPoint(
                    x: center.x + cos(angle) * radius,
                    y: center.y + sin(angle) * radius
                )
                let inner = CGPoint(
                    x: center.x + cos(angle) * (radius - length),
                    y: center.y + sin(angle) * (radius - length)
                )
                var path = Path()
                path.move(to: outer)
                path.addLine(to: inner)
                let fade = 1 - abs(relative) / 24
                context.stroke(path, with: .color(.white.opacity((major ? 0.42 : 0.2) * fade)), lineWidth: 1)
                if major {
                    let labelPoint = CGPoint(
                        x: center.x + cos(angle) * (radius - 20),
                        y: center.y + sin(angle) * (radius - 20)
                    )
                    context.draw(
                        Text("\(degree)").font(.system(size: 7, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35 * fade)),
                        at: labelPoint
                    )
                }
            }
            // Fixed marker: the current angle.
            var marker = Path()
            marker.move(to: CGPoint(x: size.width / 2, y: 2))
            marker.addLine(to: CGPoint(x: size.width / 2, y: 18))
            context.stroke(marker, with: .color(Theme.amber), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if startValue == nil { startValue = value }
                    guard let startValue else { return }
                    // The scale follows the finger.
                    var new = (startValue - Double(g.translation.width) / 6).clamped(to: -45...45)
                    if abs(new) < 0.4 { new = 0 }
                    value = new
                }
                .onEnded { _ in startValue = nil }
        )
        .onTapGesture(count: 2) { value = 0 }
        .clickCursor()
        .help("Drag to straighten — double-click resets")
    }
}
