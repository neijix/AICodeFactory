#!/bin/bash
# Re-sign a locally-built .app with a stable self-signed identity, in the order
# and with the flags that actually let it launch.
#
# Usage:
#   bash scripts/sign-app.sh <path/to/App.app> <identity-name> <bundle-identifier>
#
# Example:
#   IDENTITY="$(bash scripts/ensure-signing-identity.sh)"
#   bash scripts/sign-app.sh build/Debug/MyApp.app "$IDENTITY" com.example.myapp
#
# Two flags are deliberately NOT used, because each one silently breaks launch:
#
#   --deep          combined with --identifier it stamps the app's bundle id
#                   onto nested dylibs (Xcode 16+ Swift Debug builds emit
#                   <App>.debug.dylib in Contents/MacOS/). dyld then refuses the
#                   mismatched pairing and the app dies instantly at launch.
#                   Apple deprecated --deep for signing anyway.
#
#   --options runtime
#                   the hardened runtime enables library validation, which
#                   demands every loaded library share the process's Team ID. A
#                   self-signed cert has no Team ID, so the dylib is rejected —
#                   same instant death, same misleading dyld message. Hardened
#                   runtime only matters for notarised distribution.
set -euo pipefail

APP="${1:?usage: sign-app.sh <App.app> <identity> <bundle-id>}"
IDENTITY="${2:?usage: sign-app.sh <App.app> <identity> <bundle-id>}"
BUNDLE_ID="${3:?usage: sign-app.sh <App.app> <identity> <bundle-id>}"

[ -d "$APP" ] || { echo "No such app bundle: $APP" >&2; exit 1; }

# 1. Nested Mach-O first, each keeping its OWN identifier (no --identifier here).
while IFS= read -r macho; do
    codesign --sign "$IDENTITY" --force "$macho"
done < <(find "$APP/Contents" -type f -name '*.dylib')

# 2. The bundle last, carrying the stable identifier that TCC keys its grants on.
codesign --sign "$IDENTITY" --identifier "$BUNDLE_ID" --force "$APP"

# 3. Verify. Necessary but NOT sufficient — this passes even when the nested
#    dylib pairing is broken, so still launch the app to confirm.
codesign --verify --deep --strict "$APP"

echo "Signed $APP as '$IDENTITY' ($BUNDLE_ID)."
