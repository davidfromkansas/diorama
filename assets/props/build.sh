#!/bin/sh
# Optimize every kitchen prop source (or the ids given) into the app's KitchenProps resources,
# with the food pipeline's script (centred, base at 0, widest side 1.0).
#   assets/props/build.sh [id ...]      FACES=15000 TEXTURE=1024 by default.
set -e
PROPS=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$PROPS/../.." && pwd)
BLENDER=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
OUT=$ROOT/Sources/DioramaApp/Resources/KitchenProps
FACES=${FACES:-15000}
TEXTURE=${TEXTURE:-1024}
mkdir -p "$OUT"
if [ $# -eq 0 ]; then set -- $(cd "$PROPS/source" && ls *.glb | sed 's/\.glb$//'); fi
for id in "$@"; do
  "$BLENDER" -b --factory-startup -P "$ROOT/assets/food/optimize_food.py" -- "$PROPS/source/$id.glb" "$OUT/$id.glb" "$FACES" "$TEXTURE" 2>&1 | grep '^FOOD' || { echo "failed: $id" >&2; exit 1; }
  echo "  $(du -h "$PROPS/source/$id.glb" | cut -f1) -> $(du -h "$OUT/$id.glb" | cut -f1)"
done
