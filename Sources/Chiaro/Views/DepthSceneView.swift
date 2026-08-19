import SwiftUI
import SceneKit

/// Spatial focus: the photo morphs into a depth-displaced point cloud, the
/// camera swings to a 3/4 view, and two gridded slice planes rise in to bound
/// the sharp zone. Drag to orbit (full 180°, plus overhead), grab a handle to
/// slide a plane along the depth axis, scroll to zoom. Exit reverses the
/// choreography back into the flat photo.
/// AppKit because SceneKit has no SwiftUI surface.
enum DepthSceneCommand: Equatable {
    case exit
    case front, left, right, top
}

enum DepthScene {
    /// World-space span of the disparity axis.
    static let zSpan: Float = 1.15
    static let amber = NSColor(red: 0.91, green: 0.64, blue: 0.24, alpha: 1)
    /// The rig sits slightly high in frame — the canvas bottom carries chrome.
    static let sceneLift: CGFloat = 0.09
    /// Where hidden slice planes wait before rising in.
    static let planeRestY: CGFloat = -1.9
    static let restYaw: CGFloat = 0.46
    static let restPitch: CGFloat = 0.26

    /// Tiling grid texture: one vertical + one horizontal line per tile, so
    /// the tiling closes a uniform lattice with no doubled seams.
    static let gridTexture: NSImage = {
        let size = 256
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.clear.set()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
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

        // The cloud morphs: base geometry is the flat photo (z = 0), the
        // morph target carries depth — weight 0 → 1 extrudes the image.
        let cloud = SCNNode(geometry: cloudGeometry(grid: grid, flat: true))
        let morpher = SCNMorpher()
        morpher.targets = [cloudGeometry(grid: grid, flat: false)]
        morpher.calculationMode = .normalized
        cloud.morpher = morpher
        cloud.name = "cloud"
        rig.addChildNode(cloud)

        let planeSize = CGSize(width: CGFloat(grid.aspect) * 1.16, height: 1.16)
        rig.addChildNode(slicePlane(name: "near", size: planeSize, emphasis: 1))
        rig.addChildNode(slicePlane(name: "far", size: planeSize, emphasis: 0.6))

        updatePlanes(in: scene, focusDepth: focusDepth, focusRange: focusRange, hidden: true)
        return scene
    }

    private static func cloudGeometry(grid: DepthEngine.PointGrid, flat: Bool) -> SCNGeometry {
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
                    flat ? 0 : CGFloat((d - 0.5) * zSpan)
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
        return geometry
    }

    /// A slice of the scene: faint fill, uniform lattice, hairline border,
    /// and grab handles at all four edge midpoints.
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
        gridMaterial.transparency = 0.6
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

        // Grab handles at all four edge midpoints, each with an oversize
        // invisible hit target so they're easy to catch mid-orbit.
        let offsets: [(CGFloat, CGFloat)] = [
            (size.width / 2 + 0.075, 0), (-size.width / 2 - 0.075, 0),
            (0, size.height / 2 + 0.075), (0, -size.height / 2 - 0.075),
        ]
        for (x, y) in offsets {
            let handle = SCNNode(geometry: SCNSphere(radius: 0.036))
            let handleMaterial = SCNMaterial()
            handleMaterial.diffuse.contents = amber.withAlphaComponent(0.95 * emphasis)
            handleMaterial.lightingModel = .constant
            handle.geometry?.materials = [handleMaterial]
            handle.position = SCNVector3(x, y, 0)
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
        }

