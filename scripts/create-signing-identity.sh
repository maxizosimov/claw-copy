#!/usr/bin/env bash
# One-time setup: creates a self-signed code-signing certificate, "Claw Copy Local Signing",
# in its own keychain. build-app.sh uses it automatically when it exists.
#
#   ./scripts/create-signing-identity.sh            # create it
#   ./scripts/create-signing-identity.sh --remove   # delete it and its trust setting
#
# Why: an ad-hoc signature changes on every rebuild, so macOS treats each build as a new app
# and forgets its Accessibility permission. Signing with a fixed certificate keeps the app's
# identity stable, so the permission survives rebuilds.
#
# Hardening:
# - The private key is created on this Mac, imported as non-extractable, and never leaves it.
# - It lives in a dedicated keychain with its own password, which stays locked except for the
#   moment build-app.sh signs (it asks for that password). Nothing can sign silently as Claw Copy.
# - The certificate is trusted for code signing only, for your user account only.
set -euo pipefail

NAME="Claw Copy Local Signing"
KEYCHAIN="$HOME/Library/Keychains/claw-copy-signing.keychain-db"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# Apple's bundled LibreSSL: its .p12 files import cleanly with `security` (Homebrew OpenSSL 3's don't).
OPENSSL=/usr/bin/openssl

umask 077
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Deletes the identity (certificate + private key) and its trust setting from one keychain.
remove_from() {
  local keychain="$1"
  [ -e "$keychain" ] || return 0
  if security find-certificate -c "$NAME" -p "$keychain" > "$WORK/old.pem" 2>/dev/null; then
    security remove-trusted-cert "$WORK/old.pem" 2>/dev/null || true
    security delete-identity -c "$NAME" "$keychain" >/dev/null
    echo "Removed \"$NAME\" from $keychain"
  fi
}

if [ "${1:-}" = "--remove" ]; then
  remove_from "$LOGIN_KEYCHAIN"
  if [ -e "$KEYCHAIN" ]; then
    security delete-keychain "$KEYCHAIN"
    echo "Deleted $KEYCHAIN"
  fi
  echo "Done. Builds are ad-hoc signed again until you re-run this script."
  exit 0
fi

# Trusts the certificate for code signing only, for this user only (asks for the Mac password).
# A self-signed certificate is its own root, so it must be trusted as "trustRoot";
# "trustAsRoot" is only valid for certificates issued by someone else.
trust_cert() {
  echo "macOS will now ask for your Mac password to trust the certificate for code signing."
  security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$1"
}

is_valid_identity() {
  security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "\"$NAME\""
}

if [ -e "$KEYCHAIN" ] && security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  if is_valid_identity; then
    echo "\"$NAME\" already exists in $KEYCHAIN and is trusted for code signing. Nothing to do."
    echo "(Run with --remove first to replace it.)"
    exit 0
  fi
  # Created earlier but never trusted (e.g. an interrupted run): finish the setup.
  echo "\"$NAME\" exists but is not trusted for code signing yet. Fixing that."
  security find-certificate -c "$NAME" -p "$KEYCHAIN" > "$WORK/cert.pem"
  trust_cert "$WORK/cert.pem"
  security lock-keychain "$KEYCHAIN"
  is_valid_identity || { echo "Error: the certificate is still not a valid code-signing identity." >&2; exit 1; }
  echo "Done. Run ./scripts/build-app.sh to build with it."
  exit 0
fi

# An earlier version of this script kept the identity in the login keychain. Move off it.
remove_from "$LOGIN_KEYCHAIN"

echo "Choose a password for the Claw Copy signing keychain. build-app.sh asks for it on every build."
if [ -e "$KEYCHAIN" ]; then
  security unlock-keychain "$KEYCHAIN"
else
  security create-keychain "$KEYCHAIN"   # asks for the new password (twice); leaves it unlocked
fi
# Lock on sleep and after 5 minutes, as a backstop to build-app.sh locking it right after signing.
security set-keychain-settings -l -u -t 300 "$KEYCHAIN"

cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CNF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
  -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

PASS="$("$OPENSSL" rand -hex 16)"
"$OPENSSL" pkcs12 -export -name "$NAME" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/identity.p12" -passout "pass:$PASS"

# -x: the private key can't be exported again. -T: codesign may use it (while unlocked).
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" -x -T /usr/bin/codesign

trust_cert "$WORK/cert.pem"

security lock-keychain "$KEYCHAIN"
is_valid_identity || { echo "Error: the certificate is not a valid code-signing identity." >&2; exit 1; }
echo "Created \"$NAME\" in $KEYCHAIN (locked). Run ./scripts/build-app.sh to build with it."
