#!/bin/zsh
# Themed installer image via dmgbuild (writes the .DS_Store directly — no
# Finder scripting, no async races). Layout lives in scripts/dmg-settings.py,
# artwork in scripts/dmg-bg.tiff (1x + 2x reps).
#   scripts/dmg.sh <version>
set -euo pipefail
cd "$(dirname "$0")/.."
V=${1:?usage: scripts/dmg.sh <version>}

[[ -d dist/Chiaro.app ]] || { echo "dist/Chiaro.app missing — run scripts/bundle.sh first"; exit 1; }
/usr/bin/python3 -c "import dmgbuild" 2>/dev/null || { echo "dmgbuild missing — /usr/bin/python3 -m pip install --user dmgbuild"; exit 1; }
# The plate under the icon should read "Chiaro", not "Chiaro.app".
SetFile -a E dist/Chiaro.app 2>/dev/null || true
rm -f "dist/Chiaro-$V.dmg"
/usr/bin/python3 -m dmgbuild -s scripts/dmg-settings.py -D app=dist/Chiaro.app "Chiaro" "dist/Chiaro-$V.dmg"

# The label should read "Chiaro": dmgbuild's copy drops the hidden-extension
# flag, so set it inside the image and recompress.
if command -v SetFile >/dev/null 2>&1; then
  hdiutil convert -quiet "dist/Chiaro-$V.dmg" -format UDRW -o dist/rw-tmp.dmg
  MP=$(hdiutil attach -nobrowse dist/rw-tmp.dmg | grep Apple_HFS | awk -F'\t' '{print $NF}' | xargs)
  SetFile -a E "$MP/Chiaro.app"
  hdiutil detach -quiet "$MP"
  rm -f "dist/Chiaro-$V.dmg"
  hdiutil convert -quiet dist/rw-tmp.dmg -format ULFO -o "dist/Chiaro-$V.dmg"
  rm -f dist/rw-tmp.dmg
fi
echo "Built dist/Chiaro-$V.dmg"
