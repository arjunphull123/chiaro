import SwiftUI

/// The frosted adjustments rail (ADR 0006): photo header, histogram on a solid
/// plate, grouped adjustments, built-in Looks.
struct RailView: View {
    @Bindable var model: EditViewModel
    let library: Library

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pinned above the fold: agent presence and the photo's identity.
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    AppMark(size: 30)
                    AgentRailStatus(library: library)
                }
                photoHeader
                    .opacity(library.agentActive ? 0.4 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 42) // aligns with the canvas action cluster
            .padding(.bottom, 12)
            scroll
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

    private var scroll: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 12) {
                Group {
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
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .overlay(alignment: .bottom) {
            // Hints that the rail continues below the fold.
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                .frame(height: 26)
                .allowsHitTesting(false)
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
                Text("Curve")
                    .font(Theme.ui(12, .medium))
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
            sectionLabel("Portrait", help: "Background blur — by lifted subject or by scene depth — and subject light")
            HStack(spacing: 6) {
                Chip(title: "Subject", selected: model.edit.blurMode == .subject) { model.setBlurMode(.subject) }
                Chip(title: "Person", selected: model.edit.blurMode == .person) { model.setBlurMode(.person) }
                Chip(title: "Lens", selected: model.edit.blurMode == .depth) { model.setBlurMode(.depth) }
            }
            .padding(.bottom, 4)
            if model.edit.blurMode == .depth {
                depthContent
            } else {
                subjectContent
            }
        }
    }

    @ViewBuilder private var subjectContent: some View {
        switch model.hasPerson {
        case .none:
            Text(model.edit.blurMode == .person ? "Finding person…" : "Finding subject…")
                .font(Theme.ui(10.5)).foregroundStyle(Theme.ink3)
                .frame(height: 24)
        case .some(false):
            Text(model.edit.blurMode == .person ? "No person found in this photo" : "No subject found in this photo")
                .font(Theme.ui(10.5)).foregroundStyle(Theme.ink3)
                .frame(height: 24)
        case .some(true):
            ForEach([EditParameter.blurF, .relight, .maskReach]) { p in
                AdjustmentRow(parameter: p, edit: $model.edit, armed: $model.armed, hovered: $model.hovered)
            }
        }
    }

    /// Depth-map blur: the model is an opt-in 50 MB download on first use.
    @ViewBuilder private var depthContent: some View {
        switch DepthModelStore.shared.availability {
        case .missing:
            Button("Download depth model (50 MB)") {
                DepthModelStore.shared.downloadIfNeeded()
            }
            .buttonStyle(OutlineButtonStyle())
            .clickCursor()
            .help("Apple's Depth Anything V2, run on-device — enables focus-plane blur")
        case .downloading(let progress):
            HStack(spacing: 7) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Theme.amber)
                Text("\(Int(progress * 100))%")
                    .font(Theme.mono(9)).foregroundStyle(Theme.ink3).monospacedDigit()
            }
            .frame(height: 24)
        case .preparing:
            Text("Preparing the model…")
                .font(Theme.ui(10.5)).foregroundStyle(Theme.ink3)
                .frame(height: 24)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(Theme.mono(9)).foregroundStyle(Theme.ink3)
                    .lineLimit(2)
                Button("Try again") { DepthModelStore.shared.downloadIfNeeded() }
                    .buttonStyle(OutlineButtonStyle())
                    .clickCursor()
            }
        case .ready:
            Button {
                if model.depthSceneVisible {
                    model.depthSceneCommand = .exit
                } else {
                    model.depthSceneVisible = true
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "cube")
                        .font(.system(size: 11, weight: .semibold))
                    Text(model.depthSceneVisible ? "Close 3D scene" : "Open 3D scene")
                        .font(Theme.ui(11, .medium))
                }
                .foregroundStyle(model.depthSceneVisible ? Theme.amber : Theme.ink2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(model.depthSceneVisible ? Theme.amber.opacity(0.12) : Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(model.depthSceneVisible ? Theme.amber.opacity(0.6) : Theme.hairline)
                )
            }
            .buttonStyle(.plain)
            .clickCursor()
            .help("See the scene in 3D — drag to orbit, grab a handle to move a focus plane")
            AdjustmentRow(parameter: .blurF, edit: $model.edit, armed: $model.armed, hovered: $model.hovered)
            AdjustmentRow(parameter: .focusDepth, edit: $model.edit, armed: $model.armed, hovered: $model.hovered)
            AdjustmentRow(parameter: .focusRange, edit: $model.edit, armed: $model.armed, hovered: $model.hovered)
            AdjustmentRow(parameter: .relight, edit: $model.edit, armed: $model.armed, hovered: $model.hovered)
        }
    }

    private func sectionLabel(_ title: String, help: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(Theme.ui(12, .medium))
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
            Text("Reset all").frame(maxWidth: .infinity)
        }
        .buttonStyle(OutlineButtonStyle())
        .clickCursor()
        .disabled(model.edit.isNeutral)
        .padding(.top, 14)
    }

    private var scrubHint: some View {
        Text("Click a control, then drag on the photo or the dial — hold \\ to compare with the original")
            .font(Theme.ui(10))
            .foregroundStyle(Theme.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
    }
}


