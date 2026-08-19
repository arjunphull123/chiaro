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
    @State private var typing = false
    @State private var typedText = ""
    @FocusState private var typingFocused: Bool

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
            if typing {
                TextField("", text: $typedText)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.amber)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                    .focused($typingFocused)
                    // Focus only once the field exists — setting it earlier
                    // loses the race and the field dismisses itself.
                    .onAppear { typingFocused = true }
                    .onSubmit { commitTyped() }
                    .onExitCommand { typing = false }
                    .onChange(of: typingFocused) { was, now in
                        if was, !now { commitTyped() }
                    }
            } else {
                Text(parameter.format(value))
                    .font(Theme.mono(10))
                    .foregroundStyle(isActive ? Theme.amber : Theme.ink2)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(isArmed ? 0.10 : 0.05)))
                    .overlay(Capsule().stroke(isArmed ? Theme.amber.opacity(0.6) : Theme.hairline))
                    .onTapGesture { beginTyping() }
            }
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
        .help("Click to adjust — drag the photo or the dial, scroll sideways, or click the value to type. Double-click resets.")
    }

    /// Typed values arrive in display units — ƒ-stops for blur, EV, degrees.
    private func beginTyping() {
        let raw = parameter == .blurF
            ? (value <= 0.001 ? 16 : 16 * pow(1.4 / 16, value))
            : value
        typedText = value == parameter.defaultValue ? "" : String(format: "%.4g", raw)
        typing = true
        armed = parameter
    }

    private func commitTyped() {
        defer { typing = false }
        let cleaned = typedText.replacingOccurrences(of: "ƒ", with: "")
            .replacingOccurrences(of: "°", with: "").trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty {
            parameter.set(parameter.defaultValue, in: &edit)
            return
        }
        guard let typed = Double(cleaned) else { return }
        let newValue = parameter == .blurF
            ? (typed >= 15.9 ? 0 : (log(16 / typed.clamped(to: 1.4...16)) / log(16 / 1.4)))
            : typed
        parameter.set(newValue, in: &edit)
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
