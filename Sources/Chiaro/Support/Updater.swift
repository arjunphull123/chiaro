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
                shared.offerUpdate(from: current)
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

    static let brewUpgrade = "brew upgrade --cask --no-quarantine chiaro"

    /// A Homebrew cask leaves a Caskroom entry beside the app it installed, so
    /// the update instruction can name the route this copy actually came from.
    private static var installedByHomebrew: Bool {
        ["/opt/homebrew/Caskroom/chiaro", "/usr/local/Caskroom/chiaro"]
            .contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// Both entry points (the menu command and the library chip) land here.
    /// Chiaro never replaces itself (ADR 0014), so this hands over the command
    /// or the page and stops. Each route names the other, since a copy can be
    /// installed one way and replaced the other.
    func offerUpdate(latest: String? = nil, from current: String? = nil) {
        let version = (latest ?? available).map { "Chiaro \($0) is available" } ?? "A newer Chiaro is available"
        let onVersion = (current ?? Self.currentVersion).map { "You're on \($0)" } ?? "This build has no version"
        if Self.installedByHomebrew {
            Self.alert(
                version,
                """
                \(onVersion), installed with Homebrew.

                \(Self.brewUpgrade)

                The --no-quarantine keeps macOS from blocking the new copy. The \
                DMG on the release page works too.
                """,
                confirm: "Copy command",
                action: { Self.copyBrewUpgrade() }
            )
        } else {
            Self.alert(
                version,
                """
                \(onVersion). Download the new DMG, and drag it over the copy in \
                Applications.

                Installed with Homebrew instead? Run \(Self.brewUpgrade)
                """,
                confirm: "Open releases"
            )
        }
    }

    private static func copyBrewUpgrade() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(brewUpgrade, forType: .string)
    }

    private static func fetchLatest() async throws -> String {
        var request = URLRequest(url: latestAPI)
        request.setValue("Chiaro", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        let release = try JSONDecoder().decode(Release.self, from: data)
        return String(release.tagName.trimmingPrefix("v"))
    }

    static func isNewer(_ latest: String, than current: String) -> Bool {
        latest.compare(current, options: .numeric) == .orderedDescending
    }

    /// `action` defaults to opening the releases page (resolved in the body:
    /// a default argument is type-checked outside this type's isolation).
    private static func alert(
        _ title: String, _ message: String, confirm: String? = nil,
        action: (() -> Void)? = nil
    ) {
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
        if alert.runModal() == .alertFirstButtonReturn { (action ?? { shared.openReleases() })() }
    }

    private struct Release: Decodable {
        let tagName: String
        enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
    }
}
