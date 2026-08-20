import AppKit

/// Update check against GitHub Releases — no Sparkle, no dependency, and no
/// code that overwrites the running app (ADR 0014). The user downloads and
/// replaces it themselves.
@MainActor
enum Updater {
    private static let latestURL = URL(string: "https://api.github.com/repos/arjunphull123/chiaro/releases/latest")!
    private static let releasesPage = URL(string: "https://github.com/arjunphull123/chiaro/releases/latest")!

    /// nil in a dev build run straight from `swift run` — there's no Info.plist.
    static var currentVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    static func checkForUpdates() {
        Task {
            do {
                var request = URLRequest(url: latestURL)
                request.setValue("Chiaro", forHTTPHeaderField: "User-Agent")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, _) = try await URLSession.shared.data(for: request)
                let release = try JSONDecoder().decode(Release.self, from: data)
                present(latest: release.tagName.trimmingPrefix("v"))
            } catch {
                alert("Couldn't check for updates",
                      "\(error.localizedDescription)\n\nYou can always check the releases page directly.",
                      openReleases: true)
            }
        }
    }

    private static func present(latest: Substring) {
        guard let current = currentVersion else {
            alert("Development build", "This build has no version to compare — see the releases page for the latest.",
                  openReleases: true)
            return
        }
        if String(latest).compare(current, options: .numeric) == .orderedDescending {
            alert("Chiaro \(latest) is available", "You're on \(current).", openReleases: true, confirm: "Download")
        } else {
            alert("You're up to date", "Chiaro \(current) is the latest release.")
        }
    }

    private static func alert(_ title: String, _ message: String,
                              openReleases: Bool = false, confirm: String = "Open releases") {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        if openReleases {
            alert.addButton(withTitle: confirm)
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(releasesPage) }
        } else {
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private struct Release: Decodable {
        let tagName: String
        enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
    }
}
