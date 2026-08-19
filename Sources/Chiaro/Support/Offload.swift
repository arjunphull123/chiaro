import Foundation

/// Dedicated queues for blocking work. Swift's cooperative pool must never block
/// (decode, Core Image render, Vision — which blocks internally on a dispatch
/// group). Running those there starves every Task in the app; found live when 133
/// thumbnail extractions queued ahead of subject detection and MCP previews.
enum Offload {
    /// RAW decode + Core Image rendering (concurrent; decodes gated in RawEngine).
    static let render = DispatchQueue(label: "chiaro.render", qos: .userInitiated, attributes: .concurrent)
    /// Vision requests, serialized on their own thread.
    static let vision = DispatchQueue(label: "chiaro.vision", qos: .userInitiated)

    static func on<T: Sendable>(_ queue: DispatchQueue, _ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }
}
