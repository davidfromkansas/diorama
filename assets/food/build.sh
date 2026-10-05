#!/bin/sh
# Optimize every food source (or the ids given) into the app's Food resources.
#   assets/food/build.sh [id ...]      FACES=15000 TEXTURE=1024 by default.
set -e
FOOD=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$FOOD/../.." && pwd)
BLENDER=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
OUT=$ROOT/Sources/DioramaApp/Resources/Food
FACES=${FACES:-15000}
TEXTURE=${TEXTURE:-1024}
mkdir -p "$OUT"
if [ $# -eq 0 ]; then set -- $(cd "$FOOD/source" && ls *.glb | sed 's/\.glb$//'); fi
for id in "$@"; do
  "$BLENDER" -b --factory-startup -P "$FOOD/optimize_food.py" -- "$FOOD/source/$id.glb" "$OUT/$id.glb" "$FACES" "$TEXTURE" 2>&1 | grep '^FOOD' || { echo "failed: $id" >&2; exit 1; }
  echo "  $(du -h "$FOOD/source/$id.glb" | cut -f1) -> $(du -h "$OUT/$id.glb" | cut -f1)"
done
