#!/bin/zsh
# Themed installer image: The Calling as the backdrop, the app on the left,
# Applications on the right, an arrow for the drag. Finder layout is written
# into the DMG's .DS_Store while it is writable, then compressed.
#   scripts/dmg.sh <version>
set -euo pipefail
cd "$(dirname "$0")/.."
V=${1:?usage: scripts/dmg.sh <version>}

[[ -d dist/Chiaro.app ]] || { echo "dist/Chiaro.app missing — run scripts/bundle.sh first"; exit 1; }
rm -f "dist/Chiaro-$V.dmg" dist/Chiaro-rw.dmg

STAGE=$(mktemp -d)
cp -R dist/Chiaro.app "$STAGE/"
mkdir "$STAGE/.background"
cp scripts/dmg-bg.png "$STAGE/.background/bg.png"

hdiutil create -volname "Chiaro" -srcfolder "$STAGE" -ov -format UDRW -quiet dist/Chiaro-rw.dmg
rm -rf "$STAGE"
hdiutil attach -quiet -noautoopen dist/Chiaro-rw.dmg
# Finder needs a beat to register the mount.
for i in {1..10}; do
  osascript -e 'tell application "Finder" to get disk "Chiaro"' >/dev/null 2>&1 && break
  sleep 1
done

osascript <<'APPLESCRIPT'
tell application "Finder"
  -- A real alias file, not a bare symlink: Finder reliably draws the
  -- target's icon for aliases on read-only images.
  make new alias file at disk "Chiaro" to POSIX file "/Applications"
  set name of result to "Applications"
  tell disk "Chiaro"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {400, 200, 1060, 728}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 116
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:bg.png"
    -- Icons ride low so their Finder labels clip below the window; the
    -- background art carries white captions instead.
    set position of item "Chiaro.app" of container window to {165, 430}
    set position of item "Applications" of container window to {495, 430}
    -- Hidden housekeeping items sit outside the window for anyone whose
    -- Finder shows hidden files.
    try
      set position of item ".background" of container window to {165, 700}
    end try
    try
      set position of item ".fseventsd" of container window to {495, 700}
    end try
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach -quiet "/Volumes/Chiaro"
hdiutil convert -quiet dist/Chiaro-rw.dmg -format ULFO -o "dist/Chiaro-$V.dmg"
rm -f dist/Chiaro-rw.dmg
echo "Built dist/Chiaro-$V.dmg"
