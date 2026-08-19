import SwiftUI

@main
struct ChiaroApp: App {
    @State private var library = Library()
    @State private var exporting = false

    init() {
        Theme.registerFonts()
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        // Dev harness: `swift run Chiaro --open <folder> [--edit <name>] [--snapshot <png>]`
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let path = args[i + 1]
            let lib = library
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                let renderer = ImageRenderer(
                    content: RootView(library: lib, exporting: .constant(false))
                        .frame(width: 1400, height: 900)
                        .background(Theme.ground)
                        .preferredColorScheme(.dark)
                )
                renderer.scale = 2
                if let cg = renderer.cgImage {
                    let rep = NSBitmapImageRep(cgImage: cg)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: path))
                }
                NSApp.terminate(nil)
            }
        }
        if let i = args.firstIndex(of: "--open"), i + 1 < args.count {
            let lib = library
            let folder = URL(fileURLWithPath: args[i + 1])
            let editName = args.firstIndex(of: "--edit").flatMap { j in
                j + 1 < args.count ? args[j + 1] : nil
            }
            let exportName = args.firstIndex(of: "--export-test").flatMap { j in
                j + 1 < args.count ? args[j + 1] : nil
            }
            DispatchQueue.main.async {
                lib.open(folder)
                if let editName {
                    lib.editing = lib.photos.first { $0.name == editName }
                }
                if let exportName, let photo = lib.photos.first(where: { $0.name == exportName }) {
                    Task.detached {
                        var edit = EditState()
                        edit.exposure = 0.5
                        edit.vibrance = 25
                        edit.blurF = 0.6
                        edit.relight = 20
                        await MainActor.run { photo.edit = edit }
                        do {
                            var options = ExportOptions()
                            options.destination = FileManager.default.temporaryDirectory
                                .appendingPathComponent("ChiaroExportTest")
                            let url = try Exporter.export(photo, options: options)
                            print("EXPORTED: \(url.path)")
                        } catch {
                            print("EXPORT FAILED: \(error)")
                        }
                        await NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(library: library, exporting: $exporting)
                .preferredColorScheme(.dark)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Folder…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    if panel.runModal() == .OK, let url = panel.url { library.open(url) }
                }
                .keyboardShortcut("o")
            }
            CommandGroup(after: .pasteboard) {
                Button("Copy Edit") { library.copyEdit() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Paste Edit") { library.pasteEdit() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                    .disabled(library.copiedEdit == nil)
                Divider()
                Button("Export…") { exporting = true }
                    .keyboardShortcut("e")
            }
        }
    }
}

struct RootView: View {
    @Bindable var library: Library
    @Binding var exporting: Bool

    var body: some View {
        ZStack {
            // The window itself is translucent: desktop light bleeds through the
            // graphite ground, and the rail's frost samples it (ADR 0006).
            WindowBackdrop().ignoresSafeArea()
            Theme.ground.opacity(0.82).ignoresSafeArea()
            if let editing = library.editing {
                EditView(library: library, photo: editing)
            } else {
                LibraryView(library: library)
            }
        }
        .sheet(isPresented: $exporting) {
            ExportSheet(
                photos: library.editing.map { [$0] } ?? library.selectedPhotos,
                isPresented: $exporting
            )
        }
    }
}

/// Behind-window blur that makes the whole window translucent.
struct WindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        DispatchQueue.main.async {
            if let window = view.window {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.titlebarAppearsTransparent = true
            }
        }
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
