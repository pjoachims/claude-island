#!/bin/sh
# Install Atoll: download the latest release into /Applications.
# curl downloads don't get the macOS quarantine flag, so Gatekeeper
# won't block the (ad-hoc signed) app the way a browser download would.
set -e
ZIP_URL="https://github.com/pjoachims/claude-island/releases/latest/download/Atoll.zip"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading latest Atoll..."
curl -fsSL -o "$TMP/Atoll.zip" "$ZIP_URL"
ditto -xk "$TMP/Atoll.zip" "$TMP"

pkill -x Atoll 2>/dev/null || true
rm -rf "/Applications/Atoll.app"
# Atoll used to be Claude Island; retire the old install
pkill -x ClaudeIsland 2>/dev/null || true
rm -rf "/Applications/Claude Island.app"
ditto "$TMP/Atoll.app" "/Applications/Atoll.app"
xattr -dr com.apple.quarantine "/Applications/Atoll.app" 2>/dev/null || true

echo "Installed: /Applications/Atoll.app"
open "/Applications/Atoll.app"
