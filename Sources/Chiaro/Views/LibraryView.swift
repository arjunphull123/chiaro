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
                                    .font(Theme.ui(13, .semibold))
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
            Text(library.folderName)
                .font(Theme.ui(19, .semibold))
                .foregroundStyle(Theme.ink)
            Text("\(library.photos.count) photos · \(library.photos.filter(\.isRAW).count) RAW")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.ink3)
            Spacer()
            zoomSlider
            ConnectAgentButton()
            Button("Export…") { onExport() }
                .buttonStyle(AmberButtonStyle())
                .disabled(library.selection.isEmpty)
                .opacity(library.selection.isEmpty ? 0.4 : 1)
                .help("Export selected photos (⌘E)")
            Button("Open Folder…") { openFolder() }
                .buttonStyle(AmberButtonStyle())
                .help("⌘O")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            Rectangle().fill(.ultraThinMaterial)
                .overlay(Theme.panel.opacity(0.72))
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

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("Chiaro")
                .font(Theme.ui(30, .semibold))
                .foregroundStyle(Theme.ink)
            Text("Point it at a folder of photos — or your camera's card. Originals are never touched.")
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
