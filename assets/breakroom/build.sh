#!/bin/sh
# Optimize the break room's machines (Meshy downloads in source/, not in git) into the app's
# BreakRoom resources, with the food pipeline's script (centred, base at 0, widest side 1.0; the
# app sizes each machine, see BreakRoom.swift).
#   assets/breakroom/build.sh [id ...]      FACES=20000 TEXTURE=1024 by default.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
BLENDER=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
OUT=$ROOT/Sources/DioramaApp/Resources/BreakRoom
FACES=${FACES:-20000}
TEXTURE=${TEXTURE:-1024}
mkdir -p "$OUT"
if [ $# -eq 0 ]; then set -- $(cd "$HERE/source" && ls *.glb | sed 's/\.glb$//'); fi
for id in "$@"; do
  "$BLENDER" -b --factory-startup -P "$ROOT/assets/food/optimize_food.py" -- "$HERE/source/$id.glb" "$OUT/$id.glb" "$FACES" "$TEXTURE" 2>&1 | grep '^FOOD' || { echo "failed: $id" >&2; exit 1; }
  echo "  $(du -h "$HERE/source/$id.glb" | cut -f1) -> $(du -h "$OUT/$id.glb" | cut -f1)"
done
