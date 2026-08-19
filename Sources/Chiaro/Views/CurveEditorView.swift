import SwiftUI

/// Interactive tone curve: drag points, click empty space to add one (max 8),
/// double-click a point to remove it, endpoints move vertically only.
/// Luminance histogram sits behind the grid for context.
struct CurveEditorView: View {
    @Binding var edit: EditState
    let histogram: HistogramData

    @State private var draggingIndex: Int?

    private let maxPoints = 8

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                background(size)
                curveAndPoints(size)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(size))
            .gesture(SpatialTapGesture(count: 2).onEnded { removePoint(at: $0.location, in: size) })
        }
        .aspectRatio(1.45, contentMode: .fit)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.28)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func background(_ size: CGSize) -> some View {
        Canvas { ctx, _ in
            // Luminance histogram, faint, behind everything.
            if !histogram.isEmpty {
                let bins = histogram.red.indices.map {
                    (histogram.red[$0] + histogram.green[$0] + histogram.blue[$0]) / 3
                }
                var hist = Path()
                let step = size.width / CGFloat(bins.count - 1)
                hist.move(to: CGPoint(x: 0, y: size.height))
                for (i, v) in bins.enumerated() {
                    hist.addLine(to: CGPoint(x: CGFloat(i) * step, y: size.height - CGFloat(v) * size.height * 0.85))
                }
                hist.addLine(to: CGPoint(x: size.width, y: size.height))
                hist.closeSubpath()
                ctx.fill(hist, with: .color(.white.opacity(0.07)))
            }
            // Quarter grid + identity diagonal.
            var grid = Path()
            for i in 1..<4 {
                let f = CGFloat(i) / 4
                grid.move(to: CGPoint(x: f * size.width, y: 0))
                grid.addLine(to: CGPoint(x: f * size.width, y: size.height))
                grid.move(to: CGPoint(x: 0, y: f * size.height))
                grid.addLine(to: CGPoint(x: size.width, y: f * size.height))
            }
            ctx.stroke(grid, with: .color(.white.opacity(0.06)), lineWidth: 1)
            var diagonal = Path()
            diagonal.move(to: CGPoint(x: 0, y: size.height))
            diagonal.addLine(to: CGPoint(x: size.width, y: 0))
            ctx.stroke(diagonal, with: .color(.white.opacity(0.12)), style: .init(lineWidth: 1, dash: [3, 4]))
        }
    }

    private func curveAndPoints(_ size: CGSize) -> some View {
        Canvas { ctx, _ in
            let samples = CurveSampler.sample(edit.curve, count: 120)
            var path = Path()
            for (i, y) in samples.enumerated() {
                let pt = CGPoint(
                    x: CGFloat(i) / CGFloat(samples.count - 1) * size.width,
                    y: (1 - CGFloat(y)) * size.height
                )
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            ctx.stroke(path, with: .color(Theme.amber), lineWidth: 1.8)
            for (i, p) in edit.curve.enumerated() {
                let center = point(p, in: size)
                let r: CGFloat = draggingIndex == i ? 6 : 4.5
                let dot = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                ctx.fill(dot, with: .color(Theme.amber))
                ctx.stroke(dot, with: .color(.black.opacity(0.5)), lineWidth: 1)
            }
        }
    }

    private func point(_ p: CurvePoint, in size: CGSize) -> CGPoint {
        CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height)
    }

    private func value(at location: CGPoint, in size: CGSize) -> CurvePoint {
        CurvePoint(
            x: Double(location.x / size.width).clamped(to: 0...1),
            y: Double(1 - location.y / size.height).clamped(to: 0...1)
        )
    }

    private func nearestIndex(to location: CGPoint, in size: CGSize, within: CGFloat) -> Int? {
        var best: (Int, CGFloat)?
        for (i, p) in edit.curve.enumerated() {
            let c = point(p, in: size)
            let d = hypot(c.x - location.x, c.y - location.y)
            if d < within && d < (best?.1 ?? .infinity) { best = (i, d) }
        }
        return best?.0
    }

    private func dragGesture(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if draggingIndex == nil {
                    if let hit = nearestIndex(to: g.startLocation, in: size, within: 16) {
                        draggingIndex = hit
                    } else if edit.curve.count < maxPoints {
                        // Add a point where clicked and start dragging it.
                        let p = value(at: g.startLocation, in: size)
                        let insert = edit.curve.firstIndex { $0.x > p.x } ?? edit.curve.count
                        edit.curve.insert(p, at: insert)
                        draggingIndex = insert
                    } else {
                        return
                    }
                }
                guard let i = draggingIndex else { return }
                var p = value(at: g.location, in: size)
                let isFirst = i == 0, isLast = i == edit.curve.count - 1
                if isFirst { p.x = 0 }
                if isLast { p.x = 1 }
                if !isFirst { p.x = max(p.x, edit.curve[i - 1].x + 0.02) }
                if !isLast { p.x = min(p.x, edit.curve[i + 1].x - 0.02) }
                edit.curve[i] = p
            }
            .onEnded { _ in draggingIndex = nil }
    }

    private func removePoint(at location: CGPoint, in size: CGSize) {
        guard let i = nearestIndex(to: location, in: size, within: 14),
              i != 0, i != edit.curve.count - 1 else { return }
        edit.curve.remove(at: i)
    }
}
