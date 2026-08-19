import SwiftUI

/// Justified-rows gallery: photos keep their shape, packed into even-height rows.
struct LibraryView: View {
    @Bindable var library: Library

    private let targetRowHeight: CGFloat = 176
    private let gap: CGFloat = 8

    var body: some View {
        Group {
            if library.photos.isEmpty {
                emptyState
            } else {
                gallery
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gallery: some View {
        GeometryReader { geo in
            let rows = justifiedRows(width: geo.size.width - 28)
            ScrollView {
                VStack(alignment: .leading, spacing: gap) {
                    toolbar
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: gap) {
                            ForEach(row.photos) { photo in
                                tile(photo, height: row.height)
                            }
                        }
                    }
                }
                .padding(14)
                .padding(.top, 30)
            }
        }
    }

    private var toolbar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(library.folderName)
                .font(Theme.ui(13, .semibold))
                .foregroundStyle(Theme.ink)
            Text("\(library.photos.count) photos")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.ink3)
            Spacer()
            Button("Open Folder…") { openFolder() }
                .font(Theme.ui(11))
                .buttonStyle(.plain)
                .foregroundStyle(Theme.ink2)
        }
        .padding(.bottom, 6)
    }

    private func tile(_ photo: Photo, height: CGFloat) -> some View {
        let selected = library.selection.contains(photo.url)
        return ZStack(alignment: .bottomTrailing) {
            Group {
                if let cg = photo.thumbnail {
                    Image(cg, scale: 1, label: Text(photo.name))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Theme.panel.overlay(
                        Text(photo.name).font(Theme.mono(9)).foregroundStyle(Theme.ink3)
                    )
                }
            }
            .frame(width: height * photo.aspect, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(selected ? Theme.amber : .clear, lineWidth: 2)
            )
            HStack(spacing: 4) {
                if photo.rating > 0 {
                    Text(String(repeating: "★", count: photo.rating))
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.amber)
                }
                if photo.hasEdits {
                    Circle().fill(Theme.amber).frame(width: 6, height: 6)
                }
            }
            .padding(6)
            .shadow(color: .black.opacity(0.6), radius: 2)
        }
        .contentShape(Rectangle())
        .gesture(TapGesture(count: 2).onEnded {
            library.selection = [photo.url]
            library.editing = photo
        })
        .simultaneousGesture(TapGesture().modifiers(.command).onEnded {
            if selected { library.selection.remove(photo.url) }
            else { library.selection.insert(photo.url) }
        })
        .simultaneousGesture(TapGesture().onEnded {
            library.selection = [photo.url]
        })
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("Chiaro")
                .font(Theme.ui(30, .semibold))
                .foregroundStyle(Theme.ink)
            Text("Point it at a folder of photos. Originals are never touched.")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.ink2)
            Button(action: openFolder) {
                Text("Open Folder…")
                    .font(Theme.ui(13, .medium))
                    .foregroundStyle(Color(hex: 0x131315))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Theme.amber))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("o")
        }
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url {
            library.open(url)
        }
    }

    // MARK: - Justified layout

    private struct Row {
        var photos: [Photo]
        var height: CGFloat
    }

    private func justifiedRows(width: CGFloat) -> [Row] {
        guard width > 100 else { return [] }
        var rows: [Row] = []
        var current: [Photo] = []
        var aspectSum: CGFloat = 0
        for photo in library.photos {
            current.append(photo)
            aspectSum += photo.aspect
            let rowHeight = (width - gap * CGFloat(current.count - 1)) / aspectSum
            if rowHeight <= targetRowHeight {
                rows.append(Row(photos: current, height: rowHeight))
                current = []
                aspectSum = 0
            }
        }
        if !current.isEmpty {
            let height = min(targetRowHeight, (width - gap * CGFloat(current.count - 1)) / aspectSum)
            rows.append(Row(photos: current, height: height))
        }
        return rows
    }
}
