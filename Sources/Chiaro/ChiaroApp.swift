import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            MCPServer.shared.library?.activeEditor?.saveNow()
        }
        MCPServer.shared.stop()
    }
}

@main
struct ChiaroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library = Library()
    @State private var exporting: Bool

    init() {
        _exporting = State(initialValue: CommandLine.arguments.contains("--show-export"))
        Theme.registerFonts()
        let lib = library
        DispatchQueue.main.async {
            MCPServer.shared.start(library: lib)
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
                if let editName, let photo = lib.photos.first(where: { $0.name == editName }) {
                    lib.edit(photo)
                }
                if let exportName, let photo = lib.photos.first(where: { $0.name == exportName }) {
                    Task.detached {
                        var testEdit = EditState()
                        testEdit.exposure = 0.5
                        testEdit.vibrance = 25
                        testEdit.blurF = 0.6
                        testEdit.relight = 20
                        let edit = testEdit
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
                .frame(minWidth: 1080, minHeight: 700)
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
            CommandGroup(replacing: .undoRedo) {
                Button("Undo Edit") { library.activeEditor?.undo() }
                    .keyboardShortcut("z")
                    .disabled(!(library.activeEditor?.canUndo ?? false))
                Button("Redo Edit") { library.activeEditor?.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!(library.activeEditor?.canRedo ?? false))
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
            Theme.ground.opacity(0.6).ignoresSafeArea()
            if let editing = library.editing {
                EditView(library: library, photo: editing, onExport: { exporting = true })
            } else {
                LibraryView(library: library, onExport: { exporting = true })
            }
        }
        .containerBackground(.clear, for: .window)
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
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    // The window doesn't exist at makeNSView time; configure once attached.
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window, window.isOpaque else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
        }
    }
}
