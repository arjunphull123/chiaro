#!/bin/zsh
# One command from clean tree to published release:
#   scripts/release.sh 1.0.1
# Stamps the version, builds the app and the themed DMG, updates the cask's
# version and sha256, commits, tags, and (when gh is installed) pushes and
# creates the GitHub release with the DMG attached. The tap copy is the one
# manual step, printed at the end.
set -euo pipefail

# Release notes come from CHANGELOG.md's "## [Unreleased]" section (Keep a
# Changelog format). These three functions do the file surgery; the main flow
# below just calls them in order.

# Exits 1 if CHANGELOG.md has no "## [Unreleased]" heading, or the heading
# has no body before the next "## " heading.
changelog_verify_unreleased() {
  local file=$1
  awk '
    /^## \[Unreleased\]/ { found=1; next }
    found && /^## / { exit }
    found && NF { hascontent=1 }
    END { exit !(found && hascontent) }
  ' "$file"
}

# Renames "## [Unreleased]" to "## [<version>] - <date>" and inserts a fresh,
# empty "## [Unreleased]" heading above it.
changelog_cut_release() {
  local file=$1 version=$2 reldate=$3
  local tmp; tmp=$(mktemp)
  awk -v ver="$version" -v reldate="$reldate" '
    /^## \[Unreleased\]/ {
      print "## [Unreleased]"
      print ""
      print "## [" ver "] - " reldate
      next
    }
    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

# Writes the body of the section starting at the given heading (verbatim
# text, e.g. "## [1.0.0] - 2026-08-27") up to the next "## " heading, into
# outfile.
changelog_extract_section() {
  local file=$1 heading=$2 outfile=$3
  awk -v h="$heading" '
    $0 == h { found=1; next }
    found && /^## / { exit }
    found { print }
  ' "$file" > "$outfile"
}

cd "$(dirname "$0")/.."

V=${1:?usage: scripts/release.sh <version>}
[[ -z $(git status --porcelain) ]] || { echo "Working tree not clean — commit first"; exit 1; }
# Fail before doing any build work if the push target isn't wired up (see
# docs/LAUNCH.md) — better than dying half-committed at the push step.
git remote get-url origin >/dev/null 2>&1 || { echo "No 'origin' remote — see docs/LAUNCH.md prerequisites"; exit 1; }

changelog_verify_unreleased CHANGELOG.md || { echo "CHANGELOG.md has no content under '## [Unreleased]': write release notes first"; exit 1; }
RELDATE=$(date +%Y-%m-%d)
changelog_cut_release CHANGELOG.md "$V" "$RELDATE"
NOTES=$(mktemp)
changelog_extract_section CHANGELOG.md "## [$V] - $RELDATE" "$NOTES"

sed -i '' "s/^VERSION=.*/VERSION=\"$V\"/" scripts/bundle.sh
grep -q "VERSION=\"$V\"" scripts/bundle.sh || { echo "Version stamp failed — bundle.sh VERSION line format changed"; exit 1; }
scripts/bundle.sh
# Archive the unstripped binary so a stripped-build crash report can still be
# symbolicated later (bundle.sh strips before signing; .build/release is
# overwritten on the next build).
mkdir -p dist/symbols
cp .build/release/Chiaro "dist/symbols/Chiaro-$V-unstripped"

scripts/dmg.sh "$V"
SHA=$(shasum -a 256 "dist/Chiaro-$V.dmg" | cut -d' ' -f1)
sed -i '' "s/^  version \".*\"/  version \"$V\"/" docs/homebrew/chiaro.rb
sed -i '' "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" docs/homebrew/chiaro.rb

git add scripts/bundle.sh docs/homebrew/chiaro.rb CHANGELOG.md
git commit -m "Release $V"
git tag "v$V"
echo "Built dist/Chiaro-$V.dmg (cask sha256 $SHA)"

# The site states the measured size; keep its claim true.
MB=$(/usr/bin/python3 -c "print(f'{$(stat -f%z "dist/Chiaro-$V.dmg")/1e6:.1f}')")
SITE=../chiaro-site/index.html
if [[ -f $SITE ]]; then
  /usr/bin/sed -i '' -E "s/and just [0-9.]+MB\./and just ${MB}MB./g" "$SITE"
  echo "Stamped ${MB}MB into chiaro-site — rebuild and deploy the site."
else
  echo "DMG is ${MB}MB — update the site's close line if it changed."
fi

if command -v gh >/dev/null 2>&1; then
  git push && git push --tags
  gh release create "v$V" "dist/Chiaro-$V.dmg" --title "Chiaro $V" --notes-file "$NOTES"
  echo "Release v$V published."
  rm -f "$NOTES"
else
  echo "gh is not installed: push, then create release v$V on GitHub, attach the DMG, and paste $NOTES as the notes."
fi

cat <<NOTE

Last step, the tap (once ~/Documents/GitHub/homebrew-tap exists):
  cp docs/homebrew/chiaro.rb ../homebrew-tap/Casks/chiaro.rb
  cd ../homebrew-tap && git commit -am "Chiaro $V" && git push
NOTE
