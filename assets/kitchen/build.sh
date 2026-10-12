#!/bin/sh
# Rebuild the kitchen's range, cooking island, Orders pass and Prep dresser from their scripts, export it into the app, and render review images.
#   assets/kitchen/build.sh            (needs Blender 5.x; the app never needs Blender)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
BLENDER=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
RES=$ROOT/Sources/DioramaApp/Resources/KitchenStations
mkdir -p "$RES"
for piece in stove island order prep tasting pantry bell coffee_bar connectors; do
  mkdir -p "$ROOT/docs/kitchen/$piece"
  "$BLENDER" -b --factory-startup -P "$HERE/blender/build_$piece.py" -- "$RES/$piece.glb" "$ROOT/docs/kitchen/$piece" 2>&1 | grep -E '^(STOVE|ISLAND|ORDER|PREP|TASTING|PANTRY|BELL|COFFEE_BAR|CONNECTORS)' || { echo "$piece build failed" >&2; exit 1; }
  echo "  $(du -h "$RES/$piece.glb" | cut -f1) $RES/$piece.glb"
done
