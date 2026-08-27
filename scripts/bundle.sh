#!/bin/zsh
# Builds Chiaro.app from a release build: binary + SPM resource bundle + .icns.
# Usage: scripts/bundle.sh [output-dir]   (default: dist/)
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-dist}"
APP="$OUT/Chiaro.app"
VERSION="1.0.0"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Chiaro "$APP/Contents/MacOS/Chiaro"
# Fonts/, AgentIcons/, Skill/, AppIcon.png straight into Contents/Resources,
# where Support/Resources.swift looks for them.
cp -R Sources/Chiaro/Resources/. "$APP/Contents/Resources/"

# The .app must be self-contained: no path into this checkout may survive in
# the binary. SwiftPM's Bundle.module accessor did exactly that (and crashed
# on any Mac without the checkout), so refuse to ship a binary that names one.
if strings "$APP/Contents/MacOS/Chiaro" | grep -q "^/Users/"; then
  echo "Binary references a /Users/ path; the app would not be self-contained" >&2
  strings "$APP/Contents/MacOS/Chiaro" | grep "^/Users/" >&2
  exit 1
fi

# Strip the symbol table and debug metadata before signing: swift build -c
# release leaves them in __LINKEDIT, which grows with the codebase and had the
# binary at 5.6MB / the DMG at 5.4MB. Stripping takes the binary to ~2MB. Must
# run before codesign, since stripping invalidates a signature.
strip -rSTx "$APP/Contents/MacOS/Chiaro"

# .icns from the 1024pt master.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
MASTER="Sources/Chiaro/Resources/AppIcon.png"
for size in 16 32 128 256 512; do
  sips -z $size $size "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>Chiaro</string>
	<key>CFBundleDisplayName</key>
	<string>Chiaro</string>
	<key>CFBundleIdentifier</key>
	<string>dev.arjunphull.Chiaro</string>
	<key>CFBundleExecutable</key>
	<string>Chiaro</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>26.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.photography</string>
	<key>NSHumanReadableCopyright</key>
	<string>© 2026 Arjun Phull. GPL-3.0.</string>
	<key>NSDocumentsFolderUsageDescription</key>
	<string>Chiaro reads the photos in folders you open. Edits are saved as separate files and originals are never changed.</string>
	<key>NSDesktopFolderUsageDescription</key>
	<string>Chiaro reads the photos in folders you open. Edits are saved as separate files and originals are never changed.</string>
	<key>NSDownloadsFolderUsageDescription</key>
	<string>Chiaro reads the photos in folders you open. Edits are saved as separate files and originals are never changed.</string>
	<key>NSRemovableVolumesUsageDescription</key>
	<string>Chiaro reads photos straight from your camera card. Edits are saved on your Mac and the card is never written to.</string>
	<key>NSNetworkVolumesUsageDescription</key>
	<string>Chiaro reads the photos in folders you open. Edits are saved as separate files and originals are never changed.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built $APP"
