import SwiftUI
import SceneKit

/// Spatial focus: the photo as a depth-displaced point cloud, bounded by two
/// gridded slice planes — the near and far edges of the sharp zone. Drag
/// anywhere to orbit (a full 180°, plus overhead), grab a plane's handle to
/// slide it along the depth axis, scroll for symmetric range. Enter and exit
/// animate through a head-on camera so the cloud dissolves from and back into
/// the flat photo. AppKit because SceneKit has no SwiftUI surface.
enum DepthSceneCommand: Equatable {
    case exit
    case front, left, right, top
}

enum DepthScene {
    /// World-space span of the disparity axis.
    static let zSpan: Float = 1.15
    static let amber = NSColor(red: 0.91, green: 0.64, blue: 0.24, alpha: 1)
    /// The whole rig sits slightly high in frame — the canvas bottom carries chrome.
    static let sceneLift: CGFloat = 0.09

    /// Tiling grid texture: one cell per tile, so the tiling makes the lattice.
    static let gridTexture: NSImage = {
        let size = 256
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.clear.set()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        // One vertical + one horizontal line per tile — tiling closes the
        // lattice without doubled seam lines.
        amber.withAlphaComponent(0.4).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: NSPoint(x: 0.5, y: 0))
        path.line(to: NSPoint(x: 0.5, y: CGFloat(size)))
        path.move(to: NSPoint(x: 0, y: 0.5))
        path.line(to: NSPoint(x: CGFloat(size), y: 0.5))
        path.stroke()
        image.unlockFocus()
        return image
    }()

    static func build(grid: DepthEngine.PointGrid, focusDepth: Double, focusRange: Double) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear

        let camera = SCNCamera()
        camera.zNear = 0.05
        camera.zFar = 20
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.name = "camera"
        scene.rootNode.addChildNode(cameraNode)

        let rig = SCNNode()
        rig.name = "rig"
        rig.position = SCNVector3(0, sceneLift, 0)
        scene.rootNode.addChildNode(rig)

        let constraint = SCNLookAtConstraint(target: rig)
        constraint.isGimbalLockEnabled = true
        cameraNode.constraints = [constraint]

        let count = grid.width * grid.height
        var positions = [SCNVector3]()
        positions.reserveCapacity(count)
        var colors = [Float]()
        colors.reserveCapacity(count * 3)
        for row in 0..<grid.height {
            for col in 0..<grid.width {
                let i = row * grid.width + col
                let u = Float(col) / Float(grid.width - 1)
                let v = Float(row) / Float(grid.height - 1)
                let d = grid.disparity[i]
                positions.append(SCNVector3(
                    CGFloat((u - 0.5) * grid.aspect),
                    CGFloat(0.5 - v),
                    CGFloat((d - 0.5) * zSpan)
                ))
                colors.append(Float(grid.colors[i * 4]) / 255)
                colors.append(Float(grid.colors[i * 4 + 1]) / 255)
                colors.append(Float(grid.colors[i * 4 + 2]) / 255)
            }
        }
        let vertexSource = SCNGeometrySource(vertices: positions)
        let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorSource = SCNGeometrySource(
            data: colorData, semantic: .color, vectorCount: count,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<Float>.size * 3
        )
        let indices = Array(0..<Int32(count))
        let element = SCNGeometryElement(indices: indices, primitiveType: .point)
        element.pointSize = 3.5
        element.minimumPointScreenSpaceRadius = 1
        element.maximumPointScreenSpaceRadius = 7
        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        geometry.materials = [material]
        let cloud = SCNNode(geometry: geometry)
        cloud.name = "cloud"
        rig.addChildNode(cloud)

        let planeSize = CGSize(width: CGFloat(grid.aspect) * 1.16, height: 1.16)
        rig.addChildNode(slicePlane(name: "near", size: planeSize, emphasis: 1))
        rig.addChildNode(slicePlane(name: "far", size: planeSize, emphasis: 0.6))

        updatePlanes(in: scene, focusDepth: focusDepth, focusRange: focusRange)
        return scene
    }

    /// A slice of the scene: faint fill, fine lattice, hairline border, and a
    /// grab handle on the right edge for dragging along the depth axis.
    private static func slicePlane(name: String, size: CGSize, emphasis: CGFloat) -> SCNNode {
        let sheet = SCNNode(geometry: SCNPlane(width: size.width, height: size.height))
        let sheetMaterial = SCNMaterial()
        sheetMaterial.diffuse.contents = amber.withAlphaComponent(0.06 * emphasis)
        sheetMaterial.lightingModel = .constant
        sheetMaterial.isDoubleSided = true
        sheetMaterial.writesToDepthBuffer = false // never occlude the cloud
        sheet.geometry?.materials = [sheetMaterial]
        sheet.renderingOrder = 100
        sheet.name = name

        let grid = SCNNode(geometry: SCNPlane(width: size.width, height: size.height))
        let gridMaterial = SCNMaterial()
        gridMaterial.diffuse.contents = gridTexture
        gridMaterial.diffuse.wrapS = .repeat
        gridMaterial.diffuse.wrapT = .repeat
        gridMaterial.diffuse.contentsTransform = SCNMatrix4MakeScale(
            (size.width / size.height * 7).rounded(), 7, 1)
        gridMaterial.transparency = emphasis
        gridMaterial.lightingModel = .constant
        gridMaterial.isDoubleSided = true
        gridMaterial.writesToDepthBuffer = false
        grid.geometry?.materials = [gridMaterial]
        grid.renderingOrder = 100
        grid.name = "\(name)-grid"
        sheet.addChildNode(grid)

        // Hairline border from four bars (a wireframe box would draw its
        // triangulation diagonals).
        let bar: CGFloat = 0.004
        let edges: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (size.width + bar, bar, 0, size.height / 2),
            (size.width + bar, bar, 0, -size.height / 2),
            (bar, size.height + bar, -size.width / 2, 0),
            (bar, size.height + bar, size.width / 2, 0),
        ]
        for (w, h, x, y) in edges {
            let edge = SCNNode(geometry: SCNBox(width: w, height: h, length: bar, chamferRadius: 0))
            let material = SCNMaterial()
            material.diffuse.contents = amber.withAlphaComponent(0.8 * emphasis)
            material.lightingModel = .constant
            material.writesToDepthBuffer = false
            edge.geometry?.materials = [material]
            edge.renderingOrder = 101
            edge.name = "\(name)-frame"
            sheet.addChildNode(edge)
        }

        // The grab handle: solid knob outside the right edge, plus an oversize
        // invisible hit target so it's easy to catch mid-orbit.
        let handle = SCNNode(geometry: SCNSphere(radius: 0.038))
        let handleMaterial = SCNMaterial()
        handleMaterial.diffuse.contents = amber.withAlphaComponent(0.95 * emphasis)
        handleMaterial.lightingModel = .constant
        handle.geometry?.materials = [handleMaterial]
        handle.position = SCNVector3(size.width / 2 + 0.075, 0, 0)
        handle.renderingOrder = 102
        handle.name = "\(name)-handle"
        let grab = SCNNode(geometry: SCNSphere(radius: 0.11))
        let grabMaterial = SCNMaterial()
        grabMaterial.colorBufferWriteMask = [] // hit-testable, never drawn
        grabMaterial.writesToDepthBuffer = false
        grab.geometry?.materials = [grabMaterial]
        grab.name = "\(name)-handle-grab"
        handle.addChildNode(grab)
        sheet.addChildNode(handle)

        return sheet
    }

    static func updatePlanes(in scene: SCNScene, focusDepth: Double, focusRange: Double) {
        guard let rig = scene.rootNode.childNode(withName: "rig", recursively: false) else { return }
        let target = 1 - focusDepth
        let half = focusRange * 0.4
        let nearZ = CGFloat((Float(target + half) - 0.5) * zSpan)
        let farZ = CGFloat((Float(target - half) - 0.5) * zSpan)
        rig.childNode(withName: "near", recursively: false)?.position = SCNVector3(0, 0, nearZ)
        rig.childNode(withName: "far", recursively: false)?.position = SCNVector3(0, 0, farZ)
    }
}

