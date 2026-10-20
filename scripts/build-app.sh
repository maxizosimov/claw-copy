#!/usr/bin/env bash
# Builds build/Claw Copy.app from the Swift package and code-signs it with the hardened runtime.
#
#   ./scripts/build-app.sh                         # local certificate if set up, else ad-hoc
#   SIGN_IDENTITY="Developer ID Application: …" ./scripts/build-app.sh
#
# Used by the release workflow (all optional):
#   VERSION=0.1.42 BUILD_NUMBER=42   version shown to users and compared by the update check
#   RELEASE=1                        marks a release build (only those check for updates)
#   UNIVERSAL=1                      builds for both Apple silicon and Intel
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

BUILD_ARGS=(-c "$CONFIG")
if [ "${UNIVERSAL:-0}" = 1 ]; then
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

rm -rf "$APP"
# Never leave a half-built (unsigned) app behind if any later step fails.
trap 'rm -rf "$APP"' ERR
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/ClawCopy" "$APP/Contents/MacOS/ClawCopy"
cp Support/Info.plist "$APP/Contents/Info.plist"

PLIST="$APP/Contents/Info.plist"
COMMIT="$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
/usr/libexec/PlistBuddy -c "Add :ClawCopyCommit string $COMMIT" "$PLIST"
if [ -n "${VERSION:-}" ]; then
  [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,3}$ ]] || { echo "Invalid VERSION: $VERSION" >&2; false; }
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
fi
if [ -n "${BUILD_NUMBER:-}" ]; then
  [[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "Invalid BUILD_NUMBER: $BUILD_NUMBER" >&2; false; }
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
fi
if [ "${RELEASE:-0}" = 1 ]; then
  /usr/libexec/PlistBuddy -c "Add :ClawCopyReleaseBuild bool true" "$PLIST"
fi

# Hardened runtime, no entitlements: the app requests no network, camera, files, etc.
if [ "$USE_LOCAL_KEYCHAIN" = 1 ]; then
  # The signing keychain is unlocked only for this one signature.
  echo "Unlock the Claw Copy signing keychain to sign the app:"
  security unlock-keychain "$LOCAL_KEYCHAIN"
  # codesign only finds identities in keychains on the user's search list, so add the signing
  # keychain for this one signature and restore the original list (and lock it) afterwards.
  ORIGINAL_KEYCHAINS=()
  while IFS= read -r kc; do
    kc="${kc#"${kc%%[![:space:]]*}"}"; kc="${kc#\"}"; kc="${kc%\"}"
    [ -n "$kc" ] && [ "$kc" != "$LOCAL_KEYCHAIN" ] && ORIGINAL_KEYCHAINS+=("$kc")
  done < <(security list-keychains -d user)
  restore_keychains() {
    security list-keychains -d user -s ${ORIGINAL_KEYCHAINS[@]+"${ORIGINAL_KEYCHAINS[@]}"}
    security lock-keychain "$LOCAL_KEYCHAIN"
  }
  trap restore_keychains EXIT
  security list-keychains -d user -s "$LOCAL_KEYCHAIN" ${ORIGINAL_KEYCHAINS[@]+"${ORIGINAL_KEYCHAINS[@]}"}
  # Sign by the certificate's SHA-1 so codesign uses exactly this certificate in this keychain.
  CERT_HASH="$(security find-identity -v -p codesigning "$LOCAL_KEYCHAIN" \
    | awk -v name="\"$LOCAL_IDENTITY\"" 'index($0, name) { print $2; exit }')"
  if [ -z "$CERT_HASH" ]; then
    echo "Error: \"$LOCAL_IDENTITY\" is not a valid (trusted) code-signing identity." >&2
    echo "       Run ./scripts/create-signing-identity.sh to finish setting it up." >&2
    false
  fi
  codesign --force --options runtime --timestamp=none --keychain "$LOCAL_KEYCHAIN" \
    --sign "$CERT_HASH" "$APP"
else
  codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

echo "Built $APP (signed with: $SIGN_IDENTITY)"
