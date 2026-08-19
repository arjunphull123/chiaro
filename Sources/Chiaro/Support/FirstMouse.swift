import AppKit

/// Click-through for the whole window, Finder-style: the click that activates
/// the window also presses the control under it. SwiftUI's hosting view says
/// no to `acceptsFirstMouse`, which makes every button in the app eat its
/// first click whenever another app was frontmost. We add an override to the
/// hosting view's own class (never `object_setClass` — an isa swap here trips
/// AppKit's responder-chain assertions during window setup).
enum FirstMouse {
    static func enable(_ view: NSView) {
        guard let cls = object_getClass(view) else { return }
        let selector = #selector(NSView.acceptsFirstMouse(for:))
        guard let method = class_getInstanceMethod(cls, selector) else { return }
        let block: @convention(block) (NSView, NSEvent?) -> Bool = { _, _ in true }
        // Fails harmlessly if this exact class already got the override.
        _ = class_addMethod(
            cls, selector,
            imp_implementationWithBlock(block),
            method_getTypeEncoding(method)
        )
    }
}
