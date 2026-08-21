import SwiftUI

/// The frosted adjustments rail (ADR 0006): photo header, histogram on a solid
/// plate, grouped adjustments, built-in Looks.
struct RailView: View {
    @Bindable var model: EditViewModel
    let library: Library

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pinned above the fold: the app mark and the photo's identity.
            // Agent presence lives in the window's title strip now (RootView),
            // not here — this dims along with the rest while an agent edits.
            VStack(alignment: .leading, spacing: 12) {
                AppMark(size: 30)
                photoHeader
            }
            // The mark dims with the header, not just the header: while an agent
            // drives, its status card expands down over this block, and a mark
            // at full strength under a glass card reads as two things fighting
            // for the same corner rather than one layer over another.
            .opacity(library.agentActive ? 0.4 : 1)
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
                        .overlay(alignment: .topLeading) { clippingTriangle }
                        .overlay(alignment: .topTrailing) { clippingTriangle }
                    HStack {
                        Spacer()
                        Button(collapsedRaw.isEmpty ? "Collapse all" : "Expand all") {
                            collapsedRaw = collapsedRaw.isEmpty
                                ? RailView.allSections.joined(separator: ",") : ""
                        }
                        .buttonStyle(.plain)
                        .font(Theme.ui(9.5))
                        .foregroundStyle(Theme.ink3)
                        .clickCursor()
                    }
                    .padding(.top, 2)
                    .padding(.bottom, -6)
                    presetsSection
                    colorMixSection
                    section(
                        "Grading",
                        [.shadowStrength, .shadowHue, .midStrength, .midHue,
                         .highlightStrength, .highlightHue, .gradeBalance],
                        help: "Colour by tonal zone — a hue for shadows, midtones, and highlights"
                    )
                    section(
                        "Light", [.exposure, .contrast, .highlights, .shadows, .whites, .blacks],
                        help: "Brightness and tonal balance"
                    )
                    portraitSection
                    curveSection
                    section(
                        "Color", [.temp, .tint, .vibrance, .saturation],
                        help: "White balance and color strength"
                    )
                    localSection
                    section("Effects", [.clarity, .vignette, .grain, .grainSize], help: "Punch and framing")
                    section(
                        "Detail",
                        model.photo.isRAW ? rawDetailRows : [.sharpness, .noiseReduction],
                        help: "Fine texture and noise cleanup"
                    )
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
                Button {
                    model.photo.starred.toggle()
                    model.saveNow()
                } label: {
                    Image(systemName: model.photo.starred ? "star.fill" : "star")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(model.photo.starred ? Theme.amber : Theme.ink3)
                }
                .buttonStyle(.plain)
                .clickCursor()
                .help("Star this photo (P)")
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

    /// RAW-only Detail rows, filtered to the ones this photo's decoder still
    /// acts on — RAW 9 (once selected for a given camera) folds detail and
    /// moiré reduction into the decode model and reduces color noise
    /// automatically, so a slider for either would sit in the rail doing
    /// nothing. `EditViewModel.decodeCapabilities` is queried per photo via
    /// CIRAWFilter's own `isXSupported` flags rather than assumed from OS version.
    private var rawDetailRows: [EditParameter] {
        let c = model.decodeCapabilities
        var rows: [EditParameter] = []
        if c.sharpness { rows.append(.sharpness) }
        if c.luminanceNoise { rows.append(.noiseReduction) }
        if c.colorNoise { rows.append(.colorNoiseReduction) }
        if c.moire { rows.append(.moireReduction) }
        return rows
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
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
                    .rotationEffect(.degrees(isCollapsed("Curve") ? -90 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleCollapsed("Curve") }
            .clickCursor()
            .padding(.top, 10)
            if !isCollapsed("Curve") {
                CurveEditorView(edit: $model.edit, histogram: model.histogram)
            }
        }
        .help("Tone curve — click adds a point, drag shapes it, double-click removes")
    }

