import SwiftUI

/// Export sheet in the rail's design language: format rows with plain-language
/// blurbs, a live size estimate, long-edge sizing, color space, and an advanced
/// disclosure. Layout follows the two-tier convention (research: docs/adr/0009 era).
struct ExportSheet: View {
    let photos: [Photo]
    @Binding var isPresented: Bool

    @State private var options = ExportOptions()
    @State private var sizeChoice: SizeChoice = .full
    @State private var customEdge = "2048"
    @State private var showAdvanced = false
    @State private var revealInFinder = true
    @State private var progress: (done: Int, total: Int)?
    @State private var finishedURL: URL?
    @State private var failure: (count: Int, reason: String)?

    enum SizeChoice: String, CaseIterable, Identifiable {
        case full = "Full size"
        case web = "2048 px"
        case custom = "Custom"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(photos.count == 1 ? "Export \(photos[0].name)" : "Export \(photos.count) photos")
                .font(Theme.ui(15, .semibold))
                .foregroundStyle(Theme.ink)

            sectionLabel("Format")
            VStack(spacing: 4) {
                ForEach(ExportFormat.allCases) { format in
                    choiceRow(
                        title: format.rawValue, blurb: format.blurb,
                        selected: options.format == format
                    ) { options.format = format }
                }
            }

            if options.format.hasQuality {
                sectionLabel("Quality")
                HStack(spacing: 10) {
                    Slider(value: $options.quality, in: 0.5...1.0)
                        .tint(Theme.amber)
                        .controlSize(.small)
                    Text("\(Int(options.quality * 100))")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.amber)
                        .frame(width: 26, alignment: .trailing)
                        .monospacedDigit()
                }
            }

            if options.format != .original {
                sectionLabel("Size")
                HStack(spacing: 4) {
                    ForEach(SizeChoice.allCases) { choice in
                        chip(choice.rawValue, selected: sizeChoice == choice) { sizeChoice = choice }
                    }
                    if sizeChoice == .custom {
                        TextField("px", text: $customEdge)
                            .textFieldStyle(.plain)
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.amber)
                            .frame(width: 52)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
                        Text("px long edge").font(Theme.ui(10)).foregroundStyle(Theme.ink3)
                    }
                }

