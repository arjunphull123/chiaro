import Foundation
import Observation

/// Live view of the MCP connection: the transport is stateless HTTP, so
/// "connected" means a request arrived recently (ADR 0008).
@Observable @MainActor
final class AgentStatus {
    static let shared = AgentStatus()
    /// Persisted: agents don't re-initialize when the app restarts mid-session,
    /// so a fresh launch would otherwise show "Agent" instead of "Claude".
    var clientName: String? {
        didSet { UserDefaults.standard.set(clientName, forKey: "lastAgentClient") }
    }
    var lastSeen: Date?

    init() {
        clientName = UserDefaults.standard.string(forKey: "lastAgentClient")
    }

    struct Action: Identifiable {
        let id = UUID()
        let date: Date
        let text: String
    }
    /// Rolling log of what agents have done this session, newest first.
    private(set) var actions: [Action] = []

    func log(_ text: String) {
        actions.insert(Action(date: Date(), text: text), at: 0)
        if actions.count > 50 { actions.removeLast() }
    }

    var brand: AgentBrand { AgentBrand.match(clientName) }
    /// Capped: an unrecognized client self-reports this name over MCP, so it is
    /// arbitrary text that ends up inside UI strings. The status card is a fixed
    /// width and truncates, so this can't break the layout either way — the cap
    /// just means a long name loses its own tail rather than the sentence losing
    /// "is editing".
    var displayName: String {
        var name = brand.name == "Agent" ? (clientName ?? "Agent") : brand.name
        // Client names arrive verbatim and render mid-sentence ("x is
        // connected") — capitalize so an all-lowercase client can't put
        // lowercase copy in the UI.
        name = name.prefix(1).uppercased() + name.dropFirst()
        return name.count > 14 ? name.prefix(13) + "…" : name
    }

    /// HTTP transport is stateless: there is no disconnect signal, so any
    /// recency window produces false negatives. For a "do I still need to set
    /// this up?" affordance that's the costly error — it tells you to redo work
    /// you already did — so having been seen at all is what counts.
    var isConnected: Bool { lastSeen != nil }

    /// Recency, for anything that should reflect current activity.
    func isActive(now: Date = Date()) -> Bool {
        guard let lastSeen else { return false }
        return now.timeIntervalSince(lastSeen) < 600
    }
}
