#!/bin/sh
# Rebuild the restaurant around the kitchen from its script and export it into the app.
#   assets/restaurant/build.sh            (needs Blender 5.x; the app never needs Blender)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
BLENDER=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
OUT=$ROOT/Sources/DioramaApp/Resources/Restaurant/restaurant.glb
mkdir -p "$(dirname "$OUT")"
"$BLENDER" -b --factory-startup -P "$HERE/blender/build_restaurant.py" -- "$OUT" 2>&1 | grep '^RESTAURANT' || { echo "restaurant build failed" >&2; exit 1; }
echo "  $(du -h "$OUT" | cut -f1) $OUT"
