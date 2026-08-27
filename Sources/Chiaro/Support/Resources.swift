import Foundation

/// The bundled assets (fonts, agent marks, the editing skill). The .app carries
/// them in Contents/Resources; a `swift run` build reads them from the checkout,
/// found by walking up from the executable to Package.swift.
///
/// Deliberately not SwiftPM's `Bundle.module`: its generated accessor bakes the
/// absolute build path into the binary and falls back to it when the bundle is
/// not beside the executable, which is always the case inside a signed .app.
/// That shipped the developer's home directory in the binary, raised a
/// Documents permission prompt at launch on that one machine, and crashed
/// with fatalError on every other.
enum Resources {
    static let root: URL = {
        if let bundled = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("Fonts").path) {
            return bundled
        }
        var dir = Bundle.main.executableURL?.deletingLastPathComponent() ?? URL(fileURLWithPath: ".")
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                return dir.appendingPathComponent("Sources/Chiaro/Resources")
            }
            dir.deleteLastPathComponent()
        }
        return Bundle.main.resourceURL ?? dir
    }()

    static func url(_ path: String) -> URL { root.appendingPathComponent(path) }
}