                sectionLabel("Color")
                HStack(spacing: 4) {
                    ForEach(ExportColorSpace.allCases) { space in
                        chip(space.rawValue, selected: options.colorSpace == space) {
                            options.colorSpace = space
                        }
                        .help(space.blurb)
                    }
                }
            }

            DisclosureGroup(isExpanded: Binding(
                get: { showAdvanced },
                set: { value in withAnimation(.easeOut(duration: 0.18)) { showAdvanced = value } }
            )) {
                VStack(alignment: .leading, spacing: 10) {
                    if options.format == .tiff {
                        Toggle("16-bit color", isOn: $options.tiff16Bit)
                            .toggleStyle(.switch).controlSize(.mini).tint(Theme.amber)
                            .font(Theme.ui(11)).foregroundStyle(Theme.ink2)
                    }
                    if options.format != .original {
                        HStack(spacing: 8) {
                            Text("Print resolution").font(Theme.ui(11)).foregroundStyle(Theme.ink2)
                            TextField("", value: $options.ppi, format: .number)
                                .textFieldStyle(.plain)
                                .font(Theme.mono(11)).foregroundStyle(Theme.amber)
                                .frame(width: 40)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.06)))
                            Text("ppi · metadata only").font(Theme.ui(10)).foregroundStyle(Theme.ink3)
                        }
                        Toggle("Strip metadata (camera info, GPS)", isOn: $options.stripMetadata)
                            .toggleStyle(.switch).controlSize(.mini).tint(Theme.amber)
                            .font(Theme.ui(11)).foregroundStyle(Theme.ink2)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("More options")
                    .font(Theme.ui(11, .medium))
                    .foregroundStyle(Theme.ink2)
            }
            .tint(Theme.ink3)

            Divider().overlay(Theme.hairline)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(estimateText)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.ink2)
                    HStack(spacing: 6) {
                        Text("→ \(destinationText)")
                            .font(Theme.ui(10))
                            .foregroundStyle(Theme.ink3)
                            .lineLimit(1)
                        Button("Change…") { chooseDestination() }
                            .buttonStyle(.plain)
                            .font(Theme.ui(10, .medium))
                            .foregroundStyle(Theme.amber)
                            .clickCursor()
                    }
                }
                Spacer()
                Toggle("Show in Finder", isOn: $revealInFinder)
                    .toggleStyle(.switch).controlSize(.mini).tint(Theme.amber)
                    .font(Theme.ui(10.5)).foregroundStyle(Theme.ink2)
            }

            HStack {
                if let progress {
                    Text("Exporting \(progress.done)/\(progress.total)…")
                        .font(Theme.mono(10)).foregroundStyle(Theme.amber)
                } else if let failure {
                    Text("\(failure.count) of \(photos.count) failed — \(failure.reason)")
                        .font(Theme.mono(10)).foregroundStyle(Theme.danger)
                } else if finishedURL != nil {
                    Text("Done ✓").font(Theme.mono(10)).foregroundStyle(Theme.amber)
                }
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(OutlineButtonStyle())
                    .clickCursor()
                    .keyboardShortcut(.escape)
                Button(photos.count == 1 ? "Export photo" : "Export \(photos.count) photos") {
                    runExport()
                }
                .buttonStyle(AmberButtonStyle())
                .clickCursor()
                .keyboardShortcut(.return)
                .disabled(progress != nil || photos.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 400)
        .background(Theme.ground)
        .animation(.easeOut(duration: 0.18), value: showAdvanced)
        .animation(.easeOut(duration: 0.15), value: options.format)
        .onChange(of: sizeChoice) { syncMaxDimension() }
        .onChange(of: customEdge) { syncMaxDimension() }
    }

    // MARK: - Pieces

    private func sectionLabel(_ title: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(Theme.ui(11, .medium))
                .foregroundStyle(Theme.ink2)
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    private func choiceRow(title: String, blurb: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).font(Theme.ui(11.5, selected ? .medium : .regular))
                    .foregroundStyle(selected ? Theme.ink : Theme.ink2)
                Spacer()
                Text(blurb).font(Theme.ui(10)).foregroundStyle(Theme.ink3)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(selected ? 0.08 : 0.03)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? Theme.amber.opacity(0.5) : .clear))
        }
        .buttonStyle(.plain)
        .clickCursor()
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Chip(title: title, selected: selected, action: action)
    }

    // MARK: - Logic

    private func syncMaxDimension() {
        switch sizeChoice {
        case .full: options.maxDimension = nil
        case .web: options.maxDimension = 2048
        case .custom: options.maxDimension = Double(customEdge.filter(\.isNumber))
        }
    }

    private var estimateText: String {
        if options.format == .original {
            let total = photos.reduce(0.0) { sum, p in
                sum + Double((try? p.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 20_000_000)
            }
            return "≈ \(format(bytes: total)) total"
        }
        let total = photos.reduce(0.0) { sum, p in
            let pixels = Double((p.pixelSize?.width ?? 5472) * (p.pixelSize?.height ?? 3648))
            return sum + Exporter.estimatedBytes(pixels: pixels, options: options)
        }
        let dims = photos.first?.pixelSize.map {
            exportDims($0)
        } ?? ""
        return "≈ \(format(bytes: total))\(photos.count > 1 ? " total" : dims)"
    }

    private func exportDims(_ size: CGSize) -> String {
        var w = size.width, h = size.height
        if let maxDim = options.maxDimension, maxDim < max(w, h) {
            let s = maxDim / max(w, h)
            w *= s; h *= s
        }
        return " · \(Int(w)) × \(Int(h))"
    }

    private func format(bytes: Double) -> String {
        bytes >= 1_000_000_000
            ? String(format: "%.1f GB", bytes / 1_000_000_000)
            : String(format: "%.1f MB", bytes / 1_000_000)
    }

    private var destinationText: String {
        if let chosen = options.destination {
            return chosen.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        }
        if let first = photos.first, Library.isRemovable(first.url) {
            return "Pictures/Chiaro Exports"
        }
        return "“Chiaro Exports”, beside your originals"
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export here"
        if panel.runModal() == .OK { options.destination = panel.url }
    }

    private func runExport() {
        progress = (0, photos.count)
        finishedURL = nil
        failure = nil
        syncMaxDimension()
        var options = options
        let targets = photos
        if options.destination == nil, let first = targets.first, Library.isRemovable(first.url) {
            options.destination = FileManager.default
                .urls(for: .picturesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Chiaro Exports")
        }
        let finalOptions = options
        let reveal = revealInFinder
        // Snapshot url/edit/name on the main actor — Photo is non-Sendable and
        // main-actor-mutated, so the render queue must never touch it directly.
        let jobs = targets.map { (url: $0.url, edit: $0.edit, name: $0.name) }
        Task {
            var last: URL?
            var failureCount = 0
            var firstReason: String?
            for (i, job) in jobs.enumerated() {
                let result = await Offload.on(Offload.render) { () -> Result<URL, Error> in
                    Result { try Exporter.export(url: job.url, edit: job.edit, name: job.name, options: finalOptions) }
                }
                switch result {
                case .success(let url): last = url
                case .failure(let error):
                    failureCount += 1
                    if firstReason == nil { firstReason = error.localizedDescription }
                }
                progress = (i + 1, jobs.count)
            }
            progress = nil
            if failureCount > 0 {
                failure = (failureCount, firstReason ?? "Unknown error")
            }
            finishedURL = last
            if reveal, let last { NSWorkspace.shared.activateFileViewerSelecting([last]) }
            // Dismiss once the work is done: the sheet has nothing left to say,
            // and on a reveal it would otherwise sit behind the Finder window
            // the export just opened. Long enough for "Done ✓" to register as
            // confirmation. A failure keeps the sheet up, since that message is
            // the only place the reason is reported.
            if failureCount == 0 {
                try? await Task.sleep(for: .milliseconds(650))
                isPresented = false
            }
        }
    }
}
