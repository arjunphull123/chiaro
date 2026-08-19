import SwiftUI
import SceneKit

/// Spatial focus: the photo morphs into a depth-displaced point cloud, the
/// camera swings to a 3/4 view, and one gridded slice plane rises in — the
/// far edge of sharpness. Everything in front of it stays sharp; blur ramps
/// behind it. Drag to orbit (full 180°, plus overhead), grab a handle to
/// slide the plane, scroll to zoom. Exit reverses the choreography.
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
    static let planeHeight: CGFloat = 1.16
    static let restYaw: CGFloat = 0.46
    static let restPitch: CGFloat = 0.26

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

        let planeSize = CGSize(width: CGFloat(grid.aspect) * planeHeight, height: planeHeight)
        rig.addChildNode(slicePlane(name: "edge", size: planeSize, emphasis: 1))

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

    /// A slice of the scene: faint fill, screen-constant 1px lattice (line
    /// primitives — projection can't fatten them), and grab handles at all
    /// four edge midpoints. The returned container pivots at the plane's
    /// bottom edge so it grows in from the ground.
    private static func slicePlane(name: String, size: CGSize, emphasis: CGFloat) -> SCNNode {
        let container = SCNNode()
        container.name = name

        let sheet = SCNNode(geometry: SCNPlane(width: size.width, height: size.height))
        let sheetMaterial = SCNMaterial()
        sheetMaterial.diffuse.contents = amber.withAlphaComponent(0.06 * emphasis)
        sheetMaterial.lightingModel = .constant
        sheetMaterial.isDoubleSided = true
        sheetMaterial.writesToDepthBuffer = false // never occlude the cloud
        sheet.geometry?.materials = [sheetMaterial]
        sheet.renderingOrder = 100
        sheet.name = "\(name)-sheet"
        sheet.position = SCNVector3(0, size.height / 2, 0)
        container.addChildNode(sheet)

        let grid = SCNNode(geometry: latticeGeometry(size: size, emphasis: emphasis))
        grid.renderingOrder = 101
        grid.name = "\(name)-grid"
        sheet.addChildNode(grid)

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

        return container
    }

    /// Uniform lattice from line primitives — 1px on screen at any distance.
    private static func latticeGeometry(size: CGSize, emphasis: CGFloat) -> SCNGeometry {
        let rows = 7
        let cols = Int((size.width / size.height * 7).rounded())
        var vertices = [SCNVector3]()
        for i in 0...cols {
            let x = -size.width / 2 + size.width * CGFloat(i) / CGFloat(cols)
            vertices.append(SCNVector3(x, -size.height / 2, 0))
            vertices.append(SCNVector3(x, size.height / 2, 0))
        }
        for j in 0...rows {
            let y = -size.height / 2 + size.height * CGFloat(j) / CGFloat(rows)
            vertices.append(SCNVector3(-size.width / 2, y, 0))
            vertices.append(SCNVector3(size.width / 2, y, 0))
        }
        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(
            indices: Array(0..<Int32(vertices.count)), primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = amber.withAlphaComponent(0.55 * emphasis)
        material.lightingModel = .constant
        material.writesToDepthBuffer = false
        geometry.materials = [material]
        return geometry
    }

    static func updatePlanes(in scene: SCNScene, focusDepth: Double, focusRange: Double, hidden: Bool = false) {
        guard let rig = scene.rootNode.childNode(withName: "rig", recursively: false),
              let plane = rig.childNode(withName: "edge", recursively: false) else { return }
        let farEdge = (1 - focusDepth) - focusRange * 0.4
        plane.position = SCNVector3(0, -planeHeight / 2, CGFloat((Float(farEdge) - 0.5) * zSpan))
        plane.scale = SCNVector3(1, hidden ? 0.001 : 1, 1)
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
    // Passed explicitly (not read off the model inside updateNSView) so
    // SwiftUI reliably re-invokes updates when they change.
    var yaw: CGFloat
    var pitch: CGFloat
    var focusDepth: Double
    var focusRange: Double

    func makeNSView(context: Context) -> SCNView {
        let view = ScrollableSCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        // Trackpad two-finger scroll orbits; a mouse wheel zooms. Pinch zooms.
        view.onScroll = { [weak coordinator = context.coordinator] dx, dy, precise in
            if precise {
                coordinator?.orbit(byX: dx, y: dy)
            } else {
                coordinator?.zoom(by: dy * 8)
            }
        }
        let pan = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        view.addGestureRecognizer(pan)
        let magnify = NSMagnificationGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.magnify(_:)))
        view.addGestureRecognizer(magnify)
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
            DepthScene.updatePlanes(in: scene, focusDepth: focusDepth, focusRange: focusRange)
            if !coordinator.dragOwnsCamera { coordinator.applyOrbit() }
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

        private enum DragTarget { case plane, orbit }
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

        var dragOwnsCamera = false

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
                dragOwnsCamera = true
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
                dragTarget = names.contains(where: { $0.hasPrefix("edge-handle") }) ? .plane : .orbit
            case .changed:
                switch dragTarget {
                case .orbit:
                    // Grab-the-scene: it follows the cursor. AppKit views are
                    // y-up, so translation.y is positive on upward drags.
                    model.sceneYaw = (startYaw - translation.x / 220).clamped(to: -.pi / 2 ... .pi / 2)
                    model.scenePitch = (startPitch + translation.y / 220).clamped(to: -0.1 ... .pi / 2 - 0.06)
                    applyOrbit()
                case .plane:
                    dragPlane(translation: translation)
                case nil:
                    break
                }
            default:
                dragTarget = nil
                dragOwnsCamera = false
            }
        }

        /// Screen-space drag projected onto the depth axis, so the plane
        /// tracks the cursor from any camera angle. Moving the plane moves
        /// the whole sharp zone (focus); Range stays put.
        private func dragPlane(translation: NSPoint) {
            guard let view else { return }
            let a = view.projectPoint(SCNVector3(0, DepthScene.sceneLift, 0))
            let b = view.projectPoint(SCNVector3(0, DepthScene.sceneLift, 0.5))
            let axis = CGPoint(x: CGFloat(b.x - a.x), y: CGFloat(b.y - a.y))
            let lengthSquared = axis.x * axis.x + axis.y * axis.y
            guard lengthSquared > 1 else { return }
            let worldDz = 0.5 * Double((translation.x * axis.x + translation.y * axis.y) / lengthSquared)
            let focusDz = -worldDz / Double(DepthScene.zSpan) // +z = nearer = smaller focus value
            model.edit.focusDepth = (startFocus + focusDz).clamped(to: 0...1)
            refresh()
        }

        func zoom(by delta: CGFloat) {
            guard !isAnimating else { return }
            radius = (radius - delta / 160).clamped(to: 1.3...4.2)
            applyOrbit()
        }

        func orbit(byX dx: CGFloat, y dy: CGFloat) {
            guard !isAnimating else { return }
            model.sceneYaw = (model.sceneYaw - dx / 180).clamped(to: -.pi / 2 ... .pi / 2)
            model.scenePitch = (model.scenePitch + dy / 180).clamped(to: -0.1 ... .pi / 2 - 0.06)
            applyOrbit()
        }

        @objc func magnify(_ gesture: NSMagnificationGestureRecognizer) {
            guard !isAnimating else { return }
            radius = (radius / (1 + gesture.magnification)).clamped(to: 1.3...4.2)
            gesture.magnification = 0
            applyOrbit()
        }
    }
}

/// SCNView that forwards scroll instead of eating it — trackpad deltas are
/// precise (orbit), mouse-wheel ticks are not (zoom).
final class ScrollableSCNView: SCNView {
    var onScroll: ((CGFloat, CGFloat, Bool) -> Void)?
    override func scrollWheel(with event: NSEvent) {
        onScroll?(event.scrollingDeltaX, event.scrollingDeltaY, event.hasPreciseScrollingDeltas)
    }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
