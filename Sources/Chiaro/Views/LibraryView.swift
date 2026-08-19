import SwiftUI

/// Date-grouped, justified-rows gallery: sections per capture day (like Photos),
/// photos keep their shape within even-height rows.
struct LibraryView: View {
    @Bindable var library: Library
    let onExport: () -> Void

    private let gap: CGFloat = 8

    private var targetRowHeight: CGFloat {
        switch library.zoom {
        case .days: 176
        case .months: 118
        case .years: 78
        }
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
        GeometryReader { geo in
            let width = geo.size.width - 32
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
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
                .padding(.top, 28)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(library.folderName)
                .font(Theme.ui(22, .semibold))
                .foregroundStyle(Theme.ink)
            Text("\(library.photos.count) photos · \(library.photos.filter(\.isRAW).count) RAW")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.ink3)
            Spacer()
            Picker("", selection: $library.zoom) {
                ForEach(Library.Zoom.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)
            if !library.selection.isEmpty {
                Button("Export…") { onExport() }
                    .font(Theme.ui(12, .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.amber)
            }
            Button("Open Folder…") { openFolder() }
                .font(Theme.ui(12))
                .buttonStyle(.plain)
                .foregroundStyle(Theme.ink2)
        }
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
        var result = byPeriod.keys.sorted().map { period in
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
