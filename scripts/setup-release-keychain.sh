#!/bin/bash
# CI only: import encrypted GitHub secrets into an ephemeral Keychain.
set -euo pipefail
: "${RUNNER_TEMP:?}" "${GITHUB_ENV:?}" "${MAC_CSC_LINK:?}" "${MAC_CSC_KEY_PASSWORD:?}"
: "${APPLE_API_KEY_BASE64:?}" "${APPLE_API_KEY_ID:?}" "${APPLE_API_ISSUER:?}"
umask 077
keychain="$RUNNER_TEMP/diorama-signing.keychain-db"
certificate="$RUNNER_TEMP/diorama-signing.p12"
notary_key="$RUNNER_TEMP/diorama-notary.p8"
password=$(openssl rand -hex 32)
echo "::add-mask::$password"
trap 'rm -f "$certificate" "$notary_key"' EXIT
printf '%s' "$MAC_CSC_LINK" | base64 --decode > "$certificate"
printf '%s' "$APPLE_API_KEY_BASE64" | base64 --decode > "$notary_key"
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$certificate" -k "$keychain" -P "$MAC_CSC_KEY_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
# A fresh runner may not have the Developer ID G2 intermediate cached.
curl --fail --silent --show-error --location https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer -o "$RUNNER_TEMP/diorama-intermediate.cer"
echo 'f16cd3c54c7f83cea4bf1a3e6a0819c8aaa8e4a1528fd144715f350643d2df3a  '"$RUNNER_TEMP/diorama-intermediate.cer" | shasum -a 256 -c -
security import "$RUNNER_TEMP/diorama-intermediate.cer" -k "$keychain" >/dev/null
# Trust evaluation needs the intermediate in the runner's Keychain search list.
python3 - "$keychain" <<'PY_KEYCHAIN'
import shlex, subprocess, sys
current = shlex.split(subprocess.check_output(['security', 'list-keychains', '-d', 'user'], text=True))
subprocess.run(['security', 'list-keychains', '-d', 'user', '-s', sys.argv[1], *current], check=True)
PY_KEYCHAIN
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
identity=$(security find-identity -v -p codesigning "$keychain" | sed -n '/Developer ID Application:/s/.*) \([A-F0-9]*\) .*/\1/p')
[[ "$identity" =~ ^[A-F0-9]{40}$ ]] || { echo 'Expected exactly one valid Developer ID Application identity' >&2; exit 1; }
xcrun notarytool store-credentials diorama-release --keychain "$keychain" --key "$notary_key" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER"
{
  echo "DIORAMA_SIGN_IDENTITY=$identity"
  echo "DIORAMA_SIGN_KEYCHAIN=$keychain"
  echo "DIORAMA_NOTARY_PROFILE=diorama-release"
  echo "DIORAMA_NOTARY_KEYCHAIN=$keychain"
} >> "$GITHUB_ENV"
