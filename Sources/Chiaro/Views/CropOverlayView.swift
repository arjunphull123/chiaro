import SwiftUI

/// Crop overlay drawn over the fitted (full, straightened) image: dimmed outside,
/// thirds grid inside, 8 drag handles, drag-inside moves. Coordinates are the
/// normalized CropRect in EditState; `lockedAspect` is a pixel aspect (w/h).
struct CropOverlayView: View {
    @Binding var edit: EditState
    /// Pixel aspect (width/height) of the displayed frame, for aspect locking.
    let frameAspect: Double
    let lockedAspect: Double?

    private enum DragMode: Equatable {
        case move
        case handle(dx: Int, dy: Int) // -1 left/top, 0 center, 1 right/bottom
    }
    @State private var dragMode: DragMode?
    @State private var startCrop: CropRect?

    private let minSide = 0.08

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let rect = CGRect(
                x: edit.crop.x * size.width, y: edit.crop.y * size.height,
                width: edit.crop.w * size.width, height: edit.crop.h * size.height
            )
            ZStack {
                // Dim everything outside the crop.
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: size))
                    p.addRect(rect)
                }
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))

                // Border + thirds.
                Path { p in
                    p.addRect(rect)
                    for i in 1..<3 {
                        let fx = rect.minX + rect.width * CGFloat(i) / 3
                        let fy = rect.minY + rect.height * CGFloat(i) / 3
                        p.move(to: CGPoint(x: fx, y: rect.minY)); p.addLine(to: CGPoint(x: fx, y: rect.maxY))
                        p.move(to: CGPoint(x: rect.minX, y: fy)); p.addLine(to: CGPoint(x: rect.maxX, y: fy))
                    }
                }
                .stroke(Color.white.opacity(0.7), lineWidth: 1)

                ForEach(handles, id: \.0) { _, hx, hy in
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                        .shadow(color: .black.opacity(0.6), radius: 1.5)
                        .position(
                            x: rect.minX + rect.width * CGFloat(hx + 1) / 2,
                            y: rect.minY + rect.height * CGFloat(hy + 1) / 2
                        )
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(size: size))
        }
    }

    private var handles: [(String, Int, Int)] {
        [("nw", -1, -1), ("n", 0, -1), ("ne", 1, -1), ("w", -1, 0),
         ("e", 1, 0), ("sw", -1, 1), ("s", 0, 1), ("se", 1, 1)]
    }

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if dragMode == nil {
                    startCrop = edit.crop
                    dragMode = hitTest(g.startLocation, size: size)
                }
                guard let mode = dragMode, let start = startCrop else { return }
                let dx = Double((g.location.x - g.startLocation.x) / size.width)
                let dy = Double((g.location.y - g.startLocation.y) / size.height)
                var c = start
                switch mode {
                case .move:
                    c.x = (start.x + dx).clamped(to: 0...(1 - start.w))
                    c.y = (start.y + dy).clamped(to: 0...(1 - start.h))
                case .handle(let hx, let hy):
                    if hx == -1 {
                        let newX = (start.x + dx).clamped(to: 0...(start.x + start.w - minSide))
                        c.w = start.w + (start.x - newX); c.x = newX
                    } else if hx == 1 {
                        c.w = (start.w + dx).clamped(to: minSide...(1 - start.x))
                    }
                    if hy == -1 {
                        let newY = (start.y + dy).clamped(to: 0...(start.y + start.h - minSide))
                        c.h = start.h + (start.y - newY); c.y = newY
                    } else if hy == 1 {
                        c.h = (start.h + dy).clamped(to: minSide...(1 - start.y))
                    }
                    if let aspect = lockedAspect {
                        // Normalized w per h that yields the target pixel aspect.
                        let k = aspect / frameAspect
                        if hy == 0 { c.h = (c.w / k).clamped(to: minSide...1) }
                        else { c.w = (c.h * k).clamped(to: minSide...1) }
                        // Keep the anchored corner fixed.
                        if hx == -1 { c.x = start.x + start.w - c.w }
                        if hy == -1 { c.y = start.y + start.h - c.h }
                        c.x = c.x.clamped(to: 0...(1 - c.w))
                        c.y = c.y.clamped(to: 0...(1 - c.h))
                    }
                }
                edit.crop = c
            }
            .onEnded { _ in
                dragMode = nil
                startCrop = nil
            }
    }

    private func hitTest(_ location: CGPoint, size: CGSize) -> DragMode {
        let rect = CGRect(
            x: edit.crop.x * size.width, y: edit.crop.y * size.height,
            width: edit.crop.w * size.width, height: edit.crop.h * size.height
        )
        for (_, hx, hy) in handles {
            let p = CGPoint(
                x: rect.minX + rect.width * CGFloat(hx + 1) / 2,
                y: rect.minY + rect.height * CGFloat(hy + 1) / 2
            )
            if hypot(p.x - location.x, p.y - location.y) < 18 {
                return .handle(dx: hx, dy: hy)
            }
        }
        return .move
    }
}
