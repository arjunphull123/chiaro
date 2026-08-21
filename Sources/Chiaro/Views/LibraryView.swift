import SwiftUI

/// Date-grouped, justified-rows gallery: sections per capture day (like Photos),
/// photos keep their shape within even-height rows.
struct LibraryView: View {
    @Bindable var library: Library
    let onExport: () -> Void

    @FocusState private var searchFocused: Bool

    enum ListSortKey: String { case name, starred, time, folder }
    @AppStorage("listSortKey") private var listSortRaw = ListSortKey.name.rawValue
    @AppStorage("listSortAscending") private var listSortAscending = true
    private var listSort: ListSortKey { ListSortKey(rawValue: listSortRaw) ?? .name }

    private func sortedForList(_ photos: [Photo]) -> [Photo] {
        let sorted: [Photo] = switch listSort {
        case .name: photos.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .starred: photos.sorted { !$0.starred && $1.starred }
        case .time: photos.sorted { ($0.captureDate ?? .distantPast) < ($1.captureDate ?? .distantPast) }
        case .folder: photos.sorted { library.relativeFolder($0).localizedStandardCompare(library.relativeFolder($1)) == .orderedAscending }
        }
        return listSortAscending ? sorted : sorted.reversed()
    }

    private let gap: CGFloat = 8

    private var visiblePhotos: [Photo] { library.visiblePhotos }