        return sheet
    }

    static func updatePlanes(in scene: SCNScene, focusDepth: Double, focusRange: Double, hidden: Bool = false) {
        guard let rig = scene.rootNode.childNode(withName: "rig", recursively: false) else { return }
        let target = 1 - focusDepth
        let half = focusRange * 0.4
        let nearZ = CGFloat((Float(target + half) - 0.5) * zSpan)
        let farZ = CGFloat((Float(target - half) - 0.5) * zSpan)
        let y = hidden ? planeRestY : 0
        rig.childNode(withName: "near", recursively: false)?.position = SCNVector3(0, y, nearZ)
        rig.childNode(withName: "far", recursively: false)?.position = SCNVector3(0, y, farZ)
    }

    static func cameraPosition(yaw: CGFloat, pitch: CGFloat, radius: CGFloat) -> SCNVector3 {
        SCNVector3(
            radius * sin(yaw) * cos(pitch),
            radius * sin(pitch) + sceneLift,
            radius * cos(yaw) * cos(pitch)
        )
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
            coordinator?.zoom(by: delta)
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
        if let scene = view.scene, !coordinator.isAnimating {
            DepthScene.updatePlanes(in: scene, focusDepth: model.edit.focusDepth, focusRange: model.edit.focusRange)
            coordinator.applyOrbit()
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
        /// Choreography guard: while entering/exiting/snapping, gestures and
        /// SwiftUI-driven position sync stay out of the camera's way.
        var isAnimating = false

        private var radius: CGFloat = 2.3

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

        private var cloudNode: SCNNode? {
            view?.scene?.rootNode.childNode(withName: "rig", recursively: false)?
                .childNode(withName: "cloud", recursively: false)
        }

        /// Head-on distance where the 1-unit-tall cloud fills exactly the same
        /// screen height as the flat photo (default 60° vertical field of view).
        private var headOnDistance: CGFloat {
            1 / (2 * tan(30 * .pi / 180) * max(0.2, fitFraction))
        }

        func applyOrbit() {
            guard !isAnimating else { return }
            cameraNode?.position = DepthScene.cameraPosition(
                yaw: model.sceneYaw, pitch: model.scenePitch, radius: radius)
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

        /// The reveal: flat dots head-on (reads as the photo), depth extrudes,
        /// the camera swings out, then the slice planes rise from below.
        private func animateIn() {
            guard let cameraNode, let cloudNode else { return }
            isAnimating = true
            model.sceneYaw = DepthScene.restYaw
            model.scenePitch = DepthScene.restPitch
            cameraNode.position = DepthScene.cameraPosition(yaw: 0, pitch: 0.005, radius: headOnDistance)

            // 1. Extrude the dots into depth.
            let morph = CABasicAnimation(keyPath: "morpher.weights[0]")
            morph.fromValue = 0
            morph.toValue = 1
            morph.duration = 0.7
            morph.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            cloudNode.addAnimation(morph, forKey: "morph")
            cloudNode.morpher?.setWeight(1, forTargetAt: 0)

            // 2. Swing to the 3/4 view.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                guard let self, let cameraNode = self.cameraNode else { return }
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.9
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                SCNTransaction.completionBlock = { [weak self] in
                    Task { @MainActor in self?.raisePlanes() }
                }
                cameraNode.position = DepthScene.cameraPosition(
                    yaw: self.model.sceneYaw, pitch: self.model.scenePitch, radius: self.radius)
                SCNTransaction.commit()
            }
        }

        /// 3. The slice planes rise from below.
        private func raisePlanes() {
            guard let scene = view?.scene else { isAnimating = false; return }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.45
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
            SCNTransaction.completionBlock = { [weak self] in
                Task { @MainActor in self?.isAnimating = false }
            }
            DepthScene.updatePlanes(
                in: scene, focusDepth: model.edit.focusDepth, focusRange: model.edit.focusRange)
            SCNTransaction.commit()
        }

        /// Exit reverses the choreography: planes drop, the camera returns
        /// head-on while the dots flatten, then the photo takes over.
        private func animateOut() {
            guard let scene = view?.scene, cameraNode != nil, let cloudNode else {
                model.depthSceneVisible = false
                return
            }
            isAnimating = true
            let model = model

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.3
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeIn)
            SCNTransaction.completionBlock = { [weak self] in
                Task { @MainActor in
                    guard let self, let cameraNode = self.cameraNode else {
                        model.depthSceneVisible = false
                        return
                    }
                    let flatten = CABasicAnimation(keyPath: "morpher.weights[0]")
                    flatten.fromValue = 1
                    flatten.toValue = 0
                    flatten.duration = 0.7
                    flatten.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    cloudNode.addAnimation(flatten, forKey: "morph")
                    cloudNode.morpher?.setWeight(0, forTargetAt: 0)

                    SCNTransaction.begin()
                    SCNTransaction.animationDuration = 0.7
                    SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    SCNTransaction.completionBlock = {
                        Task { @MainActor in
                            model.depthSceneVisible = false
                            self.isAnimating = false
                        }
                    }
                    cameraNode.position = DepthScene.cameraPosition(
                        yaw: 0, pitch: 0.005, radius: self.headOnDistance)
                    SCNTransaction.commit()
                }
            }
            DepthScene.updatePlanes(
                in: scene, focusDepth: model.edit.focusDepth, focusRange: model.edit.focusRange, hidden: true)
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
            model.sceneYaw = newYaw
            model.scenePitch = newPitch
            isAnimating = true
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.55
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            SCNTransaction.completionBlock = { [weak self] in
                Task { @MainActor in self?.isAnimating = false }
            }
            cameraNode.position = DepthScene.cameraPosition(yaw: newYaw, pitch: newPitch, radius: radius)
            SCNTransaction.commit()
        }

        private func refresh() {
            guard let scene = view?.scene else { return }
            DepthScene.updatePlanes(in: scene, focusDepth: model.edit.focusDepth, focusRange: model.edit.focusRange)
        }

        @objc func pan(_ gesture: NSPanGestureRecognizer) {
            guard let view, !isAnimating else { return }
            let translation = gesture.translation(in: view)
            switch gesture.state {
            case .began:
                startFocus = model.edit.focusDepth
                startRange = model.edit.focusRange
                startYaw = model.sceneYaw
                startPitch = model.scenePitch
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
                    // Grab-the-scene: it follows the cursor. AppKit views are
                    // y-up, so translation.y is positive on upward drags.
                    model.sceneYaw = (startYaw - translation.x / 220).clamped(to: -.pi / 2 ... .pi / 2)
                    model.scenePitch = (startPitch + translation.y / 220).clamped(to: -0.1 ... .pi / 2 - 0.06)
                    applyOrbit()
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
            let worldDz = 0.5 * Double((translation.x * axis.x + translation.y * axis.y) / lengthSquared)
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

        func zoom(by delta: CGFloat) {
            guard !isAnimating else { return }
            radius = (radius - delta / 160).clamped(to: 1.3...4.2)
            applyOrbit()
        }
    }
}

/// SCNView that forwards scroll to zoom instead of eating it.
final class ScrollableSCNView: SCNView {
    var onScroll: ((CGFloat) -> Void)?
    override func scrollWheel(with event: NSEvent) {
        onScroll?(event.scrollingDeltaY)
    }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
