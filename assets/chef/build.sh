#!/bin/sh
# Rebuild the chef runtime assets from the untouched source GLB, verify them, and optionally render review sheets.
#   assets/chef/build.sh [path/to/source.glb]      RENDER=0 skips the review renders.
set -e
CHEF=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$CHEF/../.." && pwd)
SRC=${1:-$CHEF/source/Meshy_AI_Tiny_Chef_Mascot_1004162827_texture.glb}
BLENDER=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
OUT=$ROOT/.local/chef-build
RES=$ROOT/Sources/DioramaApp/Resources/Chef
"$BLENDER" -b --factory-startup -P "$CHEF/blender/build_chef.py" -- "$SRC" "$OUT"
mkdir -p "$RES"
cp "$OUT/chef-rigged.blend" "$CHEF/"
cp "$OUT/chef-animated.glb" "$OUT/chef-props.glb" "$OUT/chef-manifest.json" "$RES/"
(cd "$CHEF/verify" && { [ -d node_modules ] || npm install --silent --no-audit --no-fund; } && npm run -s verify:glb)
if [ "$RENDER" != "0" ]; then
  rm -rf "$OUT/renders"
  "$BLENDER" -b "$OUT/chef-rigged.blend" -P "$CHEF/blender/render_clips.py" -- "$OUT/chef-manifest.json" "$OUT/renders"
  python3 "$CHEF/blender/sheets.py" "$OUT/renders"
  mkdir -p "$ROOT/docs/chef/clip-sheets"
  python3 - "$OUT/renders" "$ROOT/docs/chef/clip-sheets" <<'PY'
import glob, os, sys
from PIL import Image
for f in glob.glob(os.path.join(sys.argv[1], "sheet_*.png")):
    im = Image.open(f).convert("RGB"); s = min(1.0, 1400 / im.width)
    im.resize((int(im.width * s), int(im.height * s))).save(os.path.join(sys.argv[2], os.path.basename(f)[:-4] + ".jpg"), quality=82)
PY
fi
