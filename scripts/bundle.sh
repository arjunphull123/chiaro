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
cp -R .build/release/Chiaro_Chiaro.bundle "$APP/Contents/Resources/"

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
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built $APP"
