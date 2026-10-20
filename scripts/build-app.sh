#!/usr/bin/env bash
# Builds build/Claw Copy.app from the Swift package and code-signs it with the hardened runtime.
#
#   ./scripts/build-app.sh                         # local certificate if set up, else ad-hoc
#   SIGN_IDENTITY="Developer ID Application: …" ./scripts/build-app.sh
#
# Run ./scripts/create-signing-identity.sh once so macOS keeps the Accessibility permission
# across rebuilds (an ad-hoc signature changes every build).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
LOCAL_IDENTITY="Claw Copy Local Signing"
LOCAL_KEYCHAIN="$HOME/Library/Keychains/claw-copy-signing.keychain-db"
USE_LOCAL_KEYCHAIN=0
if [ -z "${SIGN_IDENTITY:-}" ]; then
  if [ -e "$LOCAL_KEYCHAIN" ]; then
    SIGN_IDENTITY="$LOCAL_IDENTITY"
    USE_LOCAL_KEYCHAIN=1
  else
    SIGN_IDENTITY="-"
    echo "Note: ad-hoc signing. macOS will forget the Accessibility permission on every rebuild." >&2
    echo "      Run ./scripts/create-signing-identity.sh once to fix that." >&2
  fi
fi
APP="build/Claw Copy.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/ClawCopy" "$APP/Contents/MacOS/ClawCopy"
cp Support/Info.plist "$APP/Contents/Info.plist"

# Hardened runtime, no entitlements: the app requests no network, camera, files, etc.
if [ "$USE_LOCAL_KEYCHAIN" = 1 ]; then
  # The signing keychain is unlocked only for this one signature.
  echo "Unlock the Claw Copy signing keychain to sign the app:"
  security unlock-keychain "$LOCAL_KEYCHAIN"
  trap 'security lock-keychain "$LOCAL_KEYCHAIN"' EXIT
  codesign --force --options runtime --timestamp=none --keychain "$LOCAL_KEYCHAIN" \
    --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

echo "Built $APP (signed with: $SIGN_IDENTITY)"
