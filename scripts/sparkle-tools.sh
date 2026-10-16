#!/bin/bash
# Shared paths; source this file from the release scripts.
PODSBAR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-com.amirmusa.podsbar.sparkle}"
SPARKLE_TOOLS="$PODSBAR_ROOT/.build/artifacts/sparkle/Sparkle/bin"

resolve_sparkle() {
  swift package --package-path "$PODSBAR_ROOT" resolve
  if [[ ! -x "$SPARKLE_TOOLS/generate_appcast" ]]; then
    echo "Sparkle's release tools are missing from the SwiftPM artifact." >&2
    exit 1
  fi
}

check_update_key() {
  local public_key configured_key
  if ! public_key="$("$SPARKLE_TOOLS/generate_keys" --account "$SPARKLE_ACCOUNT" -p)"; then
    echo "Restore this app's existing update key from your secure backup. See docs/updates.md; do not generate a replacement for an already published app." >&2
    exit 1
  fi
  configured_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PODSBAR_ROOT/Resources/Info.plist")"
  if [[ "$public_key" != "$configured_key" ]]; then
    echo "The Keychain signing key does not match Resources/Info.plist. Do not rotate a published key accidentally." >&2
    exit 1
  fi
}
