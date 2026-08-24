import SwiftUI
import SceneKit

/// `swift run Chiaro --open <folder> [--edit <name>] [--snapshot <png>]` and friends;
/// see CLAUDE.md for the full flag list. Never runs in a shipped build unless invoked.
enum DevHarness {
    @MainActor
    static func run(library: Library, args: [String]) {
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
                    if let edit = AutoEnhance.compute(base: base, subjectMask: mask, isRAW: photo.isRAW, onto: EditState()) {
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
                            fputs("EXPORTED: \(outURL.path)\n", stderr)
                        } catch {
                            fputs("EXPORT FAILED: \(error)\n", stderr)
                        }
                        await NSApp.terminate(nil)
                    }
                }
            }
        }
    }
}
