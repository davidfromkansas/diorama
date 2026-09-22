#!/bin/bash
# Embed the SDK and a Node runtime; Claude Code remains user-installed and owns authentication.
set -euo pipefail
app=${1:?Usage: package-claude-helper.sh APP_PATH}
root=$(cd "$(dirname "$0")/.." && pwd)
node_binary=${DIORAMA_NODE:-$(command -v node)}
[[ -x "$node_binary" ]] || { echo 'Node runtime missing' >&2; exit 1; }
npm ci --prefix "$root/helpers/claude" --ignore-scripts --omit=optional --no-audit --no-fund
output="$app/Contents/Resources/ClaudeHelper"
mkdir -p "$output"
cp "$root"/helpers/claude/{index,bridge,history,history-format}.mjs "$output/"
cp "$root/helpers/claude/package.json" "$output/"
/usr/bin/ditto "$root/helpers/claude/node_modules" "$output/node_modules"
# Thin universal development Node to the app architecture when possible.
archs=$(/usr/bin/lipo -archs "$app/Contents/MacOS/Diorama")
node_archs=$(/usr/bin/lipo -archs "$node_binary")
if [[ "$archs" != *' '* && "$node_archs" == *' '* ]]; then
  /usr/bin/lipo "$node_binary" -thin "$archs" -output "$output/node"
else
  cp "$node_binary" "$output/node"
fi
chmod 755 "$output/node"
node_version=$("$node_binary" --version)
curl --fail --silent --show-error --location "https://raw.githubusercontent.com/nodejs/node/$node_version/LICENSE" -o "$output/Node-LICENSE.txt"
"$output/node" --version
# Node's JIT needs these entitlements under hardened runtime.
cat > "$output/node-entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.cs.allow-jit</key><true/></dict></plist>
PLIST
codesign --force --sign - --entitlements "$output/node-entitlements.plist" "$output/node"
