# ADR 0014: Distribution: ad-hoc signing, a personal tap, and no Sparkle

**Status:** Accepted · 2026-08-19

## Context
v1.0.0 ships as a downloadable Mac app. Three questions had to be settled
together, because the answer to the first constrains the other two:

1. **Signing.** Apple's Developer Program is $99/yr. Without it there is no
   Developer ID certificate, so no notarization, so Gatekeeper quarantines the
   download. Control-clicking to bypass Gatekeeper was removed in macOS 15 —
   users must now go through System Settings → Privacy & Security.
2. **Homebrew.** `homebrew/cask` gates new software on notability (75 stars,
   30 forks, or 30 watchers). A brand-new repo does not qualify.
3. **Updates.** Sparkle is the default for Mac apps outside the App Store.

## Decision

**Ad-hoc signing for v1.0.0.** `scripts/bundle.sh` already signs with `-`,
which gets a stable code identity without a certificate. The README documents
the Privacy & Security route and the `xattr -d com.apple.quarantine` one-liner.
This is reversible: notarizing a later release breaks nothing and needs no
change to how the app is built, only extra steps after it.

**A personal tap, not homebrew/cask.** `arjunphull123/homebrew-tap` gives
`brew install --cask arjunphull123/tap/chiaro` today. `--no-quarantine` skips
the Gatekeeper step for anyone who trusts the source. Revisit `homebrew/cask`
if the repo ever clears the notability bar.

**No Sparkle. GitHub Releases plus an in-app check.** Sparkle would be the
first third-party dependency in the project (ADR 0001 sets that bar high), and
it wants a Developer ID to work properly — its EdDSA appcast signing exists
precisely because unsigned updates are a supply-chain hazard, and an ad-hoc
app replacing itself in place is exactly the shape of thing Gatekeeper is
suspicious of. In exchange for a dependency, a hosted appcast, and a signing
key we cannot yet use well, we would get silent background updates.

Instead: **Chiaro asks GitHub for the latest release tag and, when it is newer,
points the user at the release page.** One `URLSession` call to
`/repos/arjunphull123/chiaro/releases/latest`, no dependency, no key material,
and no code that overwrites the running app. The user downloads and replaces it
themselves — the same trust decision they already made at install.

## Consequences
- First launch after download costs the user three clicks and needs
  documentation. This is the real price of not paying $99/yr, and it will lose
  some non-technical users.
- Updates are manual. Acceptable for a photo editor nobody depends on for
  uptime; unacceptable if Chiaro ever ships security-relevant surface.
- The release binary is arm64-only. Building universal is one flag away if an
  Intel Mac on macOS 26 ever asks.
- If notarization is bought later: add `--options runtime --timestamp` to the
  codesign call, `notarytool submit --wait`, and `stapler staple`. The tap and
  the update check need no changes; the Gatekeeper section of the README gets
  deleted.
