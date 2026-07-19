#!/bin/sh
# Build Claude Island.app (minimal bundle so Login Items / Gatekeeper are happy).
# Usage: ./build.sh [--universal]
#   --universal   build arm64 + x86_64 (used by CI for releases)
#   VERSION=x.y.z overrides the version (defaults to latest git tag)
set -e
cd "$(dirname "$0")"
APP="Claude Island.app"
VERSION="${VERSION:-$(git describe --tags --always 2>/dev/null | sed 's/^v//')}"
VERSION="${VERSION:-0.0.0}"

if [ "$1" = "--universal" ]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN=".build/apple/Products/Release/ClaudeIsland"
else
  swift build -c release
  BIN=".build/release/ClaudeIsland"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ClaudeIsland"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>ClaudeIsland</string>
  <key>CFBundleIdentifier</key><string>dev.pj.claude-island</string>
  <key>CFBundleName</key><string>Claude Island</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign -s - --force "$APP" 2>/dev/null || true
echo "built: $PWD/$APP (v$VERSION)"

# keep the installed copy in sync
if [ -d "/Applications/$APP" ]; then
  rm -rf "/Applications/$APP"
  cp -R "$APP" /Applications/
  echo "updated: /Applications/$APP"
fi
