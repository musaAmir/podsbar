#!/bin/bash
# Uploads a prepared release as a GitHub draft. Publishing is a separate review step.
set -euo pipefail
source "$(dirname "$0")/sparkle-tools.sh"
if [[ $# != 1 || ! "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 vVERSION" >&2
  exit 2
fi
TAG="$1"
DIRECTORY="$PODSBAR_ROOT/build/releases/$TAG"
(cd "$DIRECTORY" && shasum -a 256 -c SHA256SUMS)
read_manifest() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$DIRECTORY/release.json" "$1"; }
REPOSITORY="$(read_manifest repository)"
COMMIT="$(read_manifest commit)"
VERSION="$(read_manifest version)"
ARCHIVE="$(read_manifest archive)"
if [[ "$TAG" != "v$VERSION" || "$ARCHIVE" != "PodsBar-$VERSION.zip" ]]; then
  echo "The release directory does not match its metadata." >&2
  exit 1
fi
EXISTING_TAG="$(git ls-remote --tags "https://github.com/$REPOSITORY.git" "refs/tags/$TAG" "refs/tags/$TAG^{}")"
if [[ -n "$EXISTING_TAG" ]]; then
  echo "Tag $TAG already exists. Choose a new version so the tag and shipped source cannot diverge." >&2
  exit 1
fi
resolve_sparkle
check_update_key
"$SPARKLE_TOOLS/sign_update" --account "$SPARKLE_ACCOUNT" --verify "$DIRECTORY/appcast.xml"
"$SPARKLE_TOOLS/sign_update" --account "$SPARKLE_ACCOUNT" --verify "$DIRECTORY/$ARCHIVE" "$(read_manifest signature)"
gh release create "$TAG" --repo "$REPOSITORY" --target "$COMMIT" --draft \
  --title "PodsBar $VERSION" --notes-file "$DIRECTORY/release-notes.md" \
  "$DIRECTORY/$ARCHIVE" "$DIRECTORY/appcast.xml" "$DIRECTORY/SHA256SUMS" \
  "$DIRECTORY/release.json" "$DIRECTORY/release-notes.md"
echo "Review the draft in GitHub and publish it as the latest stable release to enable updates."
