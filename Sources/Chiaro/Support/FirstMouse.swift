import AppKit

/// Click-through for the whole app, Finder-style: the click that activates
/// the window also presses the control under it. SwiftUI hosts controls in
/// platform views scattered across many private classes (hosting view, glass
/// effect views, visual effect views), so the only reliable switch is the
/// NSView base implementation — every view in this process is ours.
enum FirstMouse {
    static func enableGlobally() {
        let selector = #selector(NSView.acceptsFirstMouse(for:))
        guard let method = class_getInstanceMethod(NSView.self, selector) else { return }
        let block: @convention(block) (NSView, NSEvent?) -> Bool = { _, _ in true }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }
}
