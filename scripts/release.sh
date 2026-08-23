#!/bin/zsh
# One command from clean tree to published release:
#   scripts/release.sh 1.0.1
# Stamps the version, builds and zips, updates the cask's version and sha256,
# commits, tags, and (when gh is installed) pushes and creates the GitHub
# release with the zip attached. The tap copy is the one manual step, printed
# at the end.
set -euo pipefail
cd "$(dirname "$0")/.."

V=${1:?usage: scripts/release.sh <version>}
[[ -z $(git status --porcelain) ]] || { echo "Working tree not clean — commit first"; exit 1; }

sed -i '' "s/^VERSION=.*/VERSION=\"$V\"/" scripts/bundle.sh
scripts/bundle.sh
( cd dist && rm -f "Chiaro-$V.zip" && ditto -c -k --keepParent Chiaro.app "Chiaro-$V.zip" )
SHA=$(shasum -a 256 "dist/Chiaro-$V.zip" | cut -d' ' -f1)
sed -i '' "s/^  version \".*\"/  version \"$V\"/" docs/homebrew/chiaro.rb
sed -i '' "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" docs/homebrew/chiaro.rb

git add scripts/bundle.sh docs/homebrew/chiaro.rb
git commit -m "Release $V"
git tag "v$V"
echo "Built dist/Chiaro-$V.zip  sha256 $SHA"

if command -v gh >/dev/null 2>&1; then
  git push && git push --tags
  gh release create "v$V" "dist/Chiaro-$V.zip" --title "Chiaro $V" --generate-notes
  echo "Release v$V published."
else
  echo "gh is not installed: push, then create release v$V on GitHub and attach the zip."
fi

cat <<NOTE

Last step, the tap (once ~/Documents/GitHub/homebrew-tap exists):
  cp docs/homebrew/chiaro.rb ../homebrew-tap/Casks/chiaro.rb
  cd ../homebrew-tap && git commit -am "Chiaro $V" && git push
NOTE
