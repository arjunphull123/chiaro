import AppKit

/// Click-through for the whole window, Finder-style: the click that activates
/// the window also presses the control under it. SwiftUI's hosting view says
/// no to `acceptsFirstMouse`, which makes every button in the app eat its
/// first click whenever another app was frontmost — so we answer for it via
/// a dynamic subclass (SwiftUI owns the hosting view; we can't subclass it
/// at compile time).
enum FirstMouse {
    static func enable(_ view: NSView) {
        guard let cls = object_getClass(view) else { return }
        let name = "ChiaroFirstMouse_\(NSStringFromClass(cls))"
        if let existing = NSClassFromString(name) {
            if !view.isKind(of: existing) { object_setClass(view, existing) }
            return
        }
        guard let subclass = objc_allocateClassPair(cls, name, 0) else { return }
        let selector = #selector(NSView.acceptsFirstMouse(for:))
        let block: @convention(block) (NSView, NSEvent?) -> Bool = { _, _ in true }
        class_addMethod(subclass, selector, imp_implementationWithBlock(block), "B@:@")
        objc_registerClassPair(subclass)
        object_setClass(view, subclass)
    }
}
