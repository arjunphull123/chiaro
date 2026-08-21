import SwiftUI
import TipKit
import SceneKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // One library, one window: tabbing only adds a dozen dead menu items.
        NSWindow.allowsAutomaticWindowTabbing = false
        Updater.checkInBackground()
    }

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
        FirstMouse.enableGlobally()
        if CommandLine.arguments.contains("--show-tips") { Tips.showAllTipsForTesting() }
        try? Tips.configure([.displayFrequency(.immediate), .datastoreLocation(.applicationDefault)])
        let lib = library
        // --quiet: dev-harness launches don't steal focus from the foreground app.
        let quiet = CommandLine.arguments.contains("--quiet")
        DispatchQueue.main.async {
            MCPServer.shared.start(library: lib)
            NSApp.setActivationPolicy(.regular)
            if !quiet { NSApp.activate(ignoringOtherApps: true) }
        }
        // Wake the on-demand model stores: anything already downloaded loads
        // now (nothing downloads without the user asking).
        DispatchQueue.main.async {
            _ = DepthModelStore.shared
        }
        // Dock icon for unbundled dev runs; the .app bundle carries the .icns.
        DispatchQueue.main.async {
            if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                NSApp.applicationIconImage = image
            }
        }
        // Dev harness: `swift run Chiaro --open <folder> [--edit <name>] [--snapshot <png>]`
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
            let path = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let renderer = ImageRenderer(content: AppIconView())
                renderer.scale = 1
                if let cg = renderer.cgImage {
                    let rep = NSBitmapImageRep(cgImage: cg)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: path))
                }
                NSApp.terminate(nil)
            }
        }
        // --click <x> <y-from-top> [count]: post real mouse events through the
        // app's own window — hit-testing behaves exactly as a user click.
        if let i = args.firstIndex(of: "--click"), i + 2 < args.count {
            let x = Double(args[i + 1]) ?? 0
            let yTop = Double(args[i + 2]) ?? 0
            let count = i + 3 < args.count ? Int(args[i + 3]) ?? 1 : 1
            let clickLib = library
            func attemptClick(_ triesLeft: Int) {
                guard let window = NSApp.windows.first(where: { $0.contentView != nil }) else {
                    if triesLeft > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { attemptClick(triesLeft - 1) }
                    } else {
                        fputs("CLICK: no window\n", stderr)
                    }
                    return
                }
                let point = NSPoint(x: x, y: window.frame.height - yTop)
                let hit = window.contentView.flatMap { $0.hitTest($0.convert(point, from: nil)) }
                fputs("CLICK: isKey=\(window.isKeyWindow) active=\(NSApp.isActive) " +
                      "hit=\(hit.map { NSStringFromClass(type(of: $0)) } ?? "nil") " +
                      "firstMouse=\(hit?.acceptsFirstMouse(for: nil) ?? false)\n", stderr)
                for n in 0..<count {
                    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        if let event = NSEvent.mouseEvent(
                            with: type, location: point, modifierFlags: [],
                            timestamp: ProcessInfo.processInfo.systemUptime,
                            windowNumber: window.windowNumber, context: nil,
                            eventNumber: 0, clickCount: 1, pressure: 1
                        ) {
                            window.sendEvent(event)
                        }
                    }
                    fputs("CLICK \(n + 1) at \(point)\n", stderr)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    fputs("POST: editing=\(clickLib.editing?.name ?? "nil")\n", stderr)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { attemptClick(40) }
        }
        // --render-depth-scene <photo> <png>: snapshot the 3D focus scene.
        if let i = args.firstIndex(of: "--render-depth-scene"), i + 2 < args.count {
            let name = args[i + 1]
            let path = args[i + 2]
            let lib = library
            func attempt(_ triesLeft: Int) {
                _ = DepthModelStore.shared // kick the lazy load of the compiled model
                guard DepthEngine.shared.isReady,
                      let photo = lib.photos.first(where: { $0.name == name }) else {
                    if triesLeft > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { attempt(triesLeft - 1) }
                    } else {
                        fputs("DEPTH SCENE: not ready\n", stderr)
                        NSApp.terminate(nil)
                    }
                    return
                }
                let url = photo.url
                let focus = photo.edit.focusDepth
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let base = RawEngine.shared.preview(for: url),
                          let grid = DepthEngine.shared.pointGrid(for: url, image: base) else {
                        fputs("DEPTH SCENE: no grid\n", stderr)
                        DispatchQueue.main.async { NSApp.terminate(nil) }
                        return
                    }
                    DispatchQueue.main.async {
                        let scene = DepthScene.build(grid: grid, focusDepth: focus)
                        scene.rootNode.childNode(withName: "rig", recursively: false)?
                            .childNode(withName: "cloud", recursively: false)?
                            .morpher?.setWeight(1, forTargetAt: 0)
                        DepthScene.updatePlanes(in: scene, focusDepth: focus)
                        scene.background.contents = NSColor(Theme.ground)
                        let cameraNode = scene.rootNode.childNode(withName: "camera", recursively: false)
                        cameraNode?.position = SCNVector3(0.99, 0.68, 1.99) // rest orbit pose
                        let renderer = SCNRenderer(device: nil, options: nil)
                        renderer.scene = scene
                        renderer.pointOfView = cameraNode
                        let image = renderer.snapshot(
                            atTime: 0, with: CGSize(width: 1280, height: 860), antialiasingMode: .multisampling4X)
                        if let tiff = image.tiffRepresentation,
                           let rep = NSBitmapImageRep(data: tiff) {
                            try? rep.representation(using: .png, properties: [:])?
                                .write(to: URL(fileURLWithPath: path))
                        }
                        NSApp.terminate(nil)
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { attempt(20) }
        }
        // --auto-test <photo>: print the wand's computed values headless.
        if let i = args.firstIndex(of: "--auto-test"), i + 1 < args.count {
            let name = args[i + 1]
            let lib = library
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                guard let photo = lib.photos.first(where: { $0.name == name }) else {
                    fputs("AUTO: photo not found\n", stderr); NSApp.terminate(nil); return
                }
                let url = photo.url
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let base = RawEngine.shared.preview(for: url) else {
                        fputs("AUTO: no preview\n", stderr)
                        DispatchQueue.main.async { NSApp.terminate(nil) }
                        return
                    }
                    let mask = PortraitEngine.shared.mask(for: url, image: base)
                    if let edit = AutoEnhance.compute(base: base, subjectMask: mask, onto: EditState()) {
                        fputs(String(format: "AUTO: exp %.2f contrast %.0f hi %.0f sh %.0f wh %.0f bl %.0f temp %.0f tint %.0f vib %.0f\n",
                                     edit.exposure, edit.contrast, edit.highlights, edit.shadows,
                                     edit.whites, edit.blacks, edit.temp, edit.tint, edit.vibrance), stderr)
                        DispatchQueue.main.async {
                            photo.edit = edit
                            Sidecar.write(for: photo)
                        }
                    } else {
                        fputs("AUTO: failed\n", stderr)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
                }
            }
        }
        if args.contains("--download-depth") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                DepthModelStore.shared.downloadIfNeeded()
            }
        }
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
                        let (url, name) = await MainActor.run { () -> (URL, String) in
                            photo.edit = edit
                            return (photo.url, photo.name)
                        }
                        do {
                            var options = ExportOptions()
                            options.destination = FileManager.default.temporaryDirectory
                                .appendingPathComponent("ChiaroExportTest")
                            let outURL = try Exporter.export(url: url, edit: edit, name: name, options: options)
                            print("EXPORTED: \(outURL.path)")
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
        // Without this the window resizes past the content's minWidth and the
        // layout overflows instead of reflowing: the rail is a fixed 268 and the
        // toolbar cannot compress, so both edges get clipped.
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for updates…") { Updater.checkForUpdates() }
            }
            CommandGroup(replacing: .help) {
                Button("Chiaro on GitHub") { NSWorkspace.shared.open(Updater.repoPage) }
            }
            CommandGroup(replacing: .newItem) {
                Button("Open folder…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    if panel.runModal() == .OK, let url = panel.url { library.open(url) }
                }
                .keyboardShortcut("o")
                Button("Close library") { library.close() }
                    .keyboardShortcut("w")
                    .disabled(library.folderURL == nil)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo edit") { library.activeEditor?.undo() }
                    .keyboardShortcut("z")
                    .disabled(!(library.activeEditor?.canUndo ?? false))
                Button("Redo edit") { library.activeEditor?.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!(library.activeEditor?.canRedo ?? false))
            }
            CommandGroup(after: .sidebar) {
                Button("Fit to window") {
                    library.activeEditor?.canvasZoom = 1
                    library.activeEditor?.canvasPan = .zero
                }
                .keyboardShortcut("0")
                .disabled(library.activeEditor == nil)
                Button("Actual pixels") { library.activeEditor?.pixelZoomRequested = true }
                    .keyboardShortcut("1")
                    .disabled(library.activeEditor == nil)
            }
            CommandGroup(after: .pasteboard) {
                Button("Copy edits") { library.copyEdit() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Paste edits") { library.pasteEdit() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                    .disabled(library.copiedEdit == nil)
                Divider()
                Button("Export…") { exporting = true }
                    .keyboardShortcut("e")
                    .disabled(library.editing == nil && library.selection.isEmpty)
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
            // Library stays mounted beneath the editor so its scroll position
            // survives a round trip into a photo and back.
            // Wrapped so the library's own intrinsic width cannot raise the
            // window's minimum: a GeometryReader proposes a size to its child
            // instead of growing to fit it. Without this, anything added to the
            // library header overflows and clips BOTH views, since the library
            // stays mounted under the editor.
            GeometryReader { geo in
                LibraryView(library: library, onExport: { exporting = true })
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .opacity(library.editing == nil ? 1 : 0)
            .allowsHitTesting(library.editing == nil)
            if let editing = library.editing {
                EditView(library: library, photo: editing, onExport: { exporting = true })
            }
        }
        .containerBackground(.clear, for: .window)
        // The title strip is WINDOW-level chrome, drawn here rather than inside
        // any of the views above, so it's identical in position for the
        // library, the editor, and the start screen. It holds only
        // window-level state: agent status, trailing, above where it lands in
        // the editor's own rail. View controls (filters, view mode, zoom,
        // search) and the folder's name belong in their own view's header.
        .overlay(alignment: .top) {
            ZStack {
                HStack {
                    Spacer()
                    AgentStatusStrip(library: library)
                        .padding(.trailing, 16)
                }
            }
            .frame(height: 24) // the pill's own height, so both share one centre
            .padding(.top, 9) // centres the row on the traffic lights
            .ignoresSafeArea()
        }
        // A separate overlay, not stacked with the pill above: the intent
        // badge floats independently just beneath it and can't affect the
        // pill's geometry (see AgentIntentBadge).
        .overlay(alignment: .top) {
            HStack {
                Spacer()
                AgentIntentBadge(library: library)
                    .padding(.trailing, 16)
            }
            .padding(.top, 9 + 24 + 6)
            .ignoresSafeArea()
            .animation(.easeOut(duration: 0.2), value: library.agentIntent)
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
