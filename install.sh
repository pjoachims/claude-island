#!/bin/sh
# Install Claude Island: download the latest release into /Applications.
# curl downloads don't get the macOS quarantine flag, so Gatekeeper
# won't block the (ad-hoc signed) app the way a browser download would.
set -e
ZIP_URL="https://github.com/pjoachims/claude-island/releases/latest/download/ClaudeIsland.zip"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading latest Claude Island..."
curl -fsSL -o "$TMP/ClaudeIsland.zip" "$ZIP_URL"
ditto -xk "$TMP/ClaudeIsland.zip" "$TMP"

pkill -x ClaudeIsland 2>/dev/null || true
rm -rf "/Applications/Claude Island.app"
ditto "$TMP/Claude Island.app" "/Applications/Claude Island.app"
xattr -dr com.apple.quarantine "/Applications/Claude Island.app" 2>/dev/null || true

echo "Installed: /Applications/Claude Island.app"
open "/Applications/Claude Island.app"
