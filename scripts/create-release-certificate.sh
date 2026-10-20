#!/usr/bin/env bash
# One-time setup (optional): creates the self-signed certificate that GitHub Actions uses to
# sign releases, and stores it as two repository secrets.
#
#   ./scripts/create-release-certificate.sh
#
# Why: without an Apple Developer ID, every release would otherwise be ad-hoc signed, and macOS
# would treat each update as a new app and ask users to grant Accessibility again. Signing every
# release with the same certificate keeps the app's identity stable, so the permission survives
# updates. (Users still see macOS's "unidentified developer" warning once at install; only Apple
# notarization, which needs a paid Developer ID, removes that.)
#
# The private key only ever exists in a temporary folder here (deleted on exit) and in the
# encrypted GitHub secrets. Anyone who can push to main can already ship a release, so the
# secret doesn't widen who can publish. Re-running replaces the certificate; users then grant
# Accessibility once more.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Claw Copy Release Signing"
OPENSSL=/usr/bin/openssl

command -v gh >/dev/null || { echo "Install the GitHub CLI first: brew install gh, then gh auth login." >&2; exit 1; }

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

"$OPENSSL" req -x509 -newkey rsa:3072 -nodes -days 3650 -sha256 \
  -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
PASS="$("$OPENSSL" rand -hex 24)"
"$OPENSSL" pkcs12 -export -name "$NAME" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/release.p12" -passout "pass:$PASS"

base64 < "$WORK/release.p12" | tr -d '\n' | gh secret set RELEASE_CERT_P12_BASE64
printf '%s' "$PASS" | gh secret set RELEASE_CERT_PASSWORD

echo "Saved the release signing certificate as the RELEASE_CERT_P12_BASE64 and"
echo "RELEASE_CERT_PASSWORD secrets of $(gh repo view --json nameWithOwner -q .nameWithOwner)."
echo "The next release (next merge to main) is signed with it."
