# Launch runbook

The order matters: several steps depend on artifacts earlier steps produce, and
the public-facing links only resolve once the repo, the tap, the release, and
the DNS all exist. Run top to bottom.

## Prerequisites (once)

1. **Create the repo** (private to start, so the release can be staged before
   anyone can see it):
   ```
   gh repo create arjunphull123/chiaro --private --source=. --remote=origin --push
   ```
2. **Create the Homebrew tap** — the site's `brew install --cask
   arjunphull123/tap/chiaro` fails until this exists and holds the cask:
   ```
   gh repo create arjunphull123/homebrew-tap --public
   git clone git@github.com:arjunphull123/homebrew-tap Casks && \
     mkdir -p Casks/Casks && cp docs/homebrew/chiaro.rb Casks/Casks/
   # the cask's sha256 is filled in by release.sh below; push after that
   ```
3. **DNS**: point `chiaro.arjunphull.dev` at Netlify (CNAME/ALIAS) and attach the
   custom domain in the Netlify site. `og:image` and every share preview use this
   host, so it must resolve before the post goes out.

## Cut the release

`scripts/release.sh <version>` stamps the version, builds the stripped app,
archives the unstripped binary (for later crash symbolication), builds the DMG,
fills the cask's sha256, measures the real DMG size and stamps it into the
site's copy, commits, tags, pushes, and creates the GitHub release. Run it while
the repo is still private — a release lives fine in a private repo:

```
scripts/release.sh 1.0.0
```

Then push the tap with the now-filled cask, and rebuild + deploy the site so the
stamped size (currently ~4.8 MB, not the old 3.6 MB) goes live:

```
git -C Casks add -A && git -C Casks commit -m "chiaro 1.0.0" && git -C Casks push
cd ../chiaro-site && npm run build && <deploy>   # Netlify picks up the push
```

## Go public (the switch that lights up every link)

Until this runs, every `github.com/arjunphull123/chiaro` link 404s — both
download buttons, the badges, the README, the app's Help menu, the site footer:

```
gh repo edit arjunphull123/chiaro --visibility public --accept-visibility-change-consequences
```

Before flipping it, audit the profile the post will send people to: `gh repo
list arjunphull123 --visibility public` and make private anything that does not
need to be public; check the profile README, avatar, bio, and pinned repos
(pin chiaro). The post links the repo, and the repo links the profile.

## Verify before posting

- [ ] `https://chiaro.arjunphull.dev` resolves and loads
- [ ] every download button reaches the DMG; the release page shows one asset
- [ ] `brew install --cask arjunphull123/tap/chiaro` works on a clean machine
- [ ] the site's size line matches the real DMG
- [ ] README badges render (repo public + release exists)
- [ ] hand-test the DMG on a machine that has never run Chiaro (Gatekeeper flow):
      the ad-hoc signature means first open is System Settings › Privacy &
      Security › Open Anyway, or `xattr -d com.apple.quarantine /Applications/Chiaro.app`
- [ ] paste the site URL into LinkedIn's post composer and confirm the unfurl

## After the post

- Submit the project at claude.com/community (the "share what you built" form) —
  Chiaro is on-thesis for a Claude social feature.
- Watch GitHub Issues (the Report a bug form routes here).

## GitHub repo settings (by hand, once public)

- Description: `A native macOS RAW photo editor with a first-party MCP server inside the app. Free and open source.`
- Topics: `macos`, `swiftui`, `raw-photo-editor`, `mcp`, `photography`
- Social preview image: `docs/screenshots/card.jpg`
- Branch protection on `main` (post-launch work lands on feature branches)
- Enable private vulnerability reporting (Settings → Security → Code security)
  so SECURITY.md's reporting path works
