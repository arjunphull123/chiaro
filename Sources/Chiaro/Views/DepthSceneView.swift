import SwiftUI
import SceneKit

/// Spatial focus: the photo as a depth-displaced point cloud seen from an
/// angle, bounded by two draggable planes — near and far edges of the sharp
/// zone. Drag a plane to move that boundary, drag between them to move the
/// whole zone, drag sideways to orbit, scroll for fine range.
/// AppKit here because SceneKit has no SwiftUI surface.
enum DepthScene {
    /// World-space span of the disparity axis.
    static let zSpan: Float = 1.15
    static let amber = NSColor(red: 0.91, green: 0.64, blue: 0.24, alpha: 1)

    /// Tiling grid texture so the boundary planes read as slices of the scene.
    static let gridTexture: NSImage = {
        let size = 256
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.clear.set()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        amber.withAlphaComponent(0.42).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 2
        for i in stride(from: 0, through: size, by: 32) {
            path.move(to: NSPoint(x: CGFloat(i), y: 0))
            path.line(to: NSPoint(x: CGFloat(i), y: CGFloat(size)))
            path.move(to: NSPoint(x: 0, y: CGFloat(i)))
            path.line(to: NSPoint(x: CGFloat(size), y: CGFloat(i)))
        }
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
        cameraNode.position = SCNVector3(0.95, 0.6, 1.95)
        cameraNode.name = "camera"
        scene.rootNode.addChildNode(cameraNode)

        let rig = SCNNode()
        rig.name = "rig"
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

        let planeSize = CGSize(width: CGFloat(grid.aspect) * 1.18, height: 1.18)
        rig.addChildNode(boundaryPlane(name: "near", size: planeSize, emphasis: 1))
        rig.addChildNode(boundaryPlane(name: "far", size: planeSize, emphasis: 0.55))

        updatePlanes(in: scene, focusDepth: focusDepth, focusRange: focusRange)
        return scene
    }

