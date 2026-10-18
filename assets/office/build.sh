#!/bin/sh
# Rebuild the office's station fixtures, lobby and props from blender/build_office.py and export
# them into the app.
#   assets/office/build.sh            (needs Blender 5.x; the app never needs Blender)
#   REVIEW=1 assets/office/build.sh   (also renders review images into docs/office/)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
BLENDER=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
RES=$ROOT/Sources/DioramaApp/Resources
build() {
  piece=$1; out=$2
  review=""; [ -n "$REVIEW" ] && review="$ROOT/docs/office"
  "$BLENDER" -b --factory-startup -P "$HERE/blender/build_office.py" -- "$piece" "$out" $review 2>&1 | grep '^OFFICE' || { echo "$piece build failed" >&2; exit 1; }
  echo "  $(du -h "$out" | cut -f1) $out"
}
for piece in order prep cooking stove tasting bell serving pantry; do build $piece "$RES/OfficeStations/$piece.glb"; done
build lobby "$RES/OfficeLobby/lobby.glb"
for piece in box_sky box_mint box_peach box_lilac box_butter box_coral binder toolbox device plan_board; do build $piece "$RES/OfficeProps/$piece.glb"; done
