#!/bin/bash
# Build and sign a release. Notarization is required unless --adhoc is explicit.
set -euo pipefail
source "$(dirname "$0")/sparkle-tools.sh"
cd "$PODSBAR_ROOT"
SIGNING_MODE=notarized
if [[ "${1:-}" == --adhoc ]]; then
  SIGNING_MODE=ad-hoc
  shift
fi
if [[ $# != 3 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$2" =~ ^[1-9][0-9]*$ || ! -f "$3" ]]; then
  echo "Usage: $0 [--adhoc] VERSION BUILD_NUMBER RELEASE_NOTES.md" >&2
  exit 2
fi
VERSION="$1"
BUILD_NUMBER="$2"
NOTES="$(cd "$(dirname "$3")" && pwd)/$(basename "$3")"
REPOSITORY="${GITHUB_REPOSITORY:-musaAmir/podsbar}"
TAG="v$VERSION"
DESTINATION="$PODSBAR_ROOT/build/releases/$TAG"
if [[ "$SIGNING_MODE" == notarized ]]; then
  : "${CODESIGN_IDENTITY:?Set CODESIGN_IDENTITY to your Developer ID Application identity, or explicitly use --adhoc}"
  : "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your notarytool Keychain profile}"
  if [[ "$CODESIGN_IDENTITY" != "Developer ID Application:"* ]]; then
    echo "Notarized releases require a Developer ID Application identity." >&2
    exit 1
  fi
else
  export CODESIGN_IDENTITY=-
  echo "Preparing an ad-hoc signed release without Apple notarization. Gatekeeper may block first launch." >&2
fi
if [[ -e "$DESTINATION" ]]; then
  echo "$DESTINATION already exists. Use a new version; published release assets must stay immutable." >&2
  exit 1
fi
if [[ -n "$(git status --porcelain --untracked-files=no)" ||
      -n "$(git ls-files --others --exclude-standard -- Sources Resources scripts Tests .github docs ReleaseNotes Package.swift Package.resolved build.sh README.md .gitignore LICENSE)" ]]; then
  echo "Commit the release source and notes first so the GitHub tag matches the shipped app." >&2
  exit 1
fi
FEED_URL="https://github.com/$REPOSITORY/releases/latest/download/appcast.xml"
CONFIGURED_FEED="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' Resources/Info.plist)"
if [[ "$FEED_URL" != "$CONFIGURED_FEED" ]]; then
  echo "The repository and SUFeedURL do not match. Update Resources/Info.plist first." >&2
  exit 1
fi
resolve_sparkle
check_update_key
mkdir -p build/releases
STAGING="$(mktemp -d "$PODSBAR_ROOT/build/releases/.prepare.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$STAGING/assets"
ASSETS="$STAGING/assets"

# Keep previously published items, including releases for older macOS versions.
HTTP_STATUS="$(curl --silent --show-error --location --max-time 30 --max-filesize 1048576 \
  --proto '=https' --proto-redir '=https' --output "$STAGING/previous.xml" --write-out '%{http_code}' "$FEED_URL")"
case "$HTTP_STATUS" in
  200)
    "$SPARKLE_TOOLS/sign_update" --account "$SPARKLE_ACCOUNT" --verify "$STAGING/previous.xml"
    python3 scripts/release_support.py check-previous "$STAGING/previous.xml" "$BUILD_NUMBER"
    ;;
  404) ;; # First Sparkle-enabled release.
  *) echo "Couldn't read the published feed (HTTP $HTTP_STATUS); refusing an unchecked release." >&2; exit 1 ;;
esac

VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" ./build.sh release universal
APP="$PODSBAR_ROOT/build/PodsBar.app"
if [[ "$SIGNING_MODE" == notarized ]]; then
ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGING/notarize.zip"
xcrun notarytool submit "$STAGING/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait \
  --output-format json > "$STAGING/notarization.json"
python3 - "$STAGING/notarization.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization was not accepted. Inspect the submission with notarytool log: ' + str(result.get('id')))
PY
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict "$APP"
spctl --assess --type execute "$APP"
fi

# EdDSA signs the final archive bytes. Never alter the ZIP after this step.
ARCHIVE="PodsBar-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ASSETS/$ARCHIVE"
if [[ "$SIGNING_MODE" == ad-hoc ]]; then
  printf '%s\n\n' '**Signing notice:** This build is ad-hoc signed and has not been notarized by Apple. macOS Gatekeeper may block the first launch. Its update archive and feed are signed with the PodsBar Sparkle key.' > "$ASSETS/release-notes.md"
  cat "$NOTES" >> "$ASSETS/release-notes.md"
else
  cp "$NOTES" "$ASSETS/release-notes.md"
fi
cp "$ASSETS/release-notes.md" "$ASSETS/PodsBar-$VERSION.md"
PREFIX="https://github.com/$REPOSITORY/releases/download/$TAG/"
"$SPARKLE_TOOLS/generate_appcast" --account "$SPARKLE_ACCOUNT" --maximum-deltas 0 \
  --download-url-prefix "$PREFIX" --embed-release-notes --link "https://github.com/$REPOSITORY" "$ASSETS"
if [[ "$HTTP_STATUS" == 200 ]]; then
  # generate_appcast drops entries without local archives. Merge the already verified
  # previous items back, preserving their immutable URLs, then sign the new feed bytes.
  python3 scripts/release_support.py merge-previous "$ASSETS/appcast.xml" "$STAGING/previous.xml"
fi
"$SPARKLE_TOOLS/sign_update" --account "$SPARKLE_ACCOUNT" "$ASSETS/appcast.xml"
"$SPARKLE_TOOLS/sign_update" --account "$SPARKLE_ACCOUNT" --verify "$ASSETS/appcast.xml"
python3 scripts/release_support.py verify "$ASSETS/appcast.xml" "$ASSETS/$ARCHIVE" \
  "$VERSION" "$BUILD_NUMBER" "$PREFIX$ARCHIVE" > "$ASSETS/release.json"
SIGNATURE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["signature"])' "$ASSETS/release.json")"
"$SPARKLE_TOOLS/sign_update" --account "$SPARKLE_ACCOUNT" --verify "$ASSETS/$ARCHIVE" "$SIGNATURE"
python3 - "$ASSETS/release.json" "$REPOSITORY" "$(git rev-parse HEAD)" "$SIGNING_MODE" <<'PY'
import json, sys
path, repository, commit, signing = sys.argv[1:]
with open(path) as source: data = json.load(source)
data.update(repository=repository, commit=commit, signing=signing)
with open(path, 'w') as output: json.dump(data, output, indent=2)
PY
(cd "$ASSETS" && shasum -a 256 "$ARCHIVE" appcast.xml release-notes.md release.json > SHA256SUMS)
mv "$ASSETS" "$DESTINATION"
echo "Prepared $DESTINATION"
echo "Review and test this build, then run: ./scripts/publish-release.sh $TAG"
