import SwiftUI

/// The frosted adjustments rail (ADR 0006): heavy-frost glass, histogram on a solid plate.
struct RailView: View {
    @Bindable var model: EditViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                HistogramView(data: model.histogram)
                section("Light", [.exposure, .contrast, .highlights, .shadows, .whites, .blacks])
                section("Color", [.temp, .tint, .vibrance, .saturation])
                portraitSection
                section("Effects", [.clarity, .vignette])
                section("Detail", [.sharpness, .noiseReduction])
                resetButton
            }
            .padding(14)
            .padding(.top, 38)
        }
        .frame(width: Theme.railWidth)
        .frame(maxHeight: .infinity)
        .background(alignment: .leading) {
            // Heavy frost: strong blur sampled from whatever is behind the window,
            // under a graphite scrim opaque enough to read as material, not photo.
            Rectangle().fill(.ultraThinMaterial)
                .overlay(Theme.panel.opacity(0.72))
                .overlay(alignment: .leading) { Theme.hairline.frame(width: 1) }
                .ignoresSafeArea()
        }
    }

    private func section(_ title: String, _ params: [EditParameter]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionLabel(title)
            ForEach(params) { p in
                AdjustmentRow(parameter: p, edit: $model.edit, armed: $model.armed)
            }
        }
    }

    private var portraitSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionLabel("Portrait")
            if model.hasPerson == false {
                Text("no subject found")
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.ink3)
                    .frame(height: 22)
            } else {
                ForEach([EditParameter.blurF, .relight]) { p in
                    AdjustmentRow(
                        parameter: p, edit: $model.edit, armed: $model.armed,
                        disabled: model.hasPerson == nil
                    )
                }
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Theme.mono(9))
            .kerning(1.3)
            .foregroundStyle(Theme.ink3)
            .padding(.top, 8)
    }

    private var resetButton: some View {
        Button {
            model.edit = .neutral
        } label: {
            Text("Reset all")
                .font(Theme.ui(11))
                .foregroundStyle(model.edit.isNeutral ? Theme.ink3 : Theme.ink2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline))
        }
        .buttonStyle(.plain)
        .disabled(model.edit.isNeutral)
        .padding(.top, 12)
    }
}
