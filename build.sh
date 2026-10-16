#!/bin/bash
# ./build.sh [debug|release] [native|universal]
set -euo pipefail

cd "$(dirname "$0")"
CONFIG="${1:-release}"
ARCHITECTURES="${2:-native}"
case "$CONFIG" in debug|release) ;; *) echo "Usage: $0 [debug|release] [native|universal]" >&2; exit 2 ;; esac
BUILD_ARGS=(-c "$CONFIG")
case "$ARCHITECTURES" in
  native) ;;
  universal) BUILD_ARGS+=(--arch arm64 --arch x86_64) ;;
  *) echo "Usage: $0 [debug|release] [native|universal]" >&2; exit 2 ;;
esac

swift build "${BUILD_ARGS[@]}"
BINARY="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/PodsBar"
SPARKLE_FRAMEWORK="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
  echo "Sparkle's binary artifact is missing. Run swift package resolve and try again." >&2
  exit 1
fi
mkdir -p build
STAGING="$(mktemp -d "$PWD/build/.PodsBar.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/PodsBar.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BINARY" "$APP/Contents/MacOS/PodsBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns LICENSE "$APP/Contents/Resources/"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$APP/Contents/Resources/Sparkle-LICENSE"
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
EMBEDDED_SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
# This app is not sandboxed; these optional XPC services are never enabled or used.
rm -rf "$EMBEDDED_SPARKLE/Versions/B/XPCServices" "$EMBEDDED_SPARKLE/XPCServices"

if [[ "$CONFIG" == release ]]; then
  strip -x "$APP/Contents/MacOS/PodsBar"
fi
if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
fi

# Local builds are ad-hoc signed. Distribution builds use a Developer ID identity.
SIGNING_IDENTITY="${CODESIGN_IDENTITY:--}"
if [[ "$SIGNING_IDENTITY" == - ]]; then
  SIGN_ARGS=(--force --sign - --timestamp=none)
else
  SIGN_ARGS=(--force --sign "$SIGNING_IDENTITY" --options runtime --timestamp)
fi
# Sign inside-out. --deep is for verification, not for signing nested helpers.
codesign "${SIGN_ARGS[@]}" "$EMBEDDED_SPARKLE/Versions/B/Autoupdate"
codesign "${SIGN_ARGS[@]}" "$EMBEDDED_SPARKLE/Versions/B/Updater.app"
codesign "${SIGN_ARGS[@]}" "$EMBEDDED_SPARKLE"
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
# Only replace the previous build once compilation, packaging, and signing have succeeded.
rm -rf build/PodsBar.app
mv "$APP" build/PodsBar.app

echo "Built build/PodsBar.app ($CONFIG, $ARCHITECTURES)"
