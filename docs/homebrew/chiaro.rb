# Source of truth for the cask published to arjunphull123/homebrew-tap.
# Update version + sha256 on each release, then copy into the tap repo.
cask "chiaro" do
  version "1.0.0"
  sha256 "6bf2a1dfd0e757c56007778aa9185e135fd1a5d126b71be3694aa8ca7b5540f2"

  url "https://github.com/arjunphull123/chiaro/releases/download/v#{version}/Chiaro-#{version}.dmg"
  name "Chiaro"
  desc "Native RAW photo editor with a built-in MCP server"
  homepage "https://github.com/arjunphull123/chiaro"

  depends_on macos: ">= :tahoe"
  depends_on arch: :arm64

  app "Chiaro.app"

  # Chiaro is ad-hoc signed, not notarized (ADR 0014). Without --no-quarantine,
  # first launch needs System Settings > Privacy & Security > Open Anyway.
  caveats do
    <<~EOS
      Chiaro is not notarized. If you installed without --no-quarantine, the
      first launch is blocked: open System Settings > Privacy & Security and
      click "Open Anyway" next to Chiaro.
    EOS
  end

  zap trash: [
    "~/Library/Application Support/Chiaro",
    "~/.chiaro",
    "~/Library/Preferences/Chiaro.plist",
  ]
end
