import SwiftUI

/// Date-grouped, justified-rows gallery: sections per capture day (like Photos),
/// photos keep their shape within even-height rows.
struct LibraryView: View {
    @Bindable var library: Library
    let onExport: () -> Void

    private let gap: CGFloat = 8

    private var targetRowHeight: CGFloat {
        64 + CGFloat(library.zoomLevel) * 190
    }

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
        VStack(spacing: 0) {
            header
            galleryScroll
        }
    }

    private var galleryScroll: some View {
        GeometryReader { geo in
            let width = geo.size.width - 32
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: gap) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(section.title)
                                    .font(Theme.serif(16))
                                    .foregroundStyle(Theme.ink)
                                Text("\(section.photos.count)")
                                    .font(Theme.mono(10))
                                    .foregroundStyle(Theme.ink3)
                            }
                            .padding(.top, 14)
                            ForEach(Array(justifiedRows(section.photos, width: width).enumerated()), id: \.offset) { _, row in
                                HStack(spacing: gap) {
                                    ForEach(row.photos) { photo in
                                        tile(photo, height: row.height)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .simultaneousGesture(zoomGesture)
        }
    }

    /// Pinned frosted header: title, zoom slider, and the real actions.
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                library.close()
            } label: {
                Image(systemName: "house")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.ink2)
                    .frame(width: 26, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7).stroke(Theme.hairline))
            }
            .buttonStyle(.plain)
            .clickCursor()
            .help("Back to the start screen (⌘W)")
            Text(library.folderName)
                .font(Theme.ui(19, .semibold))
                .foregroundStyle(Theme.ink)
            Text("\(library.photos.count) photos · \(library.photos.filter(\.isRAW).count) RAW")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.ink3)
            Spacer()
            zoomSlider
            Button("Open Folder…") { openFolder() }
                .buttonStyle(OutlineButtonStyle())
                .clickCursor()
                .help("⌘O")
            Button("Open in Editor") {
                if let photo = library.selectedPhotos.first { library.edit(photo) }
            }
            .buttonStyle(AmberButtonStyle())
            .clickCursor()
            .disabled(library.selection.isEmpty)
            .opacity(library.selection.isEmpty ? 0.4 : 1)
            .help("Edit the selected photo (⏎)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            Rectangle().fill(.ultraThinMaterial)
                .overlay(Theme.panel.opacity(0.55))
                .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
                .ignoresSafeArea()
        )
    }

    // MARK: - Zoom: one continuous value, slider + pinch (days ↔ months ↔ years)

    @State private var pinchBase: Double?

    private var zoomSlider: some View {
        HStack(spacing: 7) {
            Image(systemName: "square.grid.4x3.fill")
                .font(.system(size: 9)).foregroundStyle(Theme.ink3)
            Slider(value: zoomBinding, in: 0...1)
                .frame(width: 130)
                .tint(Theme.amber)
                .controlSize(.mini)
            Image(systemName: "square.fill")
                .font(.system(size: 11)).foregroundStyle(Theme.ink3)
        }
        .help("Thumbnail size — small groups by year, medium by month, large by day")
    }

    private var zoomBinding: Binding<Double> {
        Binding(
            get: { library.zoomLevel },
            set: { newValue in
                let before = library.zoom
                library.zoomLevel = newValue
                if library.zoom != before {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            }
        )
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { g in
                if pinchBase == nil { pinchBase = library.zoomLevel }
                zoomBinding.wrappedValue = (pinchBase! + (g.magnification - 1) * 0.55)
                    .clamped(to: 0...1)
            }
            .onEnded { _ in pinchBase = nil }
    }

    // MARK: - Date sections

    private struct DaySection: Identifiable {
        let id: Date
        let title: String
        var photos: [Photo]
    }

    private var sections: [DaySection] {
        let calendar = Calendar.current
        var byPeriod: [Date: [Photo]] = [:]
        var undated: [Photo] = []
        for photo in library.photos {
            if let date = photo.captureDate {
                let key = switch library.zoom {
                case .days: calendar.startOfDay(for: date)
                case .months: calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
                case .years: calendar.date(from: calendar.dateComponents([.year], from: date))!
                }
                byPeriod[key, default: []].append(photo)
            } else {
                undated.append(photo)
            }
        }
        let formatter = switch library.zoom {
        case .days: Self.dayFormatter
        case .months: Self.monthFormatter
        case .years: Self.yearFormatter
        }
        // Most recent first.
        var result = byPeriod.keys.sorted(by: >).map { period in
            DaySection(id: period, title: formatter.string(from: period), photos: byPeriod[period]!)
        }
        if !undated.isEmpty {
            result.append(DaySection(id: .distantFuture, title: "Undated", photos: undated))
        }
        return result
    }

    private static let dayFormatter = makeFormatter("EEEE · MMMM d, yyyy")
    private static let monthFormatter = makeFormatter("MMMM yyyy")
    private static let yearFormatter = makeFormatter("yyyy")

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        return f
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
        .clickCursor()
        .gesture(TapGesture(count: 2).onEnded {
            library.edit(photo)
        })
        .simultaneousGesture(TapGesture().modifiers(.command).onEnded {
            if selected { library.selection.remove(photo.url) }
            else { library.selection.insert(photo.url) }
        })
        .simultaneousGesture(TapGesture().onEnded {
            library.selection = [photo.url]
        })
    }

    private struct SourceItem: Identifiable {
        let id: URL
        let icon: String
        let tint: Color
        let title: String
        let subtitle: String
    }
    @State private var sources: [SourceItem] = []

    /// Card/recent discovery stats folders (slow over USB) — computed once, not per frame.
    private func refreshSources() {
        var items: [SourceItem] = Library.cameraCardFolders().map { folder in
            SourceItem(
                id: folder, icon: "camera.fill", tint: Theme.amber,
                title: "\(folder.lastPathComponent) — camera card",
                subtitle: cardSummary(folder)
            )
        }
        items += Library.recentFolders().filter { recent in !items.contains { $0.id == recent } }.map { folder in
            SourceItem(
                id: folder, icon: "folder", tint: Theme.ink2,
                title: folder.lastPathComponent,
                subtitle: folder.deletingLastPathComponent().path
                    .replacingOccurrences(of: NSHomeDirectory(), with: "~")
            )
        }
        sources = items
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 0) {
                Text("Chiaro")
                    .font(Theme.ui(44, .semibold))
                    .foregroundStyle(Theme.ink)
                Rectangle().fill(Theme.amber).frame(width: 44, height: 3)
                    .padding(.top, 10)
                Text("A quiet, fast RAW editor. Your originals are never touched.")
                    .font(Theme.ui(13.5))
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 14)

                VStack(spacing: 6) {
                    ForEach(sources) { source in
                        sourceRow(
                            icon: source.icon, tint: source.tint,
                            title: source.title, subtitle: source.subtitle, url: source.id
                        )
                    }
                }
                .padding(.top, 28)

                HStack(spacing: 12) {
                    Button("Open Folder…") { openFolder() }
                        .buttonStyle(AmberButtonStyle())
                        .clickCursor()
                        .keyboardShortcut("o")
                    Text("or drop a folder anywhere")
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.ink3)
                }
                .padding(.top, 22)
            }
            .frame(width: 400)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onAppear { refreshSources() }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first,
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else { return false }
            library.open(url)
            return true
        }
    }

    private func sourceRow(icon: String, tint: Color, title: String, subtitle: String, url: URL) -> some View {
        Button {
            library.open(url)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(tint)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Theme.ui(12.5, .medium)).foregroundStyle(Theme.ink)
                    Text(subtitle).font(Theme.mono(9.5)).foregroundStyle(Theme.ink3).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.hairline))
        }
        .buttonStyle(.plain)
        .clickCursor()
    }

    private func cardSummary(_ folder: URL) -> String {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let photos = files.filter { Photo.imageExtensions.contains($0.pathExtension.lowercased()) }
        let raws = photos.filter { Photo.rawExtensions.contains($0.pathExtension.lowercased()) }
        return "\(raws.isEmpty ? photos.count : raws.count) photos · \(folder.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent)"
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

    private func justifiedRows(_ photos: [Photo], width: CGFloat) -> [Row] {
        guard width > 100 else { return [] }
        var rows: [Row] = []
        var current: [Photo] = []
        var aspectSum: CGFloat = 0
        for photo in photos {
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
