import SwiftUI
import TipKit

struct EditView: View {
    let library: Library
    let onExport: () -> Void
    @State private var model: EditViewModel
    @State private var scrollMonitor: Any?
    @State private var savingVersion = false
    @State private var versionName = ""
    @State private var versionsHovering = false
    @FocusState private var focused: Bool

    init(library: Library, photo: Photo, onExport: @escaping () -> Void) {
        self.library = library
        self.onExport = onExport
        _model = State(initialValue: EditViewModel(photo: photo))
    }

    /// True while any text field (type-to-set) owns the keyboard — global
    /// shortcuts must not eat its characters.
    private var textEditing: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            CanvasView(model: model)
            RailView(model: model, library: library)
                .ignoresSafeArea()
                .disabled(library.agentActive)
        }
        // Keyboard handling attaches HERE, before the button overlays — a
        // focusable ancestor swallows the first click on buttons inside it.
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.escape) {
            guard !textEditing else { return .ignored }
            if model.selectedLocalID != nil { model.selectedLocalID = nil }
            else if model.depthSceneVisible { model.depthSceneCommand = .exit }
            else if model.cropMode { model.cropMode = false }
            else if model.armed != nil || model.armedHSL != nil {
                model.armed = nil
                model.armedHSL = nil
            }
            else { close() }
            return .handled
        }
        .onKeyPress(.return) {
            guard !textEditing else { return .ignored }
            guard model.cropMode else { return .ignored }
            model.cropMode = false
            return .handled
        }
        .onKeyPress(keys: ["p"], phases: [.down]) { _ in
            guard !textEditing else { return .ignored }
            model.photo.starred.toggle()
            model.saveNow()
            return .handled
        }
        .onKeyPress(keys: ["j"], phases: [.down]) { _ in
            guard !textEditing else { return .ignored }
            model.showClipping.toggle()
            return .handled
        }
        .onKeyPress(keys: ["z"], phases: [.down]) { _ in
            guard !textEditing else { return .ignored }
            if model.canvasZoom > 1 {
                model.canvasZoom = 1
                model.canvasPan = .zero
            } else {
                model.pixelZoomRequested = true
            }
            return .handled
        }
        .onKeyPress(keys: ["c"], phases: [.down]) { _ in
            guard !textEditing else { return .ignored }
            model.cropMode.toggle()
            return .handled
        }
        .onKeyPress(keys: ["\\"], phases: [.down, .up]) { press in
            guard !textEditing else { return .ignored }
            model.showOriginal = press.phase == .down
            return .handled
        }
        .onKeyPress(keys: [" "], phases: [.down, .up, .repeat]) { press in
            guard !textEditing else { return .ignored }
            model.spacePan = press.phase != .up
            return .handled
        }
        // Arrows nudge the armed control; with nothing armed they step photos.
        .onKeyPress(.leftArrow) {
            guard !textEditing else { return .ignored }
            nudgeOrStep(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !textEditing else { return .ignored }
            nudgeOrStep(1)
            return .handled
        }
        .overlay(alignment: .bottom) {
            if !model.cropMode && !model.depthSceneVisible {
                navPill.padding(.bottom, 16).padding(.trailing, Theme.railWidth)
            }
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 8) {
                backButton
                zoomControls
            }
            .padding(.top, 10)
            .padding(.leading, 14) // just below the traffic lights
        }
        .overlay(alignment: .topTrailing) {
            toolbar
            .padding(14)
            .padding(.trailing, Theme.railWidth)
        }
        .onAppear {
            focused = true
            AgentTip.noteEditorOpened()
            library.activeEditor = model
            installScrollMonitor()
        }
        .onDisappear {
            model.saveNow()
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
            scrollMonitor = nil
        }
    }

    /// Horizontal trackpad scroll adjusts the ARMED parameter (the dial), with
    /// haptic detents. Vertical scroll always scrolls lists — rows never hijack it.
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard !library.agentActive, !model.depthSceneVisible else { return event }
            let dx = event.scrollingDeltaX
            guard abs(dx) > abs(event.scrollingDeltaY), dx != 0 else { return event }
            if model.cropMode {
                // The arc ruler follows the scroll.
                model.edit.straighten = (model.edit.straighten - Double(dx) / 8).clamped(to: -45...45)
                return nil
            }
            if model.armedHSL != nil {
                model.scrub(deltaX: dx)
                return nil
            }
            guard let parameter = model.armed else { return event }
            let span = parameter.range.upperBound - parameter.range.lowerBound
            let old = parameter.value(in: model.edit)
            parameter.set(old + dx / 500 * span, in: &model.edit)
            HapticDetents.tickIfCrossed(parameter: parameter, from: old, to: parameter.value(in: model.edit))
            return nil
        }
    }


    private var navPill: some View {
        HStack(spacing: 12) {
            Button { step(-1) } label: { chevron("chevron.left") }
                .buttonStyle(.plain).clickCursor()
            Text("\(photoIndex + 1) / \(library.photos.count)")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.ink2)
                .monospacedDigit()
            Button { step(1) } label: { chevron("chevron.right") }
                .buttonStyle(.plain).clickCursor()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .chiaroGlass(cornerRadius: 12)
    }

    private func chevron(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.ink2)
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
    }

    private var photoIndex: Int {
        library.photos.firstIndex(where: { $0.url == model.photo.url }) ?? 0
    }

    private var toolbar: some View {
        HStack(spacing: 7) {
            iconAction(model.autoApplied ? "Undo auto" : "Auto",
                       icon: "wand.and.stars", active: model.autoApplied) { model.autoEnhance() }
            iconAction(model.photo.starred ? "Starred" : "Star",
                       icon: model.photo.starred ? "star.fill" : "star",
                       active: model.photo.starred) {
                model.photo.starred.toggle()
                model.saveNow()
            }
            iconAction("Crop", icon: "crop", active: model.cropMode) { model.cropMode.toggle() }
            iconAction("Headshot", icon: "person.crop.square") { model.autoHeadshotCrop() }
            iconAction("Rotate", icon: "rotate.right") {
                model.edit.rotation = (model.edit.rotation + 90) % 360
            }
            iconAction("Flip H", icon: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                model.edit.flipH.toggle()
            }
            iconAction("Flip V", icon: "arrow.up.and.down.righttriangle.up.righttriangle.down") {
                model.edit.flipV.toggle()
            }
            iconAction("Undo", icon: "arrow.uturn.backward", disabled: !model.canUndo) { model.undo() }
            iconAction("Redo", icon: "arrow.uturn.forward", disabled: !model.canRedo) { model.redo() }
            iconAction("Original", icon: model.showOriginal ? "eye.fill" : "eye", active: model.showOriginal) {
                model.showOriginal.toggle()
            }
            iconAction("Copy edits", icon: "doc.on.doc", disabled: model.edit.isNeutral) {
                library.copiedEdit = model.edit
            }
            if library.copiedEdit != nil {
                iconAction("Paste edits", icon: "doc.on.clipboard") {
                    if let copied = library.copiedEdit { model.edit = copied }
                }
            }
            versionsMenu
            exportButton
        }
    }

    /// Named saved states of this photo's edit (sidecar-persisted).
    private var versionsMenu: some View {
        Menu {
            Button("Save version…") {
                versionName = Date().formatted(date: .abbreviated, time: .shortened)
                savingVersion = true
            }
            if !model.photo.snapshots.isEmpty {
                Divider()
                ForEach(model.photo.snapshots) { snapshot in
                    Menu(snapshot.name) {
                        Button("Apply") { model.applyVersion(snapshot) }
                        Button("Delete", role: .destructive) { model.deleteVersion(snapshot) }
                    }
                }
            }
        } label: {
            Image(systemName: "square.stack")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(model.photo.snapshots.isEmpty ? Theme.ink2 : Theme.amber)
                .frame(width: 16, height: 14)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .chiaroGlass(cornerRadius: 10)
        .overlay(alignment: .top) {
            if versionsHovering {
                Text("Versions")
                    .font(Theme.ui(10, .medium))
                    .foregroundStyle(Theme.ink)
                    .fixedSize()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .overlay(Capsule().stroke(Theme.hairline))
                    .offset(y: 32)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) { versionsHovering = inside }
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help("Versions — save and switch between edit states")
        .alert("Save version", isPresented: $savingVersion) {
            TextField("Name", text: $versionName)
            Button("Save") {
                let trimmed = versionName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                model.saveVersion(named: trimmed)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keeps the current edit as a named state you can return to")
        }
    }

    /// Icon-only glass button whose label slides in on hover.
    private func iconAction(
        _ title: String, icon: String, active: Bool = false, disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HoverLabelButton(title: title, icon: icon, active: active, disabled: disabled, action: action)
    }

    private func glassAction(_ title: String, icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(title)
            }
        }
        .buttonStyle(GlassButtonStyle())
        .clickCursor()
        .disabled(disabled)
    }

    private var exportButton: some View {
        Button(action: onExport) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 10, weight: .semibold))
                Text("Export")
            }
        }
        .buttonStyle(GlassButtonStyle(tint: Theme.amber))
        .clickCursor()
        .keyboardShortcut("e")
        .help("Full-resolution JPEG, HEIF, or 16-bit TIFF (⌘E)")
    }

    /// Fit / 1:1 / zoom multiplier — pixel-checking without the trackpad.
    private var zoomControls: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    model.canvasZoom = 1
                    model.canvasPan = .zero
                }
            } label: {
                Text("Fit").font(Theme.ui(10.5, .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.canvasZoom == 1 ? Theme.amber : Theme.ink2)
            .clickCursor()
            .help("Fit the photo in the window (Z toggles)")
            Button {
                model.pixelZoomRequested = true
            } label: {
                Text("1:1").font(Theme.ui(10.5, .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.canvasZoom > 1 ? Theme.amber : Theme.ink2)
            .clickCursor()
            .help("Actual pixels — check sharpness (Z toggles)")
            Slider(value: Binding(
                get: { Double(model.canvasZoom) },
                set: { model.canvasZoom = CGFloat($0) }
            ), in: 1...8)
                .tint(Theme.amber)
                .controlSize(.mini)
                .frame(width: 76)
            Text(String(format: "×%.1f", model.canvasZoom))
                .font(Theme.mono(9))
                .foregroundStyle(Theme.ink3)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .chiaroGlass(cornerRadius: 10)
    }

    private var backButton: some View {
        Button(action: close) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                Text("Library")
            }
        }
        .buttonStyle(GlassButtonStyle())
        .clickCursor()
    }

    private func nudgeOrStep(_ direction: Int) {
        if let armed = model.armed {
            let span = armed.range.upperBound - armed.range.lowerBound
            armed.set(armed.value(in: model.edit) + Double(direction) * span / 200, in: &model.edit)
        } else if model.armedHSL != nil {
            model.scrub(deltaX: CGFloat(direction) * 2.1)
        } else {
            step(direction)
        }
    }

    private func close() {
        model.saveNow()
        library.activeEditor = nil
        library.editing = nil
    }

    private func step(_ delta: Int) {
        guard let index = library.photos.firstIndex(where: { $0.url == model.photo.url }) else { return }
        let next = (index + delta + library.photos.count) % library.photos.count
        library.edit(library.photos[next])
    }
}
