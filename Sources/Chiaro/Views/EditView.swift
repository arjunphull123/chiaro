import SwiftUI

struct EditView: View {
    let library: Library
    let onExport: () -> Void
    @State private var model: EditViewModel
    @State private var scrollMonitor: Any?
    @FocusState private var focused: Bool

    init(library: Library, photo: Photo, onExport: @escaping () -> Void) {
        self.library = library
        self.onExport = onExport
        _model = State(initialValue: EditViewModel(photo: photo))
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
            if model.cropMode { model.cropMode = false }
            else if model.armed != nil { model.armed = nil }
            else { close() }
            return .handled
        }
        .onKeyPress(.return) {
            guard model.cropMode else { return .ignored }
            model.cropMode = false
            return .handled
        }
        .onKeyPress(keys: ["c"], phases: [.down]) { _ in
            model.cropMode.toggle()
            return .handled
        }
        .onKeyPress(keys: ["\\"], phases: [.down, .up]) { press in
            model.showOriginal = press.phase == .down
            return .handled
        }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onKeyPress(characters: .init(charactersIn: "012345")) { press in
            model.photo.rating = Int(press.characters) ?? 0
            model.saveNow()
            return .handled
        }
        .overlay(alignment: .bottom) {
            if !model.cropMode {
                navPill.padding(.bottom, 16).padding(.trailing, Theme.railWidth)
            }
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    AppMark(size: 16)
                    Text("Chiaro")
                        .font(Theme.serif(16, .semibold))
                        .kerning(-0.4)
                        .foregroundStyle(Theme.ink)
                }
                backButton
            }
            .padding(.top, 10)
            .padding(.leading, 14) // just below the traffic lights
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                Button { model.cropMode.toggle() } label: { Image(systemName: "crop") }
                    .buttonStyle(GlassIconButtonStyle(tint: model.cropMode ? Theme.amber : Theme.ink2))
                    .clickCursor()
                    .help("Crop & straighten (C)")
                glassIcon("arrow.uturn.backward", disabled: !model.canUndo, help: "Undo (⌘Z)") { model.undo() }
                glassIcon("arrow.uturn.forward", disabled: !model.canRedo, help: "Redo (⇧⌘Z)") { model.redo() }
                glassAction("Copy edits", icon: "doc.on.doc", disabled: model.edit.isNeutral) {
                    library.copiedEdit = model.edit
                }
                if library.copiedEdit != nil {
                    glassAction("Paste edits", icon: "doc.on.clipboard") {
                        if let copied = library.copiedEdit { model.edit = copied }
                    }
                }
                exportButton
            }
            .padding(14)
            .padding(.trailing, Theme.railWidth)
        }
        .onAppear {
            focused = true
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
            guard !library.agentActive, let parameter = model.armed else { return event }
            let dx = event.scrollingDeltaX
            guard abs(dx) > abs(event.scrollingDeltaY), dx != 0 else { return event }
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

    private func glassIcon(_ icon: String, disabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon) }
            .buttonStyle(GlassIconButtonStyle())
            .clickCursor()
            .disabled(disabled)
            .help(help)
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
