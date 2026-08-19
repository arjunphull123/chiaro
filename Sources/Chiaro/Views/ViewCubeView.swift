import SwiftUI
import SceneKit

/// CAD-style orientation cube for the 3D focus scene: rotates in sync with
/// the orbit, and clicking a face snaps the camera to that view. Graphite
/// faces, Geist labels, amber edges — the design system in miniature.
struct ViewCubeView: NSViewRepresentable {
    @Bindable var model: EditViewModel
    // Explicit so SwiftUI re-invokes updates when the orbit changes.
    var yaw: CGFloat
    var pitch: CGFloat

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.scene = Self.makeScene()
        view.alphaValue = 0.55 // indicator at rest, controller on hover
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.click(_:)))
        view.addGestureRecognizer(click)
        let pan = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        view.addGestureRecognizer(pan)
        let hover = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: context.coordinator, userInfo: nil)
        view.addTrackingArea(hover)
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.model = model
        guard let cube = view.scene?.rootNode.childNode(withName: "cube", recursively: false) else { return }
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        cube.eulerAngles = SCNVector3(pitch, -yaw, 0)
        SCNTransaction.commit()
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    private static func makeScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 0.78
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 3)
        scene.rootNode.addChildNode(cameraNode)

        let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.1)
        // SCNBox material order: front, right, back, left, top, bottom.
        box.materials = ["Front", "Right", "Back", "Left", "Top", ""].map { faceMaterial($0) }
        let cube = SCNNode(geometry: box)
        cube.name = "cube"
        scene.rootNode.addChildNode(cube)
        return scene
    }

    private static func faceMaterial(_ label: String) -> SCNMaterial {
        let side = 256
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        NSColor(red: 0.137, green: 0.137, blue: 0.149, alpha: 0.96).setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        DepthScene.amber.withAlphaComponent(0.35).setStroke()
        let border = NSBezierPath(rect: NSRect(x: 2, y: 2, width: side - 4, height: side - 4))
        border.lineWidth = 4
        border.stroke()
        if !label.isEmpty {
            let font = NSFont(name: "Geist-Medium", size: 46) ?? NSFont.systemFont(ofSize: 46, weight: .medium)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(0.82),
            ]
            let text = NSAttributedString(string: label, attributes: attributes)
            let bounds = text.size()
            text.draw(at: NSPoint(x: (CGFloat(side) - bounds.width) / 2, y: (CGFloat(side) - bounds.height) / 2))
        }
        image.unlockFocus()

        let material = SCNMaterial()
        material.diffuse.contents = image
        material.lightingModel = .constant
        return material
    }

    @MainActor
    final class Coordinator: NSObject {
        var model: EditViewModel
        weak var view: SCNView?

        init(model: EditViewModel) {
            self.model = model
        }

        private var startYaw: CGFloat = 0
        private var startPitch: CGFloat = 0

        @objc func mouseEntered(with event: NSEvent) {
            view?.animator().alphaValue = 1
        }

        @objc func mouseExited(with event: NSEvent) {
            view?.animator().alphaValue = 0.55
        }

        /// Dragging the cube orbits the main scene.
        @objc func pan(_ gesture: NSPanGestureRecognizer) {
            guard let view else { return }
            let translation = gesture.translation(in: view)
            switch gesture.state {
            case .began:
                startYaw = model.sceneYaw
                startPitch = model.scenePitch
            case .changed:
                model.sceneYaw = (startYaw - translation.x / 60).clamped(to: -.pi / 2 ... .pi / 2)
                model.scenePitch = (startPitch + translation.y / 60).clamped(to: -0.1 ... .pi / 2 - 0.06)
            default:
                break
            }
        }

        @objc func click(_ gesture: NSClickGestureRecognizer) {
            guard let view,
                  let hit = view.hitTest(gesture.location(in: view), options: nil).first else { return }
            // geometryIndex follows SCNBox material order.
            switch hit.geometryIndex {
            case 0: model.depthSceneCommand = .front
            case 1: model.depthSceneCommand = .right
            case 3: model.depthSceneCommand = .left
            case 4: model.depthSceneCommand = .top
            default: break
            }
        }
    }
}