    /// Direct subfolders that contain photos, with counts, alphabetical.
    private var subfolders: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for photo in library.photos {
            if let top = library.topFolder(photo) { counts[top, default: 0] += 1 }
        }
        return counts.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { (name: $0.key, count: $0.value) }
    }

    private var hasSubfolders: Bool { !subfolders.isEmpty }

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
            if hasSubfolders {
                folderChips
            }
            if library.viewMode == .list {
                listColumnHeader
            }
            galleryScroll
        }
        // Clicking any part of the library that isn't itself a control gives
        // up the search field's focus, the way Esc already does. Behind
        // everything — including the header's own controls — so their taps
        // still win; this only catches clicks nothing else claimed.
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { searchFocused = false }
        )
        .onChange(of: library.folderURL) {
            library.folderScope = nil
            library.searchText = ""
        }
    }

    /// One chip per direct subfolder — the visible face of recursion.
    private var folderChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Chip(title: "All photos", selected: library.folderScope == nil) { library.folderScope = nil }
                ForEach(subfolders, id: \.name) { folder in
                    Chip(title: "\(folder.name) · \(folder.count)", selected: library.folderScope == folder.name) {
                        library.folderScope = library.folderScope == folder.name ? nil : folder.name
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(
            Rectangle().fill(Theme.panel.opacity(0.25))
                .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
        )
    }

    /// Finder-style sortable column titles for list mode.
    private var listColumnHeader: some View {
        HStack(spacing: 9) {
            Color.clear.frame(width: 30, height: 1)
            columnTitle("Name", key: .name, width: nil, alignment: .leading)
            Spacer(minLength: 12)
            columnTitle("★", key: .starred, width: nil, alignment: .trailing)
            if hasSubfolders && library.folderScope == nil {
                columnTitle("Folder", key: .folder, width: 120, alignment: .trailing)
            }
            Text("Exposure")
                .font(Theme.ui(10, .medium))
                .foregroundStyle(Theme.ink3)
                .frame(width: 190, alignment: .trailing)
            columnTitle("Time", key: .time, width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 25)
        .padding(.vertical, 5)
        .background(
            Rectangle().fill(Theme.panel.opacity(0.35))
                .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
        )
    }

    private func columnTitle(_ title: String, key: ListSortKey, width: CGFloat?, alignment: Alignment) -> some View {
        Button {
            if listSort == key {
                listSortAscending.toggle()
            } else {
                listSortRaw = key.rawValue
                listSortAscending = true
            }
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .font(Theme.ui(10, .medium))
                    .foregroundStyle(listSort == key ? Theme.ink : Theme.ink3)
                if listSort == key {
                    Image(systemName: listSortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                }
            }
            .frame(width: width, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help("Sort by \(title == "★" ? "starred" : title.lowercased())")
    }

    private var galleryScroll: some View {
        GeometryReader { geo in
            let width = geo.size.width - 32
            ScrollView {
                if sections.isEmpty && !library.searchText.isEmpty {
                    Text("No photos match \u{201C}\(library.searchText)\u{201D}")
                        .font(Theme.ui(12))
                        .foregroundStyle(Theme.ink3)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: gap) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(section.title)
                                    .font(Theme.ui(13.5, .semibold))
                                    .foregroundStyle(Theme.ink)
                                Text("\(section.photos.count)")
                                    .font(Theme.mono(10))
                                    .foregroundStyle(Theme.ink3)
                            }
                            .padding(.top, 14)
                            switch library.viewMode {
                            case .gallery:
                                ForEach(Array(justifiedRows(section.photos, width: width).enumerated()), id: \.offset) { _, row in
                                    HStack(spacing: gap) {
                                        ForEach(row.photos) { photo in
                                            tile(photo, height: row.height)
                                        }
                                    }
                                }
                            case .grid:
                                let cell = 80 + CGFloat(library.zoomLevel) * 140
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: cell, maximum: cell * 1.35), spacing: gap)], spacing: gap) {
                                    ForEach(section.photos) { photo in
                                        gridTile(photo)
                                    }
                                }
                            case .list:
                                VStack(spacing: 0) {
                                    ForEach(Array(sortedForList(section.photos).enumerated()), id: \.element.id) { index, photo in
                                        listRow(photo, alternate: index.isMultiple(of: 2))
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

    private func allChip() -> some View {
        let active = !library.filterStarred && !library.filterEdited
        return Button { library.filterStarred = false; library.filterEdited = false } label: {
            Text("All")
                .font(Theme.ui(10, .medium))
                .foregroundStyle(active ? Theme.amber : Theme.ink3)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(active ? Color.white.opacity(0.08) : .clear)
                )
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help("Every photo")
    }

    private func toggleChip(active: Bool, help: String, toggle: @escaping () -> Void, @ViewBuilder icon: () -> some View) -> some View {
        Button(action: toggle) {
            icon()
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(active ? Color.white.opacity(0.08) : .clear)
                )
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help(help)
    }

    /// A single selection is already shown by the tile's border — the count
    /// only earns its place once there's a set worth naming.
    private var selectionSuffix: String {
        library.selection.count >= 2 ? " · \(library.selection.count) selected" : ""
    }

    /// The RAW tally only earns its place in a genuinely mixed folder — "22 RAW"
    /// out of 22, or "0 RAW" out of 6, is just the photo count restated.
    private var countLabel: String {
        if library.filterRAW { return "\(visiblePhotos.count) photos\(selectionSuffix)" }
        let total = library.photos.count
        let raws = library.photos.filter(\.isRAW).count
        guard raws > 0, raws < total else { return "\(total) photos\(selectionSuffix)" }
        return "\(total) photos · \(raws) RAW\(selectionSuffix)"
    }

    /// Sheds the RAW tally, then itself, rather than truncating to "96 photo…".
    private var photoCount: some View {
        ViewThatFits {
            countText(countLabel)
            countText("\(library.photos.count) photos\(selectionSuffix)")
            EmptyView()
        }
    }

    private func countText(_ string: String) -> some View {
        Text(string)
            .font(Theme.mono(10))
            .foregroundStyle(Theme.ink3)
            .lineLimit(1)
            .fixedSize()
    }

    /// Pinned frosted header: title, zoom slider, and the real actions.
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 6) {
                AppMark(size: 18)
                Text("Chiaro")
                    .font(Theme.serif(19, .semibold))
                    .kerning(-0.5)
                    .foregroundStyle(Theme.ink)
                    .fixedSize() // the wordmark never wraps
            }
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 18)
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
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(library.folderName)
                    .font(Theme.ui(18, .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1) // truncates on a long name; never wraps
                photoCount
                    .layoutPriority(-1) // the count yields before the folder name does
            }
            Spacer()
            // Same presence pill and live intent as the edit rail (ADR 0008) —
            // a folder-wide pass happens with the library open, not the editor.
            // Only while an agent is actually working: the header is already full
            // at the 1080 minimum, and the connect call to action lives in the
            // edit rail. The library stays mounted under the editor (see
            // RootView), so width taken here clips both views.
            if library.agentActive || AgentStatus.shared.isConnected {
                AgentRailStatus(library: library)
                    .frame(maxWidth: 190)
                    .layoutPriority(-2)
            }
            HStack(spacing: 3) {
                allChip()
                toggleChip(active: library.filterStarred, help: "Starred only", toggle: { library.filterStarred.toggle() }) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(library.filterStarred ? Theme.amber : Theme.ink3)
                }
                toggleChip(active: library.filterEdited, help: "Edited only", toggle: { library.filterEdited.toggle() }) {
                    PinwheelMark()
                        .fill(library.filterEdited ? Theme.amber : Theme.ink3)
                        .frame(width: 11, height: 11)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
            Chip(title: "RAW", selected: library.filterRAW) { library.filterRAW.toggle() }
                .help("RAW files only")
            HStack(spacing: 3) {
                ForEach(Library.ViewMode.allCases, id: \.self) { mode in
                    Button { library.viewMode = mode } label: {
                        Image(systemName: mode.icon)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(library.viewMode == mode ? Theme.amber : Theme.ink3)
                            .frame(width: 26, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(library.viewMode == mode ? Color.white.opacity(0.08) : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .clickCursor()
                    .help(mode.help)
                }
                Button { library.showFilenames.toggle() } label: {
                    Image(systemName: "textformat")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(library.showFilenames ? Theme.amber : Theme.ink3)
                        .frame(width: 26, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(library.showFilenames ? Color.white.opacity(0.08) : .clear)
                        )
                        .opacity(library.viewMode == .list ? 0.35 : 1)
                }
                .buttonStyle(.plain)
                .clickCursor()
                .disabled(library.viewMode == .list)
                .help("Show filenames and shooting info on every photo")
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
            searchField
            if library.viewMode != .list {
                zoomSlider
            }
            if let folderURL = library.folderURL, Library.isRemovable(folderURL) {
                importControl
            }
            if let latest = Updater.shared.available {
                Button("Update to \(latest)") { Updater.shared.openReleases() }
                    .buttonStyle(OutlineButtonStyle()) // "Open in editor" is this surface's one primary
                    .clickCursor()
                    .fixedSize()
                    .contextMenu { Button("Dismiss") { Updater.shared.dismiss() } }
                    .help("Opens the releases page — Chiaro doesn't update itself")
            }
            // Actions never wrap; the zoom slider gives up width instead.
            Button("Open folder…") { openFolder() }
                .buttonStyle(OutlineButtonStyle())
                .clickCursor()
                .fixedSize()
                .help("⌘O")
            Button("Open in editor") { openSelectedInEditor() }
                .buttonStyle(AmberButtonStyle())
                .clickCursor()
                .keyboardShortcut(.defaultAction)
                // While the search field has focus, Return commits/edits the
                // query — it shouldn't also fire the library's default action.
                .disabled(library.selection.isEmpty || searchFocused)
                .fixedSize()
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

    /// Card offload: copies the shoot into ~/Pictures/Chiaro Library.
    @ViewBuilder private var importControl: some View {
        if let progress = library.importProgress {
            HStack(spacing: 7) {
                ProgressView(value: Double(progress.done), total: Double(progress.total))
                    .progressViewStyle(.linear)
                    .tint(Theme.amber)
                    .frame(width: 90)
                Text("\(progress.done)/\(progress.total)")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.ink2)
                    .monospacedDigit()
            }
        } else {
            Button {
                library.importToLibrary(library.selection.isEmpty ? library.photos : library.selectedPhotos)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 10, weight: .semibold))
                    Text(library.selection.isEmpty ? "Import all to library" : "Import \(library.selection.count) to library")
                }
            }
            .buttonStyle(GlassButtonStyle(tint: Theme.amber))
            .clickCursor()
            .help("Copy the shoot into your Chiaro Library, organized by capture day")
        }
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.ink3)
            TextField("Search", text: $library.searchText)
                .textFieldStyle(.plain)
                .font(Theme.ui(11.5))
                .foregroundStyle(Theme.ink)
                .focused($searchFocused)
                .onKeyPress(.escape) {
                    library.searchText = ""
                    searchFocused = false
                    return .handled
                }
                .frame(width: 108)
            if !library.searchText.isEmpty {
                Text("\(visiblePhotos.count)")
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.ink3)
                Button {
                    library.searchText = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.ink3)
                }
                .buttonStyle(.plain)
                .clickCursor()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(searchFocused ? Color.white.opacity(0.06) : .clear)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(searchFocused ? Theme.amber.opacity(0.5) : Theme.hairline))
        )
        .background(
            Button("") { searchFocused = true }
                .keyboardShortcut("f")
                .opacity(0)
                .frame(width: 0, height: 0)
        )
        .help("Filter by filename (⌘F)")
    }

    // MARK: - Zoom: one continuous value, slider + pinch (days ↔ months ↔ years)

    @State private var pinchBase: Double?

    private var zoomSlider: some View {
        HStack(spacing: 7) {
            Image(systemName: "square.grid.4x3.fill")
                .font(.system(size: 9)).foregroundStyle(Theme.ink3)
            Slider(value: zoomBinding, in: 0...1)
                .frame(minWidth: 44, idealWidth: 130, maxWidth: 130)
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
        for photo in visiblePhotos {
            if let date = photo.captureDate {
                let key = switch library.zoom {
                case .days: calendar.startOfDay(for: date)
                case .months: calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
                case .years: calendar.date(from: calendar.dateComponents([.year], from: date)) ?? calendar.startOfDay(for: date)
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

    @State private var hoveredTile: URL?

    private func agentTouched(_ photo: Photo) -> Bool {
        library.agentTouchedPhoto == photo.url
    }

    /// Soft amber halo, outside the tile's own edge so it never reads as the
    /// selection border — marks whichever tile an agent last named, and fades
    /// on its own once `agentTouchedPhoto` moves on or clears.
    private func agentTouchGlow(_ photo: Photo, cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(Theme.amber.opacity(0.8), lineWidth: 3)
            .blur(radius: 5)
            .opacity(agentTouched(photo) ? 1 : 0)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.8), value: library.agentTouchedPhoto)
    }

    /// RAW chip + star + Chiaro mark, bottom-right, sitting in the caption scrim.
    /// The chip carries the format when filenames are toggled off.
    @ViewBuilder private func badgePair(_ photo: Photo) -> some View {
        if photo.starred || photo.hasEdits || photo.isRAW {
            HStack(spacing: 6) {
                if photo.isRAW {
                    Text("RAW")
                        .font(Theme.mono(7, .medium)).kerning(0.8)
                        .foregroundStyle(Theme.amber)
                        .padding(.horizontal, 4).padding(.vertical, 1.5)
                        .background(RoundedRectangle(cornerRadius: 3).stroke(Theme.amber.opacity(0.5)))
                }
                if photo.starred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.amber)
                }
                if photo.hasEdits {
                    AppMark(size: 14)
                }
            }
            .padding(8)
            .shadow(color: .black.opacity(0.8), radius: 3)
            .allowsHitTesting(false)
        }
    }

    private func tile(_ photo: Photo, height: CGFloat) -> some View {
        let selected = library.selection.contains(photo.url)
        let width = height * photo.aspect
        // Fixed-size type in a tile that shrinks with the zoom slider: below
        // these sizes the caption outgrows its tile and drags the row apart.
        // 150pt is what the filename, a gap, and the badge cluster actually need;
        // below it the name truncates to "DSC039…" and reads worse than nothing.
        let showCaption = (hoveredTile == photo.url || library.showFilenames)
            && height >= 92 && width >= 150
        // .bottomLeading, and no greedy frame on the caption: a caption that
        // expands to infinity inflates the ZStack and shoves the photo sideways.
        return ZStack(alignment: .bottomLeading) {
            Group {
                if let cg = photo.thumbnail {
                    Image(cg, scale: 1, label: Text(photo.name))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Theme.panel.overlay(
                        Text(photo.filename).font(Theme.mono(9)).foregroundStyle(Theme.ink3)
                    )
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(selected ? Theme.amber : .clear, lineWidth: 2)
            )
            if showCaption {
                // One row, so the badges can never land on top of the metadata.
                // .center, not .bottom: badgePair carries its own uniform padding
                // for its other life as a corner overlay, which only cancels out
                // under center alignment — .bottom would count that padding twice
                // and float the badges above the filename.
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(photo.filename)
                            .font(Theme.ui(10.5, .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let exif = photo.exifSummary, height >= 124 {
                            Text(exif)
                                .font(Theme.mono(8.5))
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    badgePair(photo)
                }
                .padding(.horizontal, 9)
                .padding(.top, 46)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0),
                                .init(color: .black.opacity(0.5), location: 0.35),
                                .init(color: .black.opacity(0.95), location: 1)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: width, alignment: .leading)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 7, bottomTrailingRadius: 7))
                .allowsHitTesting(false)
            }
        }
        // Only when the caption isn't already carrying them.
        .overlay(alignment: .bottomTrailing) { if !showCaption { badgePair(photo) } }
        .overlay(agentTouchGlow(photo, cornerRadius: 7))
        .modifier(PhotoInteractions(photo: photo, library: library, hoveredTile: $hoveredTile, onExport: onExport))
    }

    /// Square grid cell: crop-filled, one-line caption, shared interactions.
    private func gridTile(_ photo: Photo) -> some View {
        let selected = library.selection.contains(photo.url)
        // Mirrors the cell size galleryScroll computes, so the caption can bow
        // out before it collides with the badges.
        let cell = 80 + CGFloat(library.zoomLevel) * 140
        let showCaption = (hoveredTile == photo.url || library.showFilenames) && cell >= 132
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let cg = photo.thumbnail {
                    Image(cg, scale: 1, label: Text(photo.name))
                        .resizable()
                        .scaledToFill()
                } else {
                    Theme.panel
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .bottom) {
                if showCaption {
                    // Same single row as the justified tile: name left, badges right.
                    HStack(alignment: .center, spacing: 6) {
                        Text(photo.filename)
                            .font(Theme.ui(9.5, .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        badgePair(photo)
                    }
                        .padding(.horizontal, 7)
                        .padding(.top, 24)
                        .padding(.bottom, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                        )
                        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 7, bottomTrailingRadius: 7))
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !showCaption { badgePair(photo) }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(selected ? Theme.amber : .clear, lineWidth: 2)
            )
            .overlay(agentTouchGlow(photo, cornerRadius: 7))
            .modifier(PhotoInteractions(photo: photo, library: library, hoveredTile: $hoveredTile, onExport: onExport))
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
            let volume = (folder.lastPathComponent == "DCIM" ? folder : folder.deletingLastPathComponent())
                .deletingLastPathComponent().lastPathComponent
            return SourceItem(
                id: folder, icon: "camera.fill", tint: Theme.amber,
                title: volume.isEmpty ? "Camera card" : volume,
                subtitle: cardSummary(folder)
            )
        }
        // A folder inside a card is already represented by the card's own row.
        items += Library.recentFolders().filter { recent in
            !items.contains { $0.id == recent || recent.path.hasPrefix($0.id.path + "/") }
        }.map { folder in
            SourceItem(
                id: folder, icon: "folder", tint: Theme.ink2,
                title: folder.lastPathComponent,
                subtitle: folder.deletingLastPathComponent().path
                    .replacingOccurrences(of: NSHomeDirectory(), with: "~")
            )
        }
        sources = items
    }

    // MARK: - Home (start screen): flat rows on the translucent ground

    private struct RecentEditItem: Identifiable {
        let id: URL
        var image: CGImage?
        var editDate: Date?
    }
    @State private var recentEdits: [RecentEditItem] = []

    private func refreshRecentEdits() {
        let urls = Array(Library.recentEdits().prefix(7))
        recentEdits = urls.map { RecentEditItem(id: $0, image: nil, editDate: Sidecar.lastEditDate(for: $0)) }
        for (position, url) in urls.enumerated() {
            let isHero = position == 0
            Task {
                let image = await Offload.on(Offload.render) {
                    // The hero says "Edited 2 minutes ago", so it should show the
                    // edit — a file thumbnail would show the untouched original.
                    // Strip thumbnails stay cheap.
                    guard isHero else {
                        return Library.scan(url, maxPixelSize: 480).image
                    }
                    let edit = Sidecar.read(for: url)?.edit ?? .neutral
                    guard let base = RawEngine.shared.preview(for: url, decode: RawEngine.DecodeParams(edit)) else {
                        return Library.scan(url, maxPixelSize: 1600).image
                    }
                    let rendered = RenderPipeline.render(base: base, edit: edit, personMask: nil, isRAW: Photo.isRAW(url))
                    return RawEngine.shared.context.createCGImage(rendered, from: rendered.extent)
                        ?? Library.scan(url, maxPixelSize: 1600).image
                }
                if let index = recentEdits.firstIndex(where: { $0.id == url }) {
                    recentEdits[index].image = image
                }
            }
        }
    }

    private func openRecentEdit(_ url: URL) {
        library.open(url.deletingLastPathComponent())
        if let photo = library.photos.first(where: { $0.url == url }) {
            library.edit(photo)
        }
    }

    /// "Good evening, Arjun" — hour-aware, first name from the macOS account.
    private var greeting: String {
        // --greeting "Good afternoon, Arjun": the salutation is clock-derived, so
        // capturing the start screen at 2am otherwise reads "Up late".
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--greeting"), i + 1 < args.count { return args[i + 1] }
        let hour = Calendar.current.component(.hour, from: Date())
        let salutation = hour < 5 ? "Up late" : hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        let first = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? salutation : "\(salutation), \(first)"
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 10)

            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 6) {
                    AppMark(size: 23)
                    Text("Chiaro")
                        .font(Theme.serif(26, .semibold))
                        .kerning(-0.8)
                        .foregroundStyle(Theme.ink)
                        .fixedSize()
                    Spacer()
                    ConnectAgentButton()
                }
                Text(greeting)
                    .font(Theme.serif(34))
                    .kerning(-1.1)
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
                if let hero = recentEdits.first {
                    heroCard(hero)
                }
                if recentEdits.count > 1 {
                    Text("Recent edits")
                        .font(Theme.ui(12, .medium))
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, 8)
                    HStack(spacing: 8) {
                        ForEach(recentEdits.dropFirst()) { item in
                            recentThumb(item)
                        }
                    }
                }
                Text("Sources")
                    .font(Theme.ui(12, .medium))
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 8)
                VStack(spacing: 6) {
                    ForEach(sources) { source in
                        sourceRow(
                            icon: source.icon, tint: source.tint,
                            title: source.title, subtitle: source.subtitle, url: source.id
                        )
                    }
                }
                HStack(spacing: 12) {
                    // Primary only when there's nothing to resume.
                    if recentEdits.isEmpty {
                        Button("Open folder…") { openFolder() }
                            .buttonStyle(AmberButtonStyle())
                            .clickCursor()
                            .keyboardShortcut("o")
                    } else {
                        Button("Open folder…") { openFolder() }
                            .buttonStyle(OutlineButtonStyle())
                            .clickCursor()
                            .keyboardShortcut("o")
                    }
                    Text("Or drop a folder anywhere")
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.ink3)
                }
                .padding(.top, 8)
            }
            .frame(width: 620)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 10)
            Spacer(minLength: 10)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onAppear {
            refreshSources()
            refreshRecentEdits()
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first,
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else { return false }
            library.open(url)
            return true
        }
    }

    private func heroCard(_ item: RecentEditItem) -> some View {
        // True to the photo's aspect, capped by height.
        let aspect = item.image.map { Double($0.width) / Double($0.height) } ?? 1.5
        let height: CGFloat = 300
        let width = min(620, height * CGFloat(aspect))
        return Button {
            openRecentEdit(item.id)
        } label: {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let cg = item.image {
                        Image(cg, scale: 1, label: Text(item.id.lastPathComponent))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Theme.panel
                    }
                }
                .frame(width: width, height: height)
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.id.deletingPathExtension().lastPathComponent)
                        .font(Theme.ui(13.5, .semibold))
                        .foregroundStyle(.white)
                    Text(heroSubtitle(item))
                        .font(Theme.mono(9.5))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .padding(13)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .clickCursor()
    }

    private func heroSubtitle(_ item: RecentEditItem) -> String {
        guard let date = item.editDate else { return "Continue editing" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Edited \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    private func recentThumb(_ item: RecentEditItem) -> some View {
        Button {
            openRecentEdit(item.id)
        } label: {
            Group {
                if let cg = item.image {
                    Image(cg, scale: 1, label: Text(item.id.lastPathComponent))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Theme.panel
                }
            }
            .frame(width: 97, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help(item.id.deletingPathExtension().lastPathComponent)
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
            .chiaroGlass(cornerRadius: 10)
        }
        .buttonStyle(.plain)
        .clickCursor()
    }

    private func cardSummary(_ folder: URL) -> String {
        let fm = FileManager.default
        // The row may point at DCIM itself when a card holds several subfolders.
        var files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        if folder.lastPathComponent == "DCIM" {
            files = files.flatMap { (try? fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
        }
        let photos = files.filter { Photo.imageExtensions.contains($0.pathExtension.lowercased()) }
        let raws = photos.filter { Photo.rawExtensions.contains($0.pathExtension.lowercased()) }
        let count = raws.isEmpty ? photos.count : raws.count
        return folder.lastPathComponent == "DCIM"
            ? "\(count) photos"
            : "\(count) photos · \(folder.lastPathComponent)"
    }

    /// Finder-style row: 26pt, zebra striping, full-row selection, columns.
    private func listRow(_ photo: Photo, alternate: Bool) -> some View {
        let selected = library.selection.contains(photo.url)
        return HStack(spacing: 9) {
            Group {
                if let cg = photo.thumbnail {
                    Image(cg, scale: 1, label: Text(photo.name))
                        .resizable()
                        .scaledToFill()
                } else {
                    Theme.panel
                }
            }
            .frame(width: 30, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(photo.filename)
                .font(Theme.ui(11.5, selected ? .medium : .regular))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            if photo.hasEdits {
                AppMark(size: 9)
            }
            Spacer(minLength: 12)
            if photo.starred {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.amber)
            }
            if hasSubfolders && library.folderScope == nil {
                Text(library.relativeFolder(photo))
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(width: 120, alignment: .trailing)
            }
            if let exif = photo.exifSummary {
                Text(exif)
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
                    .frame(width: 190, alignment: .trailing)
            }
            Text(photo.captureDate?.formatted(date: .omitted, time: .shortened) ?? "—")
                .font(Theme.mono(9))
                .foregroundStyle(Theme.ink3)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(selected ? Theme.amber.opacity(0.22)
                    : hoveredTile == photo.url ? Color.white.opacity(0.05)
                    : alternate ? Color.white.opacity(0.03) : .clear)
        )
        .overlay(agentTouchGlow(photo, cornerRadius: 5))
        .modifier(PhotoInteractions(photo: photo, library: library, hoveredTile: $hoveredTile, onExport: onExport))
    }

    private func openSelectedInEditor() {
        let target = library.lastSelected.flatMap { url in
            library.photos.first { $0.url == url && library.selection.contains(url) }
        } ?? library.photos.first { library.selection.contains($0.url) }
        if let target { library.edit(target) }
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

/// One set of behaviors for every library representation: hover tracking,
/// select / cmd-select, double-click to edit, and the photo context menu.
private struct PhotoInteractions: ViewModifier {
    let photo: Photo
    let library: Library
    @Binding var hoveredTile: URL?
    let onExport: () -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .clickCursor()
            .onHover { inside in
                hoveredTile = inside ? photo.url : (hoveredTile == photo.url ? nil : hoveredTile)
            }
            .gesture(TapGesture(count: 2).onEnded { library.edit(photo) })
            .simultaneousGesture(TapGesture().modifiers(.command).onEnded {
                if library.selection.contains(photo.url) {
                    library.selection.remove(photo.url)
                } else {
                    library.selection.insert(photo.url)
                    library.lastSelected = photo.url
                }
            })
            .simultaneousGesture(TapGesture().onEnded {
                library.selection = [photo.url]
                library.lastSelected = photo.url
            })
            .contextMenu {
                Button("Open in editor") { library.edit(photo) }
                Button("Export…") {
                    library.selection = [photo.url]
                    onExport()
                }
                Divider()
                Button("Copy edits") { library.copiedEdit = photo.edit }
                Button("Paste edits") {
                    guard let copied = library.copiedEdit else { return }
                    if let editor = library.activeEditor, editor.photo.url == photo.url {
                        editor.commitDiscrete(copied)
                    } else {
                        photo.edit = copied
                        Sidecar.write(for: photo)
                    }
                }
                .disabled(library.copiedEdit == nil)
            }
    }
}
