#!/usr/bin/env bash
# One-time setup: creates a self-signed code-signing certificate, "Claw Copy Local Signing",
# in your login keychain. build-app.sh uses it automatically when it exists.
#
# Why: an ad-hoc signature changes on every rebuild, so macOS treats each build as a new app
# and forgets its Accessibility permission. Signing with a fixed certificate keeps the app's
# identity stable, so the permission survives rebuilds.
#
# The private key is created on this Mac, imported as non-extractable, and never leaves it.
# The certificate is trusted for code signing only, for your user account only.
set -euo pipefail

NAME="Claw Copy Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# Apple's bundled LibreSSL: its .p12 files import cleanly with `security` (Homebrew OpenSSL 3's don't).
OPENSSL=/usr/bin/openssl

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "\"$NAME\" already exists in your login keychain. Nothing to do."
  exit 0
fi

umask 077
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

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

# -x: the private key can't be exported again. -T: codesign may use it.
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" -x -T /usr/bin/codesign

echo "macOS will now ask for your password to trust the certificate for code signing."
security add-trusted-cert -r trustAsRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo "Created \"$NAME\". Run ./scripts/build-app.sh to build with it."
