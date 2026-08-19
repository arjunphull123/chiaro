import SwiftUI

/// The frosted adjustments rail (ADR 0006): photo header, histogram on a solid
/// plate, grouped adjustments, built-in Looks.
struct RailView: View {
    @Bindable var model: EditViewModel
    let library: Library

    var body: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 12) {
                AgentRailStatus(library: library)
                Group {
                    photoHeader
                    HistogramView(data: model.histogram)
                    section(
                        "Light", [.exposure, .contrast, .highlights, .shadows, .whites, .blacks],
                        help: "Brightness and tonal balance"
                    )
                    curveSection
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
                .opacity(library.agentActive ? 0.4 : 1)
                .animation(.easeOut(duration: 0.2), value: library.agentActive)
            }
            .padding(16)
            .padding(.top, 26) // pill top aligns with the canvas action cluster
        }
        .overlay(alignment: .bottom) {
            // Hints that the rail continues below the fold.
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                .frame(height: 26)
                .allowsHitTesting(false)
        }
        .frame(width: Theme.railWidth)
        .frame(maxHeight: .infinity)
        .background(alignment: .leading) {
            // Heavy frost: strong blur sampled from whatever is behind the window,
            // under a graphite scrim opaque enough to read as material, not photo.
            Rectangle().fill(.ultraThinMaterial)
                .overlay(Theme.panel.opacity(0.52))
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

    private var curveSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text("CURVE")
                    .font(Theme.mono(9.5, .medium))
                    .kerning(1.4)
                    .foregroundStyle(Theme.ink2)
                Rectangle().fill(Theme.hairline).frame(height: 1)
                if model.edit.curve != CurvePoint.identity {
                    Button("Reset") { model.edit.curve = CurvePoint.identity }
                        .buttonStyle(.plain)
        .clickCursor()
                        .font(Theme.ui(9.5))
                        .foregroundStyle(Theme.ink3)
                }
            }
            .padding(.top, 10)
            CurveEditorView(edit: $model.edit, histogram: model.histogram)
        }
        .help("Tone curve — click adds a point, drag shapes it, double-click removes")
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
        .padding(.bottom, 6)
        .help(help)
    }

    private var actions: some View {
        Button {
            model.edit = .neutral
        } label: {
            Text("Reset all")
                .font(Theme.ui(11))
                .foregroundStyle(model.edit.isNeutral ? Theme.ink3 : Theme.ink2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7).stroke(Theme.hairline))
        }
        .buttonStyle(.plain)
        .clickCursor()
        .disabled(model.edit.isNeutral)
        .padding(.top, 14)
    }

    private var scrubHint: some View {
        Text("Tip: click a control, then drag on the photo or the dial — or scroll sideways for fine moves. Hold \\ to compare with the original.")
            .font(Theme.ui(10))
            .foregroundStyle(Theme.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
    }
}
