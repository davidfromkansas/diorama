#!/bin/zsh
# Standalone entry point into the production workspace scene, without loading agent sessions.
set -eu
cd "${0:A:h:h}"
lab_build_path="${DIORAMA_CAPYBARA_BUILD_PATH:-/tmp/diorama-capybara-build}"
lab_app_path="$PWD/dist/Diorama Capybara Lab.app"
swift build --scratch-path "$lab_build_path"
mkdir -p "$lab_app_path/Contents/MacOS" "$lab_app_path/Contents/Resources"
cp "$lab_build_path/debug/Diorama" "$lab_app_path/Contents/MacOS/Diorama"
/usr/bin/ditto "$lab_build_path/debug/Diorama_DioramaApp.bundle" "$lab_app_path/Contents/Resources/Diorama_DioramaApp.bundle"
cat > "$lab_app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Diorama</string>
<key>CFBundleIdentifier</key><string>local.diorama.capybara-lab</string>
<key>CFBundleName</key><string>Diorama Capybara Lab</string>
<key>CFBundleDisplayName</key><string>Diorama Capybara Lab</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>DioramaMovementLab</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$lab_app_path"
echo "$lab_app_path"
