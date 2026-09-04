#!/bin/bash
# Builds PodsBar.app into ./build. Run: ./build.sh [debug|release]
set -euo pipefail

cd "$(dirname "$0")"
CONFIG="${1:-release}"
APP="build/PodsBar.app"

swift build -c "$CONFIG"
BINARY="$(swift build -c "$CONFIG" --show-bin-path)/PodsBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/PodsBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature. Enough to run locally; replace with your Developer ID to share it.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1

echo "Built $APP"
