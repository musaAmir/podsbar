#!/bin/bash
# Verify this Mac has the configured release key. Never create or rotate it implicitly.
set -euo pipefail
source "$(dirname "$0")/sparkle-tools.sh"
resolve_sparkle
check_update_key
echo "The update key is ready in Keychain (account: $SPARKLE_ACCOUNT)."
echo "Only SUPublicEDKey belongs in the repository. Keep a secure backup of the private key."
