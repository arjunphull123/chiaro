import SwiftUI
import SceneKit

/// Focos-style spatial focus: the photo as a depth-displaced point cloud seen
/// from an angle, with the focus plane and its Range band as real geometry.
/// Drag vertically to move the plane, horizontally to orbit, scroll to widen
/// or tighten the band. AppKit here because SceneKit has no SwiftUI surface.
struct DepthSceneView: NSViewRepresentable {
    @Bindable var model: EditViewModel

    /// World-space span of the disparity axis.
    private static let zSpan: Float = 1.15

    func makeNSView(context: Context) -> SCNView {
        let view = ScrollableSCNView()
        view.backgroundColor = .clear
        view.scene = makeScene()
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
        coordinator.updatePlanes()
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear

        let camera = SCNCamera()
        camera.zNear = 0.05
        camera.zFar = 20
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0.9, 0.55, 1.9)
        cameraNode.name = "camera"
        let constraint = SCNLookAtConstraint(target: scene.rootNode)
        constraint.isGimbalLockEnabled = true
        cameraNode.constraints = [constraint]
        scene.rootNode.addChildNode(cameraNode)

        // Everything that orbits lives under one rig node.
        let rig = SCNNode()
        rig.name = "rig"
        scene.rootNode.addChildNode(rig)
        return scene
    }

    @MainActor
    final class Coordinator: NSObject {
        var model: EditViewModel
        weak var view: SCNView?
        var builtURL: URL?
        private var startFocus: Double?
        private var startYaw: CGFloat?

        init(model: EditViewModel) {
            self.model = model
        }

        private var rig: SCNNode? { view?.scene?.rootNode.childNode(withName: "rig", recursively: false) }

        func rebuildCloud() {
            let model = model
            Task {
                guard let grid = await model.depthGrid() else { return }
                self.install(grid)
            }
        }

        private func install(_ grid: DepthEngine.PointGrid) {
            guard let rig else { return }
            rig.childNodes.forEach { $0.removeFromParentNode() }

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
                        CGFloat((d - 0.5) * DepthSceneView.zSpan)
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

            let amber = NSColor(red: 0.91, green: 0.64, blue: 0.24, alpha: 1)
            let planeSize = CGSize(width: CGFloat(grid.aspect) * 1.2, height: 1.2)

            let focusPlane = SCNNode(geometry: SCNBox(
                width: planeSize.width, height: planeSize.height, length: 0.006, chamferRadius: 0))
            focusPlane.geometry?.firstMaterial?.diffuse.contents = amber.withAlphaComponent(0.55)
            focusPlane.geometry?.firstMaterial?.lightingModel = .constant
            focusPlane.geometry?.firstMaterial?.isDoubleSided = true
            focusPlane.name = "focus"
            rig.addChildNode(focusPlane)

            let band = SCNNode(geometry: SCNBox(
                width: planeSize.width, height: planeSize.height, length: 0.01, chamferRadius: 0))
            band.geometry?.firstMaterial?.diffuse.contents = amber.withAlphaComponent(0.13)
            band.geometry?.firstMaterial?.lightingModel = .constant
            band.geometry?.firstMaterial?.isDoubleSided = true
            band.name = "band"
            rig.addChildNode(band)

            updatePlanes()
        }

        func updatePlanes() {
            guard let rig else { return }
            let target = 1 - model.edit.focusDepth
            let z = CGFloat((Float(target) - 0.5) * DepthSceneView.zSpan)
            rig.childNode(withName: "focus", recursively: false)?.position = SCNVector3(0, 0, z)
            if let band = rig.childNode(withName: "band", recursively: false) {
                band.position = SCNVector3(0, 0, z)
                let length = max(0.01, CGFloat(Float(model.edit.focusRange) * 0.4 * 2 * DepthSceneView.zSpan))
                (band.geometry as? SCNBox)?.length = length
            }
        }

        @objc func pan(_ gesture: NSPanGestureRecognizer) {
            let translation = gesture.translation(in: view)
            switch gesture.state {
            case .began:
                startFocus = model.edit.focusDepth
                startYaw = rig?.eulerAngles.y ?? 0
            case .changed:
                if abs(translation.y) >= abs(translation.x) {
                    // Drag up pushes the plane away (toward far).
                    if let startFocus {
                        model.edit.focusDepth = (startFocus - Double(translation.y) / 260).clamped(to: 0...1)
                    }
                } else if let startYaw, let rig {
                    let yaw = startYaw + translation.x / 300
                    rig.eulerAngles.y = max(-0.85, min(0.85, yaw))
                }
                updatePlanes()
            default:
                startFocus = nil
                startYaw = nil
            }
        }

        func adjustRange(by delta: CGFloat) {
            model.edit.focusRange = (model.edit.focusRange + Double(delta) / 120).clamped(to: 0...1)
            updatePlanes()
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
