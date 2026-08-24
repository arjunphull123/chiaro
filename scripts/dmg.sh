#!/bin/zsh
# Themed installer image via dmgbuild (writes the .DS_Store directly — no
# Finder scripting, no async races). Layout lives in scripts/dmg-settings.py,
# artwork in scripts/dmg-bg.tiff (1x + 2x reps).
#   scripts/dmg.sh <version>
set -euo pipefail
cd "$(dirname "$0")/.."
V=${1:?usage: scripts/dmg.sh <version>}

[[ -d dist/Chiaro.app ]] || { echo "dist/Chiaro.app missing — run scripts/bundle.sh first"; exit 1; }
rm -f "dist/Chiaro-$V.dmg"
/usr/bin/python3 -m dmgbuild -s scripts/dmg-settings.py -D app=dist/Chiaro.app "Chiaro" "dist/Chiaro-$V.dmg"
echo "Built dist/Chiaro-$V.dmg"
