#!/bin/bash
# Verify the actual notarized installer, not just the original build directory.
set -euo pipefail
image=${1:?Usage: verify-release.sh DMG_PATH}
hdiutil verify "$image"
xcrun stapler validate "$image"
spctl --assess --type open --context context:primary-signature --verbose=2 "$image"
mount_dir=$(mktemp -d /tmp/diorama-verify.XXXXXX)
mounted=0
cleanup() {
  if [[ "$mounted" == 1 ]]; then hdiutil detach "$mount_dir"; fi
  rmdir "$mount_dir"
}
trap cleanup EXIT
hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$image"
mounted=1
app="$mount_dir/Diorama.app"
codesign --verify --deep --strict "$app"
spctl --assess --type execute --verbose=2 "$app"
codesign --display --verbose=2 "$app"
test "$(readlink "$mount_dir/Applications")" = /Applications
test "$(lipo -archs "$app/Contents/MacOS/Diorama")" = arm64
test "$(lipo -archs "$app/Contents/Resources/ClaudeHelper/node")" = arm64
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist"
"$app/Contents/Resources/ClaudeHelper/node" --version