    private func section(_ title: String, _ params: [EditParameter], help: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionLabel(title, help: help)
            if !isCollapsed(title) {
                ForEach(params) { p in
                    AdjustmentRow(parameter: p, edit: $model.edit, armed: $model.armed, hovered: $model.hovered)
                }
            }
        }
    }

    private var portraitSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionLabel("Background blur", help: "What stays sharp: the lifted subject, detected people, or everything nearer than the focus plane")
            if !isCollapsed("Background blur") {
            HStack(spacing: 5) {
                modePill("Subject", .subject)
                modePill("Person", .person)
                modePill("Depth", .depth)
            }
            .padding(.bottom, 4)
            depthSceneAccess
                .padding(.bottom, 6)
            if model.edit.blurMode == .depth {
                depthContent
            } else {
                subjectContent
            }
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

    /// Viewing the depth composition is inspection, available in any blur
    /// mode — it never touches the edit on its own (only grabbing the focus
    /// plane inside it, or picking Depth above, commits to depth-mode blur).
    /// The model itself is an opt-in 50 MB download on first use.
    @ViewBuilder private var depthSceneAccess: some View {
        switch DepthModelStore.shared.availability {
        case .missing:
            Button("Download depth model (50 MB)") {
                DepthModelStore.shared.downloadIfNeeded()
            }
            .buttonStyle(OutlineButtonStyle())
            .clickCursor()
            .help("Apple's Depth Anything V2, run on-device — enables focus-plane blur and the 3D scene")
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
            HStack(spacing: 7) {
                ProgressView().controlSize(.mini)
                Text("Preparing…")
                    .font(Theme.ui(10.5)).foregroundStyle(Theme.ink3)
            }
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
                    Capsule().fill(model.depthSceneVisible ? Theme.amber.opacity(0.12) : Color.white.opacity(0.04))
                )
                .overlay(
                    Capsule().stroke(model.depthSceneVisible ? Theme.amber.opacity(0.6) : Theme.hairline)
                )
            }
            .buttonStyle(.plain)
            .clickCursor()
            .help("See the scene in 3D — drag to orbit, grab a handle to move a focus plane")
        }
    }

    /// Depth-map blur controls, once the model is ready and Depth is selected.
    @ViewBuilder private var depthContent: some View {
        if case .ready = DepthModelStore.shared.availability {
            AdjustmentRow(parameter: .blurF, edit: $model.edit, armed: $model.armed, hovered: $model.hovered)
            AdjustmentRow(parameter: .focusDepth, edit: $model.edit, armed: $model.armed, hovered: $model.hovered)
            AdjustmentRow(parameter: .relight, edit: $model.edit, armed: $model.armed, hovered: $model.hovered)
        }
    }

    @State private var selectedBand = 0
    @State private var bandScrubStart: (x: CGFloat, value: Double)?

    private var colorMixSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Color mix", help: "Per-hue adjustments — pick a band, then shift its hue, saturation, and luminance")
            if !isCollapsed("Color mix") {
            // Spacing is 6, not 8, and there is no divider: the chip plus eight
            // swatches has to fit the rail's 236pt of inner width, and at 8 it
            // overflowed and ate the rail's right padding.
            HStack(spacing: 6) {
                // In the band row, because it changes what the bands mean: in
                // black and white the luminance row becomes each hue's grey.
                Chip(title: "B&W", selected: model.edit.monochrome) {
                    model.edit.monochrome.toggle()
                }
                .fixedSize() // Chip fills its container by default; the row's spacers would crush the label
                .help("Black and white. The luminance row sets each colour's grey value")
                Spacer(minLength: 0)
                ForEach(0..<8, id: \.self) { i in
                    let active = !model.edit.hsl[i].isNeutral
                    Button {
                        selectedBand = i
                        if let armed = model.armedHSL { model.armedHSL = (i, armed.component) }
                    } label: {
                        Circle()
                            .fill(Color(hue: HSLBand.centers[i] / 360, saturation: 0.75, brightness: 0.85))
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle().stroke(
                                    selectedBand == i ? Theme.amber : (active ? Theme.ink2 : .clear),
                                    lineWidth: selectedBand == i ? 2 : 1.5
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .clickCursor()
                    .help(HSLBand.names[i].prefix(1).uppercased() + HSLBand.names[i].dropFirst())
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 2)
            if !model.edit.monochrome {
                bandRow(.h)
                bandRow(.s)
            }
            bandRow(.l)
            }
        }
    }

    @State private var typingValue = ""
    @FocusState private var typingField: String?

    /// Scrub row for one component of the selected band — same feel as
    /// AdjustmentRow: click arms the glass dial, drag scrubs, click the
    /// value to type it.
    private func bandRow(_ component: EditViewModel.HSLComponent) -> some View {
        let label = component.rawValue
        let keyPath = component.keyPath
        let isArmed = model.armedHSL?.band == selectedBand && model.armedHSL?.component == component
        let value = model.edit.hsl[selectedBand][keyPath: keyPath]
        let fieldID = "hsl-\(selectedBand)-\(label)"
        return HStack {
            Text(label)
                .font(Theme.ui(11.5))
                .foregroundStyle(Theme.ink2)
            Spacer()
            if typingField == fieldID {
                TextField("", text: $typingValue)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(10, .medium))
                    .foregroundStyle(Theme.amber)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                    .focused($typingField, equals: fieldID)
                    .onAppear {
                        DispatchQueue.main.async { typingField = fieldID }
                    }
                    .onSubmit {
                        if let typed = Double(typingValue) {
                            model.edit.hsl[selectedBand][keyPath: keyPath] = typed.clamped(to: -100...100)
                        }
                        typingField = nil
                    }
                    .onExitCommand { typingField = nil }
            } else {
                Text(value == 0 ? "0" : String(format: "%+.0f", value))
                    .font(Theme.mono(10, .medium))
                    .foregroundStyle(value == 0 ? Theme.ink3 : Theme.amber)
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.05)))
                    .onTapGesture {
                        typingValue = value == 0 ? "" : String(format: "%.0f", value)
                        typingField = fieldID
                    }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isArmed ? Theme.amber.opacity(0.1) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isArmed ? Theme.amber.opacity(0.6) : .clear)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { g in
                    if bandScrubStart == nil {
                        bandScrubStart = (g.startLocation.x, model.edit.hsl[selectedBand][keyPath: keyPath])
                    }
                    guard let start = bandScrubStart else { return }
                    let delta = Double(g.location.x - start.x) / 1.6
                    var new = (start.value + delta).clamped(to: -100...100)
                    if abs(new) < 2 { new = 0 }
                    model.edit.hsl[selectedBand][keyPath: keyPath] = new
                }
                .onEnded { _ in bandScrubStart = nil }
        )
        .onTapGesture(count: 2) { model.edit.hsl[selectedBand][keyPath: keyPath] = 0 }
        .onTapGesture {
            model.armedHSL = isArmed ? nil : (selectedBand, component)
        }
        .clickCursor()
    }

    private var localSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text("Masking")
                    .font(Theme.ui(12, .medium))
                    .foregroundStyle(Theme.ink2)
                Rectangle().fill(Theme.hairline).frame(height: 1)
                Menu {
                    Button("Radial") { addLocal(.radial) }
                    Button("Linear") { addLocal(.linear) }
                    Button("Subject") { addLocal(.subject) }
                } label: {
                    Text("Add")
                        .font(Theme.ui(9.5))
                        .foregroundStyle(Theme.ink3)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .clickCursor()
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
                    .rotationEffect(.degrees(isCollapsed("Masking") ? -90 : 0))
                    .contentShape(Rectangle())
                    .onTapGesture { toggleCollapsed("Masking") }
                    .clickCursor()
            }
            .padding(.top, 10)
            if !isCollapsed("Masking") {
            ForEach(Array(model.edit.locals.enumerated()), id: \.element.id) { index, local in
                let selected = model.selectedLocalID == local.id
                HStack(spacing: 6) {
                    Image(systemName: local.kind == .radial ? "circle.dashed"
                        : local.kind == .linear ? "line.diagonal" : "person.crop.square.badge.camera")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(selected ? Theme.amber : Theme.ink3)
                    Text("\(local.kind.rawValue.prefix(1).uppercased() + local.kind.rawValue.dropFirst()) \(index + 1)")
                        .font(Theme.ui(11.5, selected ? .medium : .regular))
                        .foregroundStyle(selected ? Theme.amber : Theme.ink2)
                    Spacer()
                    Button {
                        model.edit.locals.removeAll { $0.id == local.id }
                        if selected { model.selectedLocalID = nil }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.ink3)
                    }
                    .buttonStyle(.plain)
                    .clickCursor()
                    .help("Delete this mask")
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(selected ? Theme.amber.opacity(0.1) : Color.white.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(selected ? Theme.amber.opacity(0.5) : .clear)
                )
                .contentShape(Rectangle())
                .onTapGesture { model.selectedLocalID = selected ? nil : local.id }
                .clickCursor()
            }
            if let index = model.edit.locals.firstIndex(where: { $0.id == model.selectedLocalID }) {
                localRow("Exposure", index: index, keyPath: \.exposure, range: -3...3)
                localRow("Contrast", index: index, keyPath: \.contrast, range: -100...100)
                localRow("Highlights", index: index, keyPath: \.highlights, range: -100...100)
                localRow("Shadows", index: index, keyPath: \.shadows, range: -100...100)
                localRow("Temp", index: index, keyPath: \.temp, range: -100...100)
                localRow("Tint", index: index, keyPath: \.tint, range: -100...100)
                localRow("Saturation", index: index, keyPath: \.saturation, range: -100...100)
                localRow("Clarity", index: index, keyPath: \.clarity, range: -100...100)
                localRow("Luma low", index: index, keyPath: \.lumaLow, range: 0...100)
                localRow("Luma high", index: index, keyPath: \.lumaHigh, range: 0...100)
                if model.edit.locals[index].kind != .linear {
                    localRow("Feather", index: index, keyPath: \.feather, range: 0...100)
                }
                Toggle(isOn: Binding(
                    get: { model.edit.locals[index].invert },
                    set: { model.edit.locals[index].invert = $0 }
                )) {
                    Text("Invert")
                        .font(Theme.ui(11.5))
                        .foregroundStyle(Theme.ink2)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Theme.amber)
                .padding(.horizontal, 9)
                .padding(.top, 2)
            }
            }
        }
        .help("Masked corrections — a radial or linear region, or the detected subject")
    }

    private func modePill(_ title: String, _ mode: BlurMode) -> some View {
        let selected = model.edit.blurMode == mode
        return Button { model.setBlurMode(mode) } label: {
            Text(title)
                .font(Theme.ui(10.5, selected ? .medium : .regular))
                .foregroundStyle(selected ? Theme.amber : Theme.ink2)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(selected ? 0.08 : 0.03)))
                .overlay(Capsule().stroke(selected ? Theme.amber.opacity(0.5) : Theme.hairline))
        }
        .buttonStyle(.plain)
        .clickCursor()
    }

    private func addLocal(_ kind: LocalAdjustment.Kind) {
        var local = LocalAdjustment(kind: kind)
        if kind == .linear {
            local.ax = 0.5; local.ay = 0.15; local.bx = 0.5; local.by = 0.55
        }
        model.edit.locals.append(local)
        model.selectedLocalID = local.id
    }

    @State private var localScrubStart: (x: CGFloat, value: Double)?

    private func localRow(_ label: String, index: Int, keyPath: WritableKeyPath<LocalAdjustment, Double>, range: ClosedRange<Double>) -> some View {
        let value = model.edit.locals[index][keyPath: keyPath]
        let isEV = range.upperBound <= 3
        let fieldID = "local-\(index)-\(label)"
        // The gestures below escape past this render pass — resolve the index
        // fresh by id when they fire, since `locals` can shrink meanwhile
        // (an agent's set_edit clearing them mid-drag).
        let id = model.edit.locals[index].id
        func resolve() -> Int? { model.edit.locals.firstIndex(where: { $0.id == id }) }
        let isArmed = model.armedLocal?.id == id && model.armedLocal?.keyPath == keyPath
        return HStack {
            Text(label)
                .font(Theme.ui(11.5, isArmed ? .medium : .regular))
                .foregroundStyle(isArmed ? Theme.ink : Theme.ink2)
            Spacer()
            if typingField == fieldID {
                TextField("", text: $typingValue)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(10, .medium))
                    .foregroundStyle(Theme.amber)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                    .focused($typingField, equals: fieldID)
                    .onAppear {
                        DispatchQueue.main.async { typingField = fieldID }
                    }
                    .onSubmit {
                        if let typed = Double(typingValue), let i = resolve() {
                            model.edit.locals[i][keyPath: keyPath] = typed.clamped(to: range)
                        }
                        typingField = nil
                    }
                    .onExitCommand { typingField = nil }
            } else {
                Text(isEV ? String(format: "%+.2f", value) : (value == 0 ? "0" : String(format: "%+.0f", value)))
                    .font(Theme.mono(10, .medium))
                    .foregroundStyle(value == 0 ? Theme.ink3 : Theme.amber)
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.05)))
                    .onTapGesture {
                        typingValue = value == 0 ? "" : String(format: isEV ? "%.2f" : "%.0f", value)
                        typingField = fieldID
                    }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isArmed ? Theme.amber.opacity(0.1) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isArmed ? Theme.amber.opacity(0.6) : .clear)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { g in
                    guard let i = resolve() else { return }
                    if localScrubStart == nil {
                        localScrubStart = (g.startLocation.x, model.edit.locals[i][keyPath: keyPath])
                    }
                    guard let start = localScrubStart else { return }
                    let span = range.upperBound - range.lowerBound
                    let delta = Double(g.location.x - start.x) / 260 * span
                    var new = (start.value + delta).clamped(to: range)
                    if abs(new) < 2 { new = 0 }
                    model.edit.locals[i][keyPath: keyPath] = new
                }
                .onEnded { _ in localScrubStart = nil }
        )
        .onTapGesture(count: 2) {
            guard let i = resolve() else { return }
            model.edit.locals[i][keyPath: keyPath] = LocalAdjustment.defaults[keyPath: keyPath]
        }
        .onTapGesture {
            model.armedLocal = isArmed ? nil : (id, keyPath, label, range)
        }
        .clickCursor()
    }

    @State private var savingPreset = false
    @State private var presetName = ""

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text("Presets")
                    .font(Theme.ui(12, .medium))
                    .foregroundStyle(Theme.ink2)
                Rectangle().fill(Theme.hairline).frame(height: 1)
                Button("Save current") { presetName = ""; savingPreset = true }
                    .buttonStyle(.plain)
                    .clickCursor()
                    .font(Theme.ui(9.5))
                    .foregroundStyle(Theme.ink3)
                    .disabled(model.edit.isNeutral)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
                    .rotationEffect(.degrees(isCollapsed("Presets") ? -90 : 0))
                    .contentShape(Rectangle())
                    .onTapGesture { toggleCollapsed("Presets") }
                    .clickCursor()
            }
            .padding(.top, 10)
            if !isCollapsed("Presets") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], spacing: 5) {
                ForEach(PresetStore.shared.all) { preset in
                    let selected = preset.matches(model.edit)
                    Button {
                        // Clicking the active preset clears it back to neutral.
                        model.commitDiscrete(
                            (selected ? Preset(name: "", edit: EditState()) : preset).applied(to: model.edit)
                        )
                    } label: {
                        Text(preset.name)
                            .font(Theme.ui(10.5, selected ? .medium : .regular))
                            .foregroundStyle(selected ? Theme.amber : Theme.ink2)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(selected ? 0.08 : 0.03)))
                            .overlay(Capsule().stroke(selected ? Theme.amber.opacity(0.5) : Theme.hairline))
                    }
                    .buttonStyle(.plain)
                    .clickCursor()
                    .contextMenu {
                        if PresetStore.shared.user.contains(preset) {
                            Button("Delete preset") { PresetStore.shared.delete(preset) }
                        }
                    }
                }
            }
            }
        }
        .help("Starting points — tone and color only; crop and portrait stay put")
        .alert("Save preset", isPresented: $savingPreset) {
            TextField("Name", text: $presetName)
            Button("Save") {
                let trimmed = presetName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                PresetStore.shared.save(Preset.capture(name: trimmed, from: model.edit))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keeps the current tone and color as a reusable starting point")
        }
    }

    static let allSections = ["Presets", "Color mix", "Grading", "Light", "Background blur", "Curve", "Color", "Masking", "Effects", "Detail"]
    @AppStorage("collapsedSections") private var collapsedRaw = RailView.allSections.joined(separator: ",")

    private func isCollapsed(_ title: String) -> Bool {
        collapsedRaw.split(separator: ",").map(String.init).contains(title)
    }

    private func toggleCollapsed(_ title: String) {
        var set = Set(collapsedRaw.split(separator: ",").map(String.init))
        if !set.insert(title).inserted { set.remove(title) }
        collapsedRaw = set.sorted().joined(separator: ",")
    }

    /// Lightroom-style histogram corner toggles for the clipping overlay.
    private var clippingTriangle: some View {
        Button { model.showClipping.toggle() } label: {
            Image(systemName: "triangle.fill")
                .font(.system(size: 6))
                .foregroundStyle(model.showClipping ? Theme.amber : Theme.ink3)
                .padding(5)
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help("Clipping warnings — red blown highlights, blue crushed blacks (J)")
    }

    @State private var hoveredSection: String?

    private func sectionLabel(_ title: String, help: String) -> some View {
        let hovered = hoveredSection == title
        return HStack(spacing: 5) {
            Text(title)
                .font(Theme.ui(12, .medium))
                .foregroundStyle(hovered ? Theme.ink : Theme.ink2)
            Rectangle().fill(hovered ? Color.white.opacity(0.16) : Theme.hairline).frame(height: 1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(hovered ? Theme.ink2 : Theme.ink3)
                .rotationEffect(.degrees(isCollapsed(title) ? -90 : 0))
        }
        .contentShape(Rectangle())
        .onTapGesture { toggleCollapsed(title) }
        .onHover { hoveredSection = $0 ? title : (hoveredSection == title ? nil : hoveredSection) }
        .clickCursor()
        .padding(.top, 10)
        .padding(.bottom, 6)
        .help(help)
    }

    private var actions: some View {
        Button {
            model.commitDiscrete(.neutral)
        } label: {
            Text("Reset all").frame(maxWidth: .infinity)
        }
        .buttonStyle(OutlineButtonStyle())
        .clickCursor()
        .disabled(model.edit.isNeutral)
        .padding(.top, 14)
    }

    private var scrubHint: some View {
        Text("Click a control, then drag on the photo or the dial. Hold \\ to compare with the original")
            .font(Theme.ui(10))
            .foregroundStyle(Theme.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
    }
}


