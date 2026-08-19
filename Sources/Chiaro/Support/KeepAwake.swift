import Foundation

/// Holds a ProcessInfo activity while real work is in flight, releasing it after a
/// quiet period. Without this, App Nap throttles decodes, Vision, renders, and MCP
/// handling to a crawl whenever Chiaro isn't frontmost — which is always the case
/// when an agent is driving it.
enum KeepAwake {
    private static var token: NSObjectProtocol?
    private static var expiry: DispatchWorkItem?

    static func poke(_ seconds: TimeInterval = 15) {
        DispatchQueue.main.async {
            if token == nil {
                token = ProcessInfo.processInfo.beginActivity(
                    options: [.userInitiated, .latencyCritical], reason: "Chiaro active work"
                )
            }
            expiry?.cancel()
            let item = DispatchWorkItem {
                if let t = token {
                    ProcessInfo.processInfo.endActivity(t)
                    token = nil
                }
            }
            expiry = item
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        }
    }
}
