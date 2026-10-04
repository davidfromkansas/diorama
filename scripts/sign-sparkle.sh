#!/bin/bash
# Sign nested Sparkle executables inside-out, preserving framework symlinks.
set -euo pipefail
app=${1:?App path required}
identity=${2:?Signing identity required}
framework="$app/Contents/Frameworks/Sparkle.framework"
args=(--force --sign "$identity")
if [[ "$identity" != - ]]; then
  args+=(--options runtime --timestamp)
  if [[ -n "${DIORAMA_SIGN_KEYCHAIN:-}" ]]; then args+=(--keychain "$DIORAMA_SIGN_KEYCHAIN"); fi
fi
for part in Autoupdate XPCServices/Downloader.xpc XPCServices/Installer.xpc Updater.app; do
  codesign "${args[@]}" "$framework/Versions/B/$part"
done
codesign "${args[@]}" "$framework"
codesign --verify --deep --strict "$framework"
