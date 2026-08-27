import SwiftUI
import TipKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // One library, one window: tabbing only adds a dozen dead menu items.
        NSWindow.allowsAutomaticWindowTabbing = false
        Updater.checkInBackground()
    }

    // Closing the window quits, as a single-window app should, unless an agent
    // is mid-session: then the app and its MCP server stay up so the agent's
    // work continues, and quit on their own once the agent has gone quiet
    // (ADR 0017). "Quiet" is AgentStatus.isActive's window, checked each minute.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        MainActor.assumeIsolated {
            guard AgentStatus.shared.isActive() else { return true }
            headlessTimer?.invalidate()
            headlessTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { timer in
                MainActor.assumeIsolated {
                    if NSApp.windows.contains(where: \.isVisible) { timer.invalidate(); return }
                    if !AgentStatus.shared.isActive() { NSApp.terminate(nil) }
                }
            }
            return false
        }
    }
    private var headlessTimer: Timer?

    // Dock click or `open -a` with the window closed brings it back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            NSApp.windows.first { $0.contentView != nil }?.makeKeyAndOrderFront(nil)
        }
        return true
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
            if let image = NSImage(contentsOf: Resources.url("AppIcon.png")) {
                NSApp.applicationIconImage = image
            }
        }
        // Dev harness: `swift run Chiaro --open <folder> [--edit <name>] [--snapshot <png>]`
        DevHarness.run(library: library, args: CommandLine.arguments)
    }

    var body: some Scene {
        // One window, always: the library and editor are one shared state,
        // and a second view over them is incoherent (the Lightroom posture).
        // Window (not WindowGroup) also removes File > New Window.
        Window("Chiaro", id: "main") {
            RootView(library: library, exporting: $exporting)
                .preferredColorScheme(.dark)
                // The start screen hugs its content (LibraryView resizes the
                // window to it); the editor needs the taller floor.
                // Start screens are fixed-size windows hugged by LibraryView (the
                // welcome card, or the 900-wide returning page at its content's
                // height); the editor's 1080 floor applies once a folder opens.
                .frame(
                    minWidth: library.folderURL == nil ? (Library.hasRecentEdits ? 900 : 640) : 1080,
                    minHeight: library.folderURL == nil ? 480 : 700
                )
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
                Button("Report a bug…") {
                    NSWorkspace.shared.open(Updater.repoPage.appending(path: "issues/new/choose"))
                }
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
            // The welcome card sits on the share card's Caravaggio, run under
            // the title bar so the window is one surface. First run only.
            if library.welcome, library.folderURL == nil,
               let painting = NSImage(contentsOf: Resources.url("Welcome.jpg")) {
                Image(nsImage: painting)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
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
                    // The welcome card carries its own Connect button.
                    if !(library.welcome && library.folderURL == nil) {
                        AgentStatusStrip(library: library)
                            .padding(.trailing, 16)
                    }
                }
            }
            // No fixed height: the card grows downward when it carries the
            // agent's intent. Its collapsed height is 24, so the traffic-light
            // alignment below is unchanged.
            .padding(.top, 9) // centres the collapsed row on the traffic lights
            .ignoresSafeArea()
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
