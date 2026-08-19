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

    private var isHovered: Bool { hovered == parameter }

    var body: some View {
        HStack(spacing: 8) {
            Text(parameter.label)
                .font(Theme.ui(11.5, isArmed ? .medium : .regular))
                .foregroundStyle(isArmed ? Theme.ink : Theme.ink2)
            Spacer()
            Text(parameter.format(value))
                .font(Theme.mono(10))
                .foregroundStyle(isActive ? Theme.amber : Theme.ink2)
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(isArmed ? 0.10 : 0.05)))
                .overlay(Capsule().stroke(isArmed ? Theme.amber.opacity(0.6) : Theme.hairline))
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.white.opacity(isArmed ? 0.08 : (isHovered ? 0.06 : 0.03)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isArmed ? Theme.amber.opacity(0.4) : (isHovered ? Color.white.opacity(0.12) : .clear))
        )
        .contentShape(Rectangle())
        .opacity(disabled ? 0.35 : 1)
        .allowsHitTesting(!disabled)
        .onTapGesture { armed = isArmed ? nil : parameter }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            parameter.set(parameter.defaultValue, in: &edit)
        })
        .onHover { inside in
            if inside {
                hovered = parameter
                NSCursor.pointingHand.push()
            } else if hovered == parameter {
                hovered = nil
                NSCursor.pop()
            }
        }
        .help("Click to adjust — then drag the photo or the dial, or scroll sideways. Double-click resets.")
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
