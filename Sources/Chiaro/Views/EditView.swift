import SwiftUI

struct EditView: View {
    let library: Library
    let onExport: () -> Void
    @State private var model: EditViewModel
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
                .overlay(alignment: .trailing) { agentOverlay }
        }
        .overlay(alignment: .bottom) { navPill.padding(.bottom, 16).padding(.trailing, Theme.railWidth) }
        .overlay(alignment: .topLeading) { backButton.padding(14) }
        .overlay(alignment: .topTrailing) {
            exportButton.padding(14).padding(.trailing, Theme.railWidth)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear {
            focused = true
            library.activeEditor = model
        }
        .onKeyPress(.escape) {
            if model.armed != nil { model.armed = nil } else { close() }
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
        .onDisappear { model.saveNow() }
    }

    /// Frosts the entire rail while an agent drives, with the agent's stated intent.
    @ViewBuilder private var agentOverlay: some View {
        if library.agentActive {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                VStack(spacing: 10) {
                    AgentPill()
                    if let intent = library.agentIntent {
                        Text(intent)
                            .font(Theme.ui(11))
                            .foregroundStyle(Theme.ink2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                }
            }
            .frame(width: Theme.railWidth)
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }

    private var navPill: some View {
        HStack(spacing: 12) {
            Button { step(-1) } label: { chevron("chevron.left") }.buttonStyle(.plain)
            Text("\(photoIndex + 1) / \(library.photos.count)")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.ink2)
                .monospacedDigit()
            Button { step(1) } label: { chevron("chevron.right") }.buttonStyle(.plain)
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

    private var exportButton: some View {
        Button(action: onExport) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 10, weight: .semibold))
                Text("Export").font(Theme.ui(11, .medium))
            }
            .foregroundStyle(Theme.amber)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .chiaroGlass(cornerRadius: 10)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("e")
        .help("Full-resolution JPEG, HEIF, or 16-bit TIFF (⌘E)")
    }

    private var backButton: some View {
        Button(action: close) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                Text("Library").font(Theme.ui(11, .medium))
            }
            .foregroundStyle(Theme.ink2)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .chiaroGlass(cornerRadius: 10)
        }
        .buttonStyle(.plain)
    }

    private struct AgentPill: View {
        @State private var pulsing = false

        var body: some View {
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.amber)
                    .frame(width: 7, height: 7)
                    .opacity(pulsing ? 0.35 : 1)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulsing)
                Text("AGENT EDITING")
                    .font(Theme.mono(9, .medium))
                    .kerning(1.6)
                    .foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .chiaroGlass(cornerRadius: 12)
            .onAppear { pulsing = true }
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
