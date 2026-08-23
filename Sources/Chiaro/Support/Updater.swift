import AppKit
import Observation

/// Update check against GitHub Releases — no Sparkle, no dependency, and no
/// code that overwrites the running app (ADR 0014). The user downloads and
/// replaces it themselves.
@Observable @MainActor
final class Updater {
    static let shared = Updater()

    static let repoPage = URL(string: "https://github.com/arjunphull123/chiaro")!
    private static let latestAPI = URL(string: "https://api.github.com/repos/arjunphull123/chiaro/releases/latest")!
    private static let releasesPage = URL(string: "https://github.com/arjunphull123/chiaro/releases/latest")!

    /// Set only when a newer release exists and the user hasn't waved it off.
    private(set) var available: String?

    /// nil in a dev build run straight from `swift run` — there's no Info.plist.
    static var currentVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    private var dismissed: String? {
        get { UserDefaults.standard.string(forKey: "dismissedUpdate") }
        set { UserDefaults.standard.set(newValue, forKey: "dismissedUpdate") }
    }

    /// Silent check at launch: surfaces a chip in the library, never a dialog.
    static func checkInBackground() {
        guard let current = currentVersion else { return }
        Task {
            guard let latest = try? await fetchLatest(), isNewer(latest, than: current) else { return }
            if shared.dismissed != latest { shared.available = latest }
        }
    }

    /// The menu command: always says something, even when there's nothing to say.
    static func checkForUpdates() {
        Task {
            let latest: String
            do { latest = try await fetchLatest() } catch {
                // A DecodingError is the API answering without a release —
                // its own description ("the data is missing") helps nobody.
                let reason = error is DecodingError
                    ? "GitHub has no published release to compare against."
                    : error.localizedDescription
                alert("Couldn't check for updates",
                      "\(reason)\n\nYou can always check the releases page directly.",
                      confirm: "Open releases")
                return
            }
            guard let current = currentVersion else {
                alert("Development build", "This build has no version to compare — \(latest) is the latest release.",
                      confirm: "Open releases")
                return
            }
            if isNewer(latest, than: current) {
                shared.available = latest
                alert("Chiaro \(latest) is available", "You're on \(current).", confirm: "Download")
            } else {
                alert("You're up to date", "Chiaro \(current) is the latest release.")
            }
        }
    }

    func dismiss() {
        dismissed = available
        available = nil
    }

    func openReleases() { NSWorkspace.shared.open(Self.releasesPage) }

    private static func fetchLatest() async throws -> String {
        var request = URLRequest(url: latestAPI)
        request.setValue("Chiaro", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        let release = try JSONDecoder().decode(Release.self, from: data)
        return String(release.tagName.trimmingPrefix("v"))
    }

    private static func isNewer(_ latest: String, than current: String) -> Bool {
        latest.compare(current, options: .numeric) == .orderedDescending
    }

    private static func alert(_ title: String, _ message: String, confirm: String? = nil) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        guard let confirm else {
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn { shared.openReleases() }
    }

    private struct Release: Decodable {
        let tagName: String
        enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
    }
}
