import Foundation

/// Monotone cubic interpolation (Fritsch–Carlson) through curve control points —
/// smooth between points, never overshoots, standard for tone curves.
enum CurveSampler {
    static func sample(_ points: [CurvePoint], count: Int) -> [Float] {
        let pts = points.sorted { $0.x < $1.x }
        guard pts.count >= 2 else {
            return (0..<count).map { Float($0) / Float(count - 1) }
        }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        let n = pts.count

        // Secant slopes, then Fritsch–Carlson tangents.
        var delta = [Double](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            let dx = max(xs[i + 1] - xs[i], 1e-6)
            delta[i] = (ys[i + 1] - ys[i]) / dx
        }
        var m = [Double](repeating: 0, count: n)
        m[0] = delta[0]
        m[n - 1] = delta[n - 2]
        for i in 1..<(n - 1) {
            m[i] = delta[i - 1] * delta[i] <= 0 ? 0 : (delta[i - 1] + delta[i]) / 2
        }
        for i in 0..<(n - 1) where delta[i] != 0 {
            let a = m[i] / delta[i], b = m[i + 1] / delta[i]
            let s = a * a + b * b
            if s > 9 {
                let t = 3 / s.squareRoot()
                m[i] = t * a * delta[i]
                m[i + 1] = t * b * delta[i]
            }
        }

        return (0..<count).map { step in
            let x = Double(step) / Double(count - 1)
            if x <= xs[0] { return Float(ys[0].clamped(to: 0...1)) }
            if x >= xs[n - 1] { return Float(ys[n - 1].clamped(to: 0...1)) }
            var i = 0
            while i < n - 2 && x > xs[i + 1] { i += 1 }
            let h = max(xs[i + 1] - xs[i], 1e-6)
            let t = (x - xs[i]) / h
            let t2 = t * t, t3 = t2 * t
            let y = ys[i] * (2 * t3 - 3 * t2 + 1)
                + m[i] * h * (t3 - 2 * t2 + t)
                + ys[i + 1] * (-2 * t3 + 3 * t2)
                + m[i + 1] * h * (t3 - t2)
            return Float(y.clamped(to: 0...1))
        }
    }
}
