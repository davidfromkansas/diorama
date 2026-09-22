#!/bin/zsh
set -eu
cd "${0:A:h}"
build_path="${DIORAMA_BUILD_PATH:-$PWD/.build}"
swift build -c release --scratch-path "$build_path"
app_path="${DIORAMA_APP_PATH:-$PWD/dist/Diorama.app}"
mkdir -p "$app_path/Contents/MacOS"
cp "$build_path/release/Diorama" "$app_path/Contents/MacOS/Diorama"
cp "$build_path/release/DioramaReporter" "$app_path/Contents/MacOS/DioramaReporter"
codesign --force --sign - "$app_path/Contents/MacOS/DioramaReporter"
./scripts/package-claude-helper.sh "$app_path"
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
<key>CFBundleShortVersionString</key><string>0.6.0</string>
<key>CFBundleVersion</key><string>43</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Generated bundles inside synced folders can acquire Finder/file-provider metadata.
# Strip extended attributes from this build output before signing (never source files).
xattr -cr "$app_path"
codesign --force --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
echo "$app_path"
