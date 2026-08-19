import SwiftUI

struct ExportSheet: View {
    let photos: [Photo]
    @Binding var isPresented: Bool

    @State private var options = ExportOptions()
    @State private var progress: (done: Int, total: Int)?
    @State private var finishedURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(photos.count == 1 ? "Export \(photos[0].name)" : "Export \(photos.count) photos")
                .font(Theme.ui(15, .semibold))
                .foregroundStyle(Theme.ink)

            Picker("Format", selection: $options.format) {
                ForEach(ExportFormat.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if options.format.hasQuality {
                HStack(spacing: 10) {
                    Text("Quality").font(Theme.ui(11)).foregroundStyle(Theme.ink2)
                    Slider(value: $options.quality, in: 0.5...1.0)
                    Text(String(format: "%.0f%%", options.quality * 100))
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.ink2)
                        .frame(width: 36, alignment: .trailing)
                }
            }

            Text("Full resolution · Display P3 · into “Chiaro Exports” beside your originals")
                .font(Theme.ui(11))
                .foregroundStyle(Theme.ink3)

            HStack {
                if let progress {
                    Text("Exporting \(progress.done)/\(progress.total)…")
                        .font(Theme.mono(10)).foregroundStyle(Theme.amber)
                } else if let finishedURL {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([finishedURL])
                    }
                    .buttonStyle(.plain)
                    .font(Theme.ui(11))
                    .foregroundStyle(Theme.amber)
                }
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.escape)
                Button(finishedURL == nil ? "Export" : "Export Again") { runExport() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.amber)
                    .disabled(progress != nil || photos.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(Theme.ground)
    }

    private func runExport() {
        progress = (0, photos.count)
        finishedURL = nil
        let options = options
        let targets = photos
        Task.detached {
            var last: URL?
            for (i, photo) in targets.enumerated() {
                last = try? Exporter.export(photo, options: options)
                await MainActor.run { progress = (i + 1, targets.count) }
            }
            let result = last
            await MainActor.run {
                progress = nil
                finishedURL = result
            }
        }
    }
}