struct DepthSceneView: NSViewRepresentable {
    @Bindable var model: EditViewModel
    /// The flat photo's height as a fraction of the canvas — the head-on
    /// camera matches it so enter/exit reads as the photo itself folding
    /// into space.
    var fitFraction: CGFloat

    func makeNSView(context: Context) -> SCNView {
        let view = ScrollableSCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.onScroll = { [weak coordinator = context.coordinator] delta in
            coordinator?.adjustRange(by: delta)
        }
        let pan = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        view.addGestureRecognizer(pan)
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.model = model
        coordinator.fitFraction = fitFraction
        if coordinator.builtURL != model.photo.url {
            coordinator.builtURL = model.photo.url
            coordinator.rebuildCloud()
        }
        if let scene = view.scene {
            DepthScene.updatePlanes(in: scene, focusDepth: model.edit.focusDepth, focusRange: model.edit.focusRange)
        }
        if let command = model.depthSceneCommand {
            DispatchQueue.main.async { [weak model] in
                if model?.depthSceneCommand == command { model?.depthSceneCommand = nil }
            }
            coordinator.handle(command)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    @MainActor
    final class Coordinator: NSObject {
        var model: EditViewModel
        weak var view: SCNView?
        var builtURL: URL?
        var fitFraction: CGFloat = 0.85

        /// Orbit state (spherical around the rig).
        private var yaw: CGFloat = 0
        private var pitch: CGFloat = 0
        private let radius: CGFloat = 2.3
        private static let restYaw: CGFloat = 0.46
        private static let restPitch: CGFloat = 0.26

        private enum DragTarget { case near, far, orbit }
        private var dragTarget: DragTarget?
        private var startFocus = 0.0
        private var startRange = 0.0
        private var startYaw: CGFloat = 0
        private var startPitch: CGFloat = 0

        init(model: EditViewModel) {
            self.model = model
        }

        private var cameraNode: SCNNode? {
            view?.scene?.rootNode.childNode(withName: "camera", recursively: false)
        }

        /// Head-on distance where the 1-unit-tall cloud fills exactly the same
        /// screen height as the flat photo (default 60° vertical field of view).
        private var headOnDistance: CGFloat {
            1 / (2 * tan(30 * .pi / 180) * max(0.2, fitFraction))
        }

        private func cameraPosition(yaw: CGFloat, pitch: CGFloat, radius: CGFloat) -> SCNVector3 {
            SCNVector3(
                radius * sin(yaw) * cos(pitch),
                radius * sin(pitch) + DepthScene.sceneLift,
                radius * cos(yaw) * cos(pitch)
            )
        }

        func rebuildCloud() {
            let model = model
            Task {
                guard let grid = await model.depthGrid() else { return }
                let scene = DepthScene.build(
                    grid: grid, focusDepth: model.edit.focusDepth, focusRange: model.edit.focusRange)
                self.view?.scene = scene
                self.animateIn()
            }
        }

        /// Head-on (the cloud reads as the flat photo), then swing to 3/4.
        private func animateIn() {
            guard let cameraNode else { return }
            yaw = Self.restYaw
            pitch = Self.restPitch
            cameraNode.position = cameraPosition(yaw: 0, pitch: 0.005, radius: headOnDistance)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 1.0
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            cameraNode.position = cameraPosition(yaw: yaw, pitch: pitch, radius: radius)
            SCNTransaction.commit()
        }

        /// Swing back to head-on, then hand the canvas back to the flat photo.
        private func animateOut() {
            guard let cameraNode else {
                model.depthSceneVisible = false
                return
            }
            let model = model
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.8
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            SCNTransaction.completionBlock = {
                Task { @MainActor in model.depthSceneVisible = false }
            }
            cameraNode.position = cameraPosition(yaw: 0, pitch: 0.005, radius: headOnDistance)
            SCNTransaction.commit()
        }

        func handle(_ command: DepthSceneCommand) {
            switch command {
            case .exit: animateOut()
            case .front: snap(yaw: 0, pitch: 0.005)
            case .left: snap(yaw: -.pi / 2, pitch: 0.005)
            case .right: snap(yaw: .pi / 2, pitch: 0.005)
            case .top: snap(yaw: 0.001, pitch: .pi / 2 - 0.06)
            }
        }

        private func snap(yaw newYaw: CGFloat, pitch newPitch: CGFloat) {
            guard let cameraNode else { return }
            yaw = newYaw
            pitch = newPitch
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.55
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            cameraNode.position = cameraPosition(yaw: yaw, pitch: pitch, radius: radius)
            SCNTransaction.commit()
        }

        private func refresh() {
            guard let scene = view?.scene else { return }
            DepthScene.updatePlanes(in: scene, focusDepth: model.edit.focusDepth, focusRange: model.edit.focusRange)
        }

        @objc func pan(_ gesture: NSPanGestureRecognizer) {
            guard let view else { return }
            let translation = gesture.translation(in: view)
            switch gesture.state {
            case .began:
                startFocus = model.edit.focusDepth
                startRange = model.edit.focusRange
                startYaw = yaw
                startPitch = pitch
                // Only the handles grab a plane; everything else orbits.
                let hits = view.hitTest(gesture.location(in: view), options: [
                    .searchMode: SCNHitTestSearchMode.all.rawValue,
                    .ignoreHiddenNodes: false,
                ])
                let names = hits.compactMap(\.node.name)
                if names.contains(where: { $0.hasPrefix("near-handle") }) { dragTarget = .near }
                else if names.contains(where: { $0.hasPrefix("far-handle") }) { dragTarget = .far }
                else { dragTarget = .orbit }
            case .changed:
                switch dragTarget {
                case .orbit:
                    yaw = (startYaw + translation.x / 220).clamped(to: -.pi / 2 ... .pi / 2)
                    pitch = (startPitch - translation.y / 220).clamped(to: -0.1 ... .pi / 2 - 0.06)
                    cameraNode?.position = cameraPosition(yaw: yaw, pitch: pitch, radius: radius)
                case .near, .far:
                    dragPlane(near: dragTarget == .near, translation: translation)
                case nil:
                    break
                }
            default:
                dragTarget = nil
            }
        }

        /// Screen-space drag projected onto the depth axis, so plane dragging
        /// tracks the cursor from any camera angle.
        private func dragPlane(near: Bool, translation: NSPoint) {
            guard let view else { return }
            let a = view.projectPoint(SCNVector3(0, DepthScene.sceneLift, 0))
            let b = view.projectPoint(SCNVector3(0, DepthScene.sceneLift, 0.5))
            let axis = CGPoint(x: CGFloat(b.x - a.x), y: CGFloat(b.y - a.y))
            let lengthSquared = axis.x * axis.x + axis.y * axis.y
            guard lengthSquared > 1 else { return }
            // Gesture translation is top-left origin; projectPoint is bottom-left.
            let drag = CGPoint(x: translation.x, y: -translation.y)
            let worldDz = 0.5 * Double((drag.x * axis.x + drag.y * axis.y) / lengthSquared)
            let focusDz = -worldDz / Double(DepthScene.zSpan) // +z = nearer = smaller focus value

            let startHalf = startRange * 0.4
            let nearEdge = startFocus - startHalf
            let farEdge = startFocus + startHalf
            let newNear = near ? (nearEdge + focusDz).clamped(to: -0.2...1.2) : nearEdge
            let newFar = near ? farEdge : (farEdge + focusDz).clamped(to: -0.2...1.2)
            let lo = min(newNear, newFar), hi = max(newNear, newFar)
            model.edit.focusDepth = ((lo + hi) / 2).clamped(to: 0...1)
            model.edit.focusRange = ((hi - lo) / 2 / 0.4).clamped(to: 0...1)
            refresh()
        }

        func adjustRange(by delta: CGFloat) {
            model.edit.focusRange = (model.edit.focusRange + Double(delta) / 120).clamped(to: 0...1)
            refresh()
        }
    }
}

/// SCNView that forwards scroll to the Range control instead of eating it.
final class ScrollableSCNView: SCNView {
    var onScroll: ((CGFloat) -> Void)?
    override func scrollWheel(with event: NSEvent) {
        onScroll?(event.scrollingDeltaY)
    }
}
