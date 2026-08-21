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
    @State private var versionsCursorPushed = false
    @State private var reverting = false
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
        .onKeyPress(keys: ["p"], phases: [.down]) { press in
            guard !textEditing, press.modifiers.isEmpty else { return .ignored }
            model.photo.starred.toggle()
            model.saveNow()
            return .handled
        }
        .onKeyPress(keys: ["j"], phases: [.down]) { press in
            guard !textEditing, press.modifiers.isEmpty else { return .ignored }
            model.showClipping.toggle()
            return .handled
        }
        .onKeyPress(keys: ["z"], phases: [.down]) { press in
            guard !textEditing, press.modifiers.isEmpty else { return .ignored }
            if model.canvasZoom > 1 {
                model.canvasZoom = 1
                model.canvasPan = .zero
            } else {
                model.pixelZoomRequested = true
            }
            return .handled
        }
        .onKeyPress(keys: ["c"], phases: [.down]) { press in
            guard !textEditing, press.modifiers.isEmpty else { return .ignored }
            model.cropMode.toggle()
            return .handled
        }
        .onKeyPress(keys: ["\\"], phases: [.down, .up]) { press in
            guard !textEditing else { return .ignored }
            // Modifiers only gate the down-stroke — the release must always go
            // through, or a modifier held mid-press would leave this stuck on.
            if press.phase == .down, !press.modifiers.isEmpty { return .ignored }
            model.showOriginal = press.phase == .down
            return .handled
        }
        .onKeyPress(keys: [" "], phases: [.down, .up, .repeat]) { press in
            guard !textEditing else { return .ignored }
            if press.phase == .down, !press.modifiers.isEmpty { return .ignored }
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
        // One row, not two overlays: at narrow widths independent leading and
        // trailing overlays overlapped each other.
        .overlay(alignment: .top) {
            HStack(spacing: 8) {
                backButton
                zoomControls
                Spacer(minLength: 12)
                toolbar.layoutPriority(1) // actions keep their labels; the zoom slider yields first
            }
            .padding(.top, 12)
            .padding(.leading, 14) // just below the traffic lights
            .padding(.trailing, 14 + Theme.railWidth)
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
                model.scrubStraighten(deltaX: -dx)
                return nil
            }
            guard model.armed != nil || model.armedHSL != nil else { return event }
            // Negated so the ruler's ticks travel with the fingers.
            model.scrub(deltaX: -dx)
            return nil
        }
    }


    private var navPill: some View {
        HStack(spacing: 12) {
            Button { step(-1) } label: { chevron("chevron.left") }
                .buttonStyle(.plain).clickCursor()
            Text("\(photoIndex + 1) / \(navPhotos.count)")
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

    /// Arrow-key/nav-pill stepping walks the gallery's filtered set, falling
    /// back to every photo if the open one has been filtered out from under it.
    private var navPhotos: [Photo] {
        library.visiblePhotos.contains(where: { $0.url == model.photo.url })
            ? library.visiblePhotos : library.photos
    }

    private var photoIndex: Int {
        navPhotos.firstIndex(where: { $0.url == model.photo.url }) ?? 0
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
            // A before/after split rather than an eye: this shows the RAW
            // against the edit, not a show/hide toggle, so the eye glyph read
            // wrong. Press-and-hold mirrors the \ key exactly — a tap alone
            // does nothing, since HoverLabelButton still wants an action.
            iconAction("Original", icon: "square.righthalf.filled", active: model.showOriginal) {}
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in model.showOriginal = true }
                        .onEnded { _ in model.showOriginal = false }
                )
                .help("Hold to see the original (\\)")
            iconAction("Copy edits", icon: "doc.on.doc", disabled: model.edit.isNeutral) {
                library.copiedEdit = model.edit
            }
            if library.copiedEdit != nil {
                iconAction("Paste edits", icon: "doc.on.clipboard") {
                    if let copied = library.copiedEdit { model.commitDiscrete(copied) }
                }
            }
            versionsMenu
            iconAction("Revert", icon: "arrow.counterclockwise", disabled: model.edit.isNeutral,
                       tint: Theme.danger) { reverting = true }
            exportButton
        }
        .alert("Revert to original", isPresented: $reverting) {
            Button("Revert", role: .destructive) { model.commitDiscrete(EditState()) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes every edit on this photo — the original file is never touched")
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
            if inside {
                NSCursor.pointingHand.push()
                versionsCursorPushed = true
            } else if versionsCursorPushed {
                NSCursor.pop()
                versionsCursorPushed = false
            }
        }
        .onDisappear {
            if versionsCursorPushed {
                NSCursor.pop()
                versionsCursorPushed = false
            }
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
        tint: Color? = nil, action: @escaping () -> Void
    ) -> some View {
        HoverLabelButton(title: title, icon: icon, active: active, disabled: disabled, tint: tint, action: action)
    }

    /// Drops its label rather than compressing when the toolbar runs out of room.
    private var exportButton: some View {
        ViewThatFits(in: .horizontal) {
            exportButtonBody(labeled: true)
            exportButtonBody(labeled: false)
        }
    }

    private func exportButtonBody(labeled: Bool) -> some View {
        Button(action: onExport) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 10, weight: .semibold))
                if labeled { Text("Export") }
            }
        }
        .buttonStyle(GlassButtonStyle(tint: Theme.amber))
        .clickCursor()
        .keyboardShortcut("e")
        .help("Full-resolution JPEG, HEIF, or 16-bit TIFF (⌘E)")
        .fixedSize()
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
            // The slider is the first thing to go when the window is too narrow
            // for the toolbar; Fit / 1:1 / readout still fit.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    zoomSlider
                    zoomReadout
                }
                zoomReadout
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .chiaroGlass(cornerRadius: 10)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var zoomSlider: some View {
        Slider(value: Binding(
            get: { Double(model.canvasZoom) },
            set: { model.canvasZoom = CGFloat($0) }
        ), in: 1...8)
            .tint(Theme.amber)
            .controlSize(.mini)
            .frame(width: 76)
    }

    private var zoomReadout: some View {
        Text(String(format: "×%.1f", model.canvasZoom))
            .font(Theme.mono(9))
            .foregroundStyle(Theme.ink3)
            .monospacedDigit()
            .fixedSize()
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
        if model.armed != nil || model.armedHSL != nil || model.cropMode {
            model.nudge(direction)
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
        let list = navPhotos
        guard let index = list.firstIndex(where: { $0.url == model.photo.url }) else { return }
        let next = (index + delta + list.count) % list.count
        library.edit(list[next])
    }
}
