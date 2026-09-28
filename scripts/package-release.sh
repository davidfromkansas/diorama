#!/bin/bash
# Package an already built app. Never modifies the original app or publishes.
set -euo pipefail
if [[ $# -ne 2 ]]; then echo "Usage: $0 APP_PATH OUTPUT_DIRECTORY" >&2; exit 2; fi
if [[ "${DIORAMA_REQUIRE_NOTARIZATION:-0}" == 1 ]]; then
  : "${DIORAMA_SIGN_IDENTITY:?Developer ID signing is required}"
  : "${DIORAMA_NOTARY_PROFILE:?Notarization is required}"
fi
signing_args=()
if [[ -n "${DIORAMA_SIGN_KEYCHAIN:-}" ]]; then signing_args=(--keychain "$DIORAMA_SIGN_KEYCHAIN"); fi
notary_args=()
if [[ -n "${DIORAMA_NOTARY_KEYCHAIN:-}" ]]; then notary_args=(--keychain "$DIORAMA_NOTARY_KEYCHAIN"); fi
app_path="$1"
output_dir="$2"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")
archs=$(/usr/bin/lipo -archs "$app_path/Contents/MacOS/Diorama")
case "$archs" in arm64) arch=arm64;; x86_64) arch=x86_64;; *) arch=universal;; esac
image="$output_dir/Diorama-${version}-${build}-${arch}.dmg"
[[ ! -e "$image" ]] || { echo "Refusing to overwrite $image" >&2; exit 1; }
stage=$(mktemp -d /tmp/diorama-release.XXXXXX)
trap 'rm -rf "$stage"' EXIT
/usr/bin/ditto "$app_path" "$stage/Diorama.app"
xattr -cr "$stage/Diorama.app"
if [[ -n "${DIORAMA_SIGN_IDENTITY:-}" ]]; then
  if [[ -f "$stage/Diorama.app/Contents/Resources/ClaudeHelper/node" ]]; then
    codesign ${signing_args[@]+"${signing_args[@]}"} --force --options runtime --timestamp --entitlements "$stage/Diorama.app/Contents/Resources/ClaudeHelper/node-entitlements.plist" --sign "$DIORAMA_SIGN_IDENTITY" "$stage/Diorama.app/Contents/Resources/ClaudeHelper/node"
  fi
  codesign ${signing_args[@]+"${signing_args[@]}"} --force --options runtime --timestamp --sign "$DIORAMA_SIGN_IDENTITY" "$stage/Diorama.app/Contents/MacOS/DioramaReporter"
  codesign ${signing_args[@]+"${signing_args[@]}"} --force --options runtime --timestamp --sign "$DIORAMA_SIGN_IDENTITY" "$stage/Diorama.app"
fi
codesign --verify --deep --strict "$stage/Diorama.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname Diorama -srcfolder "$stage" -ov -format UDZO "$image"
if [[ -n "${DIORAMA_SIGN_IDENTITY:-}" ]]; then
  codesign ${signing_args[@]+"${signing_args[@]}"} --timestamp --sign "$DIORAMA_SIGN_IDENTITY" "$image"
fi
if [[ -n "${DIORAMA_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$image" --keychain-profile "$DIORAMA_NOTARY_PROFILE" ${notary_args[@]+"${notary_args[@]}"} --wait
  xcrun stapler staple "$image"
  xcrun stapler validate "$image"
fi
hdiutil verify "$image"
(cd "$output_dir" && shasum -a 256 "$(basename "$image")" > "$(basename "$image").sha256")
echo "$image"
