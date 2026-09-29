#!/bin/zsh
set -eu
cd "${0:A:h}"
build_path="${DIORAMA_BUILD_PATH:-$PWD/.build}"
configuration="${DIORAMA_BUILD_CONFIGURATION:-release}"
[[ "$configuration" == "debug" || "$configuration" == "release" ]] || { echo "Invalid build configuration" >&2; exit 1; }
swift build -c "$configuration" --scratch-path "$build_path"
app_path="${DIORAMA_APP_PATH:-$PWD/dist/Diorama.app}"
mkdir -p "$app_path/Contents/MacOS"
cp "$build_path/$configuration/Diorama" "$app_path/Contents/MacOS/Diorama"
cp "$build_path/$configuration/DioramaReporter" "$app_path/Contents/MacOS/DioramaReporter"
codesign --force --sign - "$app_path/Contents/MacOS/DioramaReporter"
mkdir -p "$app_path/Contents/Resources"
for resource_bundle in "$build_path/$configuration/"*.bundle(N); do
  /usr/bin/ditto "$resource_bundle" "$app_path/Contents/Resources/${resource_bundle:t}"
done
helper_source="${DIORAMA_REUSE_HELPER_FROM:-}"
helper_stamp=$(shasum helpers/claude/{index,bridge,history,history-format}.mjs helpers/claude/package{,-lock}.json scripts/package-claude-helper.sh)
if [[ -n "$helper_source" && -x "$helper_source/node" && -f "$helper_source/source.sha1" &&
      "$(cat "$helper_source/source.sha1")" == "$helper_stamp" ]]; then
  /usr/bin/ditto "$helper_source" "$app_path/Contents/Resources/ClaudeHelper"
else
  ./scripts/package-claude-helper.sh "$app_path"
fi
printf '%s\n' "$helper_stamp" > "$app_path/Contents/Resources/ClaudeHelper/source.sha1"
mkdir -p "$app_path/Contents/Resources/Licenses"
cp -f "$build_path/checkouts/swift-markdown-ui/LICENSE" "$app_path/Contents/Resources/Licenses/MarkdownUI.txt"
cp -f "$build_path/checkouts/NetworkImage/LICENSE" "$app_path/Contents/Resources/Licenses/NetworkImage.txt"
cp -f "$build_path/checkouts/swift-cmark/COPYING" "$app_path/Contents/Resources/Licenses/swift-cmark.txt"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Diorama</string>
<key>CFBundleIdentifier</key><string>local.diorama.prototype</string>
<key>CFBundleName</key><string>Diorama</string>
<key>CFBundleDisplayName</key><string>Diorama</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.8.2</string>
<key>CFBundleVersion</key><string>53</string>
<key>DioramaGitHubClientID</key><string>Ov23liN3O8j2ksYfPj0j</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Opt-in source watching is restricted to this local development build.
if [[ -n "${DIORAMA_DEVELOPMENT_ROOT:-}" ]]; then
  printf '%s\n' "$DIORAMA_DEVELOPMENT_ROOT" > "$app_path/Contents/Resources/DevelopmentRoot.txt"
  touch "$app_path/Contents/Resources/DevelopmentBuildDate.txt"
else
  rm -f "$app_path/Contents/Resources/DevelopmentRoot.txt" "$app_path/Contents/Resources/DevelopmentBuildDate.txt"
fi
# Generated bundles inside synced folders can acquire Finder/file-provider metadata.
# Strip extended attributes from this build output before signing (never source files).
xattr -cr "$app_path"
codesign --force --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
echo "$app_path"
