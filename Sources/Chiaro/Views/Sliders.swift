import SwiftUI

/// One adjustment row: label, thin track with amber fill from neutral, mono value.
/// Click arms the parameter for canvas scrubbing (ADR 0005); drag adjusts directly.
struct AdjustmentRow: View {
    let parameter: EditParameter
    @Binding var edit: EditState
    @Binding var armed: EditParameter?
    var disabled = false

    @State private var dragStartValue: Double?

    private var value: Double { parameter.value(in: edit) }
    private var isArmed: Bool { armed == parameter }
    private var isActive: Bool { value != parameter.defaultValue }

    var body: some View {
        HStack(spacing: 8) {
            Text(parameter.label)
                .font(Theme.ui(11.5))
                .foregroundStyle(isArmed ? Theme.amber : Theme.ink2)
                .frame(width: 70, alignment: .leading)
            track
            Text(parameter.format(value))
                .font(Theme.mono(10))
                .foregroundStyle(isActive ? Theme.amber : Theme.ink2)
                .frame(width: 42, alignment: .trailing)
                .monospacedDigit()
        }
        .frame(height: 25)
        .contentShape(Rectangle())
        .opacity(disabled ? 0.35 : 1)
        .allowsHitTesting(!disabled)
        .onTapGesture { armed = isArmed ? nil : parameter }
    }

    private var track: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let range = parameter.range
            let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let neutralT = (parameter.defaultValue - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14)).frame(height: 3)
                Capsule()
                    .fill(Theme.amber)
                    .frame(width: abs(t - neutralT) * width, height: 3)
                    .offset(x: min(t, neutralT) * width)
                Circle()
                    .fill(Color(hex: 0xE6E6E8))
                    .frame(width: 9, height: 9)
                    .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
                    .offset(x: t * width - 4.5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if dragStartValue == nil { dragStartValue = value }
                        let newT = (g.location.x / width).clamped01()
                        var v = range.lowerBound + newT * (range.upperBound - range.lowerBound)
                        v = snapToDetents(v, parameter: parameter, width: width)
                        setValue(v)
                    }
                    .onEnded { _ in dragStartValue = nil }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { setValue(parameter.defaultValue) })
        }
        .frame(height: 22)
    }

    private func setValue(_ v: Double) {
        let old = value
        parameter.set(v, in: &edit)
        HapticDetents.tickIfCrossed(parameter: parameter, from: old, to: parameter.value(in: edit))
    }

    private func snapToDetents(_ v: Double, parameter: EditParameter, width: CGFloat) -> Double {
        let range = parameter.range
        let perPoint = (range.upperBound - range.lowerBound) / width
        for d in parameter.detents where abs(v - d) < perPoint * 3 {
            return d
        }
        return v
    }
}

enum HapticDetents {
    static func tickIfCrossed(parameter: EditParameter, from: Double, to: Double) {
        guard from != to else { return }
        let lo = min(from, to), hi = max(from, to)
        if parameter.detents.contains(where: { $0 >= lo && $0 <= hi }) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}

extension CGFloat {
    func clamped01() -> Double { Double(Swift.min(1, Swift.max(0, self))) }
}
