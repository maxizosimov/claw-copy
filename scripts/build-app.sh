#!/usr/bin/env bash
# Builds build/Claw Copy.app from the Swift package and code-signs it with the hardened runtime.
#
#   ./scripts/build-app.sh                         # ad-hoc signature (local use)
#   SIGN_IDENTITY="Developer ID Application: …" ./scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/Claw Copy.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/ClawCopy" "$APP/Contents/MacOS/ClawCopy"
cp Support/Info.plist "$APP/Contents/Info.plist"

# Hardened runtime, no entitlements: the app requests no network, camera, files, etc.
codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "Built $APP"