    /// A sharp-zone boundary: translucent amber sheet with a solid frame so
    /// it reads as a draggable object, not a tint.
    private static func boundaryPlane(name: String, size: CGSize, emphasis: CGFloat) -> SCNNode {
        let sheet = SCNNode(geometry: SCNPlane(width: size.width, height: size.height))
        let sheetMaterial = SCNMaterial()
        sheetMaterial.diffuse.contents = amber.withAlphaComponent(0.07 * emphasis)
        sheetMaterial.lightingModel = .constant
        sheetMaterial.isDoubleSided = true
        sheetMaterial.writesToDepthBuffer = false // never occlude the cloud
        sheet.geometry?.materials = [sheetMaterial]
        sheet.renderingOrder = 100
        sheet.name = name

        let grid = SCNNode(geometry: SCNPlane(width: size.width, height: size.height))
        let gridMaterial = SCNMaterial()
        gridMaterial.diffuse.contents = gridTexture
        gridMaterial.transparency = emphasis
        gridMaterial.diffuse.wrapS = .repeat
        gridMaterial.diffuse.wrapT = .repeat
        gridMaterial.diffuse.contentsTransform = SCNMatrix4MakeScale(
            size.width / size.height * 1.4, 1.4, 1)
        gridMaterial.lightingModel = .constant
        gridMaterial.isDoubleSided = true
        gridMaterial.writesToDepthBuffer = false
        grid.geometry?.materials = [gridMaterial]
        grid.renderingOrder = 100
        grid.name = "\(name)-grid"
        sheet.addChildNode(grid)

        // Clean border from four bars (a wireframe box would draw its
        // triangulation diagonals).
        let bar: CGFloat = 0.009
        let edges: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (size.width + bar, bar, 0, size.height / 2),  // top
            (size.width + bar, bar, 0, -size.height / 2), // bottom
            (bar, size.height + bar, -size.width / 2, 0), // left
            (bar, size.height + bar, size.width / 2, 0),  // right
        ]
        for (w, h, x, y) in edges {
            let edge = SCNNode(geometry: SCNBox(width: w, height: h, length: bar, chamferRadius: 0))
            let material = SCNMaterial()
            material.diffuse.contents = amber.withAlphaComponent(0.9 * emphasis)
            material.lightingModel = .constant
            material.writesToDepthBuffer = false
            edge.geometry?.materials = [material]
            edge.renderingOrder = 101
            edge.position = SCNVector3(x, y, 0)
            edge.name = "\(name)-frame"
            sheet.addChildNode(edge)
        }
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
        if coordinator.builtURL != model.photo.url {
            coordinator.builtURL = model.photo.url
            coordinator.rebuildCloud()
        }
        if let scene = view.scene {
            DepthScene.updatePlanes(in: scene, focusDepth: model.edit.focusDepth, focusRange: model.edit.focusRange)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    @MainActor
    final class Coordinator: NSObject {
        var model: EditViewModel
        weak var view: SCNView?
        var builtURL: URL?

        private enum DragTarget { case near, far, zone, orbit }
        private var dragTarget: DragTarget?
        private var startFocus = 0.0
        private var startRange = 0.0
        private var startYaw: CGFloat = 0

        init(model: EditViewModel) {
            self.model = model
        }

        func rebuildCloud() {
            let model = model
            Task {
                guard let grid = await model.depthGrid() else { return }
                let scene = DepthScene.build(
                    grid: grid, focusDepth: model.edit.focusDepth, focusRange: model.edit.focusRange)
                self.view?.scene = scene
                // Enter head-on — the cloud reads as the flat photo — then
                // swing out to the 3/4 view so the depth reveals itself.
                if let camera = scene.rootNode.childNode(withName: "camera", recursively: false) {
                    let destination = camera.position
                    camera.position = SCNVector3(0, 0.02, 2.45)
                    SCNTransaction.begin()
                    SCNTransaction.animationDuration = 1.1
                    SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    camera.position = destination
                    SCNTransaction.commit()
                }
            }
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
                startYaw = view.scene?.rootNode.childNode(withName: "rig", recursively: false)?.eulerAngles.y ?? 0
                // What's under the cursor decides the drag: a boundary plane
                // moves that edge; anything else moves the zone or orbits.
                let hits = view.hitTest(gesture.location(in: view), options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
                let names = hits.compactMap { $0.node.name ?? $0.node.parent?.name }
                if names.contains(where: { $0.hasPrefix("near") }) { dragTarget = .near }
                else if names.contains(where: { $0.hasPrefix("far") }) { dragTarget = .far }
                else { dragTarget = .zone }
            case .changed:
                guard let target = dragTarget else { return }
                if target == .zone, abs(translation.x) > abs(translation.y) * 1.6 {
                    dragTarget = .orbit
                }
                // Drag up pushes toward far: screen-up = -y translation.
                let dz = -Double(translation.y) / 260
                switch dragTarget {
                case .zone:
                    model.edit.focusDepth = (startFocus + dz).clamped(to: 0...1)
                case .near:
                    // Near boundary at focus − half·range: pulling it moves the
                    // near edge; focus and range both follow so far stays put.
                    moveBoundary(near: true, dz: dz)
                case .far:
                    moveBoundary(near: false, dz: dz)
                case .orbit:
                    if let rig = view.scene?.rootNode.childNode(withName: "rig", recursively: false) {
                        rig.eulerAngles.y = max(-0.85, min(0.85, startYaw + translation.x / 300))
                    }
                case nil:
                    break
                }
                refresh()
            default:
                dragTarget = nil
            }
        }

        /// Move one edge of the sharp zone, keeping the other edge fixed.
        private func moveBoundary(near: Bool, dz: Double) {
            let startHalf = startRange * 0.4
            let nearEdge = startFocus - startHalf
            let farEdge = startFocus + startHalf
            let newNear = near ? (nearEdge + dz).clamped(to: 0...1) : nearEdge
            let newFar = near ? farEdge : (farEdge + dz).clamped(to: 0...1)
            let lo = min(newNear, newFar), hi = max(newNear, newFar)
            model.edit.focusDepth = (lo + hi) / 2
            model.edit.focusRange = ((hi - lo) / 2 / 0.4).clamped(to: 0...1)
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
