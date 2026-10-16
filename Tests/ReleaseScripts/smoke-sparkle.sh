#!/bin/bash
# Exercise real Sparkle signing/verification with a disposable key, never the release key.
set -euo pipefail
umask 077
source "$(dirname "$0")/../../scripts/sparkle-tools.sh"
resolve_sparkle
cd "$PODSBAR_ROOT"
WORK="$(mktemp -d "$PODSBAR_ROOT/build/.sparkle-smoke.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/archives"
PUBLIC_KEY="$(swift - "$WORK/test.key" <<'SWIFT'
import CryptoKit
import Foundation
let key = Curve25519.Signing.PrivateKey()
try Data(key.rawRepresentation.base64EncodedString().utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print(key.publicKey.rawRepresentation.base64EncodedString())
SWIFT
)"
ditto build/PodsBar.app "$WORK/PodsBar.app"
cat > "$WORK/UpdaterProbe.swift" <<'SWIFT'
import AppKit
import Sparkle
@main @MainActor
enum Probe {
    static func main() throws {
        _ = NSApplication.shared
        guard let bundle = Bundle(path: CommandLine.arguments[1]) else { fatalError("Missing test bundle") }
        let driver = SPUStandardUserDriver(hostBundle: bundle, delegate: nil)
        let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: nil)
        try updater.start()
        precondition(updater.canCheckForUpdates, "Updater did not become ready")
        print("Sparkle starts with the packaged framework and app configuration.")
        // Exit before the scheduled runloop cycle; no UI or network check is requested.
    }
}
SWIFT
swiftc -parse-as-library "$WORK/UpdaterProbe.swift" -F "$WORK/PodsBar.app/Contents/Frameworks" \
  -framework Sparkle -Xlinker -rpath -Xlinker "$WORK/PodsBar.app/Contents/Frameworks" -o "$WORK/updater-probe"
"$WORK/updater-probe" "$WORK/PodsBar.app"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBLIC_KEY" "$WORK/PodsBar.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 2' "$WORK/PodsBar.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 1.1.0' "$WORK/PodsBar.app/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$WORK/PodsBar.app"
ditto -c -k --sequesterRsrc --keepParent "$WORK/PodsBar.app" "$WORK/archives/PodsBar-1.1.0.zip"
printf '%s\n' '# Test release' 'Disposable signing test; never publish these artifacts.' > "$WORK/archives/PodsBar-1.1.0.md"
PREFIX='https://github.com/musaAmir/podsbar/releases/download/v1.1.0/'
"$SPARKLE_TOOLS/generate_appcast" --ed-key-file "$WORK/test.key" --maximum-deltas 0 \
  --download-url-prefix "$PREFIX" --embed-release-notes "$WORK/archives"
"$SPARKLE_TOOLS/sign_update" --ed-key-file "$WORK/test.key" --verify "$WORK/archives/appcast.xml"
python3 scripts/release_support.py verify "$WORK/archives/appcast.xml" "$WORK/archives/PodsBar-1.1.0.zip" \
  1.1.0 2 "${PREFIX}PodsBar-1.1.0.zip" > "$WORK/manifest.json"
SIGNATURE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["signature"])' "$WORK/manifest.json")"
"$SPARKLE_TOOLS/sign_update" --ed-key-file "$WORK/test.key" --verify "$WORK/archives/PodsBar-1.1.0.zip" "$SIGNATURE"
cp "$WORK/archives/appcast.xml" "$WORK/tampered.xml"
python3 - "$WORK/tampered.xml" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
assert 'PodsBar-1.1.0.zip' in text
path.write_text(text.replace('PodsBar-1.1.0.zip', 'PodsBar-1.1.0-tampered.zip'))
PY
if "$SPARKLE_TOOLS/sign_update" --ed-key-file "$WORK/test.key" --verify "$WORK/tampered.xml" > "$WORK/rejection.log" 2>&1; then
  echo "ERROR: Tampered feed was accepted" >&2; exit 1
fi
printf 'tampered' >> "$WORK/archives/PodsBar-1.1.0.zip"
if "$SPARKLE_TOOLS/sign_update" --ed-key-file "$WORK/test.key" --verify "$WORK/archives/PodsBar-1.1.0.zip" "$SIGNATURE" > "$WORK/rejection.log" 2>&1; then
  echo "ERROR: Tampered update was accepted" >&2; exit 1
fi
echo "Sparkle smoke test passed: signed feed and archive verified; tampering rejected."
# Simulate the next release, with no previous ZIP present in the staging directory.
cp "$WORK/archives/appcast.xml" "$WORK/previous.xml"
rm "$WORK/archives/appcast.xml"
rm "$WORK/archives/PodsBar-1.1.0.zip" "$WORK/archives/PodsBar-1.1.0.md"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 3' "$WORK/PodsBar.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 1.1.1' "$WORK/PodsBar.app/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$WORK/PodsBar.app"
ditto -c -k --sequesterRsrc --keepParent "$WORK/PodsBar.app" "$WORK/archives/PodsBar-1.1.1.zip"
"$SPARKLE_TOOLS/generate_appcast" --ed-key-file "$WORK/test.key" --maximum-deltas 0 \
  --download-url-prefix 'https://github.com/musaAmir/podsbar/releases/download/v1.1.1/' "$WORK/archives"
python3 scripts/release_support.py merge-previous "$WORK/archives/appcast.xml" "$WORK/previous.xml"
"$SPARKLE_TOOLS/sign_update" --ed-key-file "$WORK/test.key" "$WORK/archives/appcast.xml"
"$SPARKLE_TOOLS/sign_update" --ed-key-file "$WORK/test.key" --verify "$WORK/archives/appcast.xml"
python3 - "$WORK/archives/appcast.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
items = ET.parse(sys.argv[1]).findall('./channel/item')
assert [item.findtext(ns + 'version') for item in items] == ['3', '2']
assert items[1].find('enclosure').get('url') == 'https://github.com/musaAmir/podsbar/releases/download/v1.1.0/PodsBar-1.1.0.zip'
PY
echo "Feed history smoke test passed: prior release URLs retained and merged feed re-signed."
