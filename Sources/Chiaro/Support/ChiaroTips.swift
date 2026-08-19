import TipKit

/// Once-only onboarding tips (configured in ChiaroApp.init).

/// First editor open: the scrub gesture is the app's core interaction and
/// invisible without a hint.
struct ScrubTip: Tip {
    var title: Text { Text("Scrub to edit") }
    var message: Text? { Text("Click a value in the rail to arm it, then drag across the photo to adjust") }
    var image: Image? { Image(systemName: "hand.draw") }
    var options: [any TipOption] { MaxDisplayCount(1) }
}

/// First time a parameter is armed: the dial responds to sideways scroll.
struct FineTuneTip: Tip {
    var title: Text { Text("Fine moves") }
    var message: Text? { Text("Scroll sideways on the trackpad to nudge the armed control in small steps") }
    var image: Image? { Image(systemName: "slider.horizontal.below.rectangle") }
    var options: [any TipOption] { MaxDisplayCount(1) }
}

/// Third editor session: surface the agent pill for people who haven't found
/// it. Session counting is a UserDefaults gate rather than a TipKit rule —
/// the #Rule macro plugin isn't available under the CLT toolchain.
struct AgentTip: Tip {
    static func noteEditorOpened() {
        let opens = UserDefaults.standard.integer(forKey: "editorOpens") + 1
        UserDefaults.standard.set(opens, forKey: "editorOpens")
    }

    static var isEligible: Bool {
        UserDefaults.standard.integer(forKey: "editorOpens") >= 3
    }

    var title: Text { Text("Bring your agent") }
    var message: Text? { Text("Claude or any MCP agent can edit alongside you — click to connect") }
    var image: Image? { Image(systemName: "sparkles") }
    var options: [any TipOption] { MaxDisplayCount(1) }
}
