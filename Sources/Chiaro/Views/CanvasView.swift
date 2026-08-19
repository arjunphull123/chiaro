import SwiftUI

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
                if let cg = model.showOriginal ? model.originalPreview : model.preview {
                    let imageSize = CGSize(width: cg.width, height: cg.height)
                    let fitScale = min(
                        (fitRegion.width - 48) / imageSize.width,
                        (fitRegion.height - 48) / imageSize.height
                    )
                    Image(cg, scale: 1, label: Text(model.photo.name))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: imageSize.width * fitScale, height: imageSize.height * fitScale)
                        .scaleEffect(zoom * gestureZoom)
                        .offset(x: pan.width + gesturePan.width, y: pan.height + gesturePan.height)
                        .position(x: fitRegion.width / 2, y: fitRegion.height / 2)
                        .shadow(color: .black.opacity(0.45), radius: 24, y: 8)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .position(x: fitRegion.width / 2, y: fitRegion.height / 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .gesture(magnifyGesture)
            .onTapGesture(count: 2) { toggleZoom() }
            .overlay(alignment: .bottom) { readout.padding(.bottom, 78).padding(.trailing, Theme.railWidth) }
            .onChange(of: model.photo.url) { resetView() }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { g in
                if model.armed != nil {
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

    /// The one slider in the app: a floating glass dial for the armed parameter
    /// (ADR 0005). Drag it, drag the photo, or scroll — same EditState either way.
    @ViewBuilder private var readout: some View {
        if let armed = model.armed {
            let range = armed.range
            let t = (armed.value(in: model.edit) - range.lowerBound) / (range.upperBound - range.lowerBound)
            VStack(spacing: 7) {
                HStack(spacing: 10) {
                    Text(armed.label.uppercased())
                        .font(Theme.mono(9))
                        .kerning(1.6)
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
            .transition(.opacity)
        }
    }
}
