import SwiftUI

/// One adjustment row: name and value only — clean, no track (v3 interaction).
/// Click arms the parameter: the canvas becomes its control surface and the glass
/// dial overlay appears (ADR 0005). Scroll over the row nudges it directly;
/// double-click resets.
struct AdjustmentRow: View {
    let parameter: EditParameter
    @Binding var edit: EditState
    @Binding var armed: EditParameter?
    @Binding var hovered: EditParameter?
    var disabled = false

    private var value: Double { parameter.value(in: edit) }
    private var isArmed: Bool { armed == parameter }
    private var isActive: Bool { value != parameter.defaultValue }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isArmed ? Theme.amber : .clear)
                .frame(width: 4, height: 4)
            Text(parameter.label)
                .font(Theme.ui(11.5, isArmed ? .medium : .regular))
                .foregroundStyle(isArmed ? Theme.ink : Theme.ink2)
            Spacer()
            Text(parameter.format(value))
                .font(Theme.mono(10.5))
                .foregroundStyle(isActive ? Theme.amber : Theme.ink3)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isArmed ? Color.white.opacity(0.07) : (hovered == parameter ? Color.white.opacity(0.04) : .clear))
        )
        .contentShape(Rectangle())
        .opacity(disabled ? 0.35 : 1)
        .allowsHitTesting(!disabled)
        .onTapGesture { armed = isArmed ? nil : parameter }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            parameter.set(parameter.defaultValue, in: &edit)
        })
        .onHover { inside in
            if inside { hovered = parameter }
            else if hovered == parameter { hovered = nil }
        }
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
