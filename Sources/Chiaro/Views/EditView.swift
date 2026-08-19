import SwiftUI

struct EditView: View {
    let library: Library
    @State private var model: EditViewModel
    @FocusState private var focused: Bool

    init(library: Library, photo: Photo) {
        self.library = library
        _model = State(initialValue: EditViewModel(photo: photo))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            CanvasView(model: model)
            RailView(model: model)
                .ignoresSafeArea()
                .disabled(library.agentActive)
        }
        .overlay(alignment: .top) {
            if library.agentActive {
                AgentPill().padding(.top, 14).padding(.trailing, Theme.railWidth)
            }
        }
        .overlay(alignment: .bottom) {
            FilmstripView(photos: library.photos, current: model.photo) { photo in
                model.switchTo(photo)
                library.selection = [photo.url]
            }
            .padding(.bottom, 14)
            .padding(.trailing, Theme.railWidth)
        }
        .overlay(alignment: .topLeading) { backButton.padding(14) }
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

    private func close() {
        model.saveNow()
        library.activeEditor = nil
        library.editing = nil
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
            .transition(.opacity)
        }
    }

    private func step(_ delta: Int) {
        guard let index = library.photos.firstIndex(where: { $0.url == model.photo.url }) else { return }
        let next = (index + delta + library.photos.count) % library.photos.count
        model.switchTo(library.photos[next])
    }
}
