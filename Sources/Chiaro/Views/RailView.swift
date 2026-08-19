import SwiftUI

/// The frosted adjustments rail (ADR 0006): photo header, histogram on a solid
/// plate, grouped adjustments, built-in Looks.
struct RailView: View {
    @Bindable var model: EditViewModel
    let library: Library

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                photoHeader
                HistogramView(data: model.histogram)
                looks
                section(
                    "Light", [.exposure, .contrast, .highlights, .shadows, .whites, .blacks],
                    help: "Brightness and tonal balance"
                )
                section(
                    "Color", [.temp, .tint, .vibrance, .saturation],
                    help: "White balance and color strength"
                )
                portraitSection
                section("Effects", [.clarity, .vignette], help: "Punch and framing")
                section("Detail", [.sharpness, .noiseReduction], help: "Fine texture and grain cleanup")
                actions
                scrubHint
            }
            .padding(16)
            .padding(.top, 40)
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

    private var photoHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(model.photo.name)
                    .font(Theme.ui(14, .semibold))
                    .foregroundStyle(Theme.ink)
                if model.photo.isRAW {
                    Text("RAW")
                        .font(Theme.mono(8, .medium)).kerning(1)
                        .foregroundStyle(Theme.amber)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).stroke(Theme.amber.opacity(0.5)))
                }
            }
            if let exif = model.photo.exifSummary {
                Text(exif)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.ink2)
            }
            if let date = model.photo.captureDate {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.ink3)
            }
        }
    }

    /// Looks carousel: each card previews THIS photo with the preset applied.
    private var looks: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Looks", help: "One-tap starting points — tweak anything after")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(Preset.builtIn) { preset in
                        lookCard(preset)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func lookCard(_ preset: Preset) -> some View {
        let isCurrent = model.edit == preset.applied(over: model.edit)
        return Button {
            model.edit = preset.applied(over: model.edit)
        } label: {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let cg = model.presetPreviews[preset.name] {
                        Image(cg, scale: 1, label: Text(preset.name))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.white.opacity(0.06)
                    }
                }
                .frame(width: 104, height: 66)
                LinearGradient(
                    colors: [.clear, .black.opacity(0.75)],
                    startPoint: .center, endPoint: .bottom
                )
                Text(preset.name)
                    .font(Theme.ui(9.5, .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 6)
                    .padding(.bottom, 5)
            }
            .frame(width: 104, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isCurrent ? Theme.amber : Theme.hairline, lineWidth: isCurrent ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func section(_ title: String, _ params: [EditParameter], help: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionLabel(title, help: help)
            ForEach(params) { p in
                AdjustmentRow(parameter: p, edit: $model.edit, armed: $model.armed, hovered: $model.hovered)
            }
        }
    }

    private var portraitSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionLabel("Portrait", help: "Background blur and subject light, from AI person detection")
            switch model.hasPerson {
            case .none:
                Text("finding subject…")
                    .font(Theme.mono(10)).foregroundStyle(Theme.ink3)
                    .frame(height: 24)
            case .some(false):
                Text("no person found in this photo")
                    .font(Theme.mono(10)).foregroundStyle(Theme.ink3)
                    .frame(height: 24)
            case .some(true):
                ForEach([EditParameter.blurF, .relight, .maskReach]) { p in
                    AdjustmentRow(parameter: p, edit: $model.edit, armed: $model.armed, hovered: $model.hovered)
                }
            }
        }
    }

    private func sectionLabel(_ title: String, help: String) -> some View {
        HStack(spacing: 5) {
            Text(title.uppercased())
                .font(Theme.mono(9.5, .medium))
                .kerning(1.4)
                .foregroundStyle(Theme.ink2)
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .padding(.top, 10)
        .help(help)
    }

    private var actions: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                secondaryButton("Copy Edit", disabled: model.edit.isNeutral) {
                    library.copiedEdit = model.edit
                }
                secondaryButton("Paste Edit", disabled: library.copiedEdit == nil) {
                    if let copied = library.copiedEdit { model.edit = copied }
                }
            }
            secondaryButton("Reset all", disabled: model.edit.isNeutral) {
                model.edit = .neutral
            }
        }
        .padding(.top, 14)
    }

    private func secondaryButton(_ title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.ui(11))
                .foregroundStyle(disabled ? Theme.ink3 : Theme.ink2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7).stroke(Theme.hairline))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var scrubHint: some View {
        Text("Tip: click a control's name, then drag left–right anywhere on the photo. Hold \\ to compare with the original.")
            .font(Theme.ui(10))
            .foregroundStyle(Theme.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
    }
}
