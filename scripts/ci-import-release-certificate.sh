#!/usr/bin/env bash
# Release workflow only: imports the release signing certificate (if the repository has one)
# into a temporary keychain and prints its identity for build-app.sh. Without the secrets the
# release is ad-hoc signed.
set -euo pipefail

if [ -z "${RELEASE_CERT_P12_BASE64:-}" ] || [ -z "${RELEASE_CERT_PASSWORD:-}" ]; then
  echo "No release certificate configured (see scripts/create-release-certificate.sh): ad-hoc signing." >&2
  echo "identity=" >> "$GITHUB_OUTPUT"
  exit 0
fi

NAME="Claw Copy Release Signing"
KEYCHAIN="$RUNNER_TEMP/release-signing.keychain-db"
KEYCHAIN_PASS="$(openssl rand -hex 24)"
umask 077

security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security set-keychain-settings -lut 1800 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"

printf '%s' "$RELEASE_CERT_P12_BASE64" | base64 --decode > "$RUNNER_TEMP/release.p12"
security import "$RUNNER_TEMP/release.p12" -k "$KEYCHAIN" -P "$RELEASE_CERT_PASSWORD" -T /usr/bin/codesign >/dev/null
rm -f "$RUNNER_TEMP/release.p12"
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null

# codesign looks for identities in the user's keychain search list.
existing=()
while IFS= read -r kc; do
  kc="${kc#"${kc%%[![:space:]]*}"}"; kc="${kc#\"}"; kc="${kc%\"}"
  [ -n "$kc" ] && existing+=("$kc")
done < <(security list-keychains -d user)
security list-keychains -d user -s "$KEYCHAIN" ${existing[@]+"${existing[@]}"}

# A self-signed certificate is its own root: trust it for code signing on this runner.
security find-certificate -c "$NAME" -p "$KEYCHAIN" > "$RUNNER_TEMP/release.pem"
sudo security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain "$RUNNER_TEMP/release.pem"

HASH="$(security find-identity -v -p codesigning "$KEYCHAIN" | awk -v name="\"$NAME\"" 'index($0, name) { print $2; exit }')"
if [ -z "$HASH" ]; then
  echo "The release certificate is not a valid code-signing identity." >&2
  exit 1
fi
echo "identity=$HASH" >> "$GITHUB_OUTPUT"
