# Source of truth for the cask published to arjunphull123/homebrew-tap.
# Update version + sha256 on each release, then copy into the tap repo.
cask "chiaro" do
  version "1.0.0"
  sha256 "039b3dca324f37f3fa68ff47aef991f55e353e4171701cbced7ffbf373ef4d3c"

  url "https://github.com/arjunphull123/chiaro/releases/download/v#{version}/Chiaro-#{version}.dmg"
  name "Chiaro"
  desc "Native RAW photo editor with a built-in MCP server"
  homepage "https://github.com/arjunphull123/chiaro"

  # The symbol form parses with a ">=" comparator, so this is Tahoe or newer.
  # The old ">= :tahoe" string is deprecated and warns on every brew command.
  depends_on macos: :tahoe
  depends_on arch: :arm64

  app "Chiaro.app"

  # Chiaro is ad-hoc signed, not notarized (ADR 0014), so Gatekeeper stops the
  # first launch. Homebrew removed --no-quarantine in 5.0, and it inherits the
  # user's approval across an upgrade only when the signing identity is
  # unchanged; an ad-hoc identity is the build's cdhash, so every version asks
  # again. Building from source avoids all of it.
  caveats do
    <<~EOS
      Chiaro is not notarized, so macOS stops the first launch: open System
      Settings > Privacy & Security and click "Open Anyway" next to Chiaro.
      The button is offered for about an hour after the first try.

      Every version is a new app to macOS, so an update asks once more.
    EOS
  end

  zap trash: [
    "~/Library/Application Support/Chiaro",
    "~/.chiaro",
    "~/Library/Preferences/Chiaro.plist",
  ]
end
