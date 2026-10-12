#!/bin/sh
# Fit characters to the chef's skeleton, verify them, and render review sheets.
#   assets/chef/build_variants.sh [--guests|--staff] [id,id]      RENDER=0 skips the review renders.
# Chef characters (variants.json) go to Resources/Chef as chef-<id>.glb; restaurant guests
# (guests.json, --guests) go to Resources/Restaurant as guest-<id>.glb; kitchen staff (the
# manager; staff.json, --staff) go to Resources/Chef as staff-<id>.glb. All play the chef's
# clips, so build the chef first (assets/chef/build.sh). Sources (original Meshy downloads) are
# not in git: variants/source/, guests/source/ and staff/source/.
set -e
CHEF=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$CHEF/../.." && pwd)
BLENDER=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
if [ "$1" = "--guests" ]; then
  shift; KIND=guests; LIST=$CHEF/guests.json; SOURCES=$CHEF/guests/source; PREFIX=guest
  RES=$ROOT/Sources/DioramaApp/Resources/Restaurant; INDEX=guest-list.json; BASE=../Chef/chef-animated.glb
  CLIPS=sit_talk,sit_laugh,sit_eat,sit_gesture,sit_cheer,sit_sip; DOCS=$ROOT/docs/restaurant/guests
elif [ "$1" = "--staff" ]; then
  shift; KIND=staff; LIST=$CHEF/staff.json; SOURCES=$CHEF/staff/source; PREFIX=staff
  RES=$ROOT/Sources/DioramaApp/Resources/Chef; INDEX=staff-list.json; BASE=chef-animated.glb
  CLIPS=walk,manager_talk,idle_available; DOCS=$ROOT/docs/chef/staff
else
  KIND=variants; LIST=$CHEF/variants.json; SOURCES=$CHEF/variants/source; PREFIX=chef
  RES=$ROOT/Sources/DioramaApp/Resources/Chef; INDEX=chef-variants.json; BASE=chef-animated.glb
  CLIPS=walk,working_chop,carry_walk,arrive_wave,sit_idle,present_review; DOCS=$ROOT/docs/chef/variants
fi
OUT=$ROOT/.local/chef-$KIND
ONLY=$1
mkdir -p "$OUT" "$RES"
python3 - "$LIST" "$ONLY" "$PREFIX" > "$OUT/jobs.txt" <<'PY'
import json, sys
config = json.load(open(sys.argv[1]))
only = set(filter(None, sys.argv[2].split(",")))
for c in config["characters"]:
    if not only or c["id"] in only:
        opts = {"tail": c.get("tail"), "budget": config.get("budget", {}), "prefix": sys.argv[3]}
        print(c["id"], c["source"], json.dumps(opts, separators=(",", ":")))
PY
while read -r ID SRC OPTS; do
  echo "== $ID"
  "$BLENDER" -b --factory-startup -P "$CHEF/blender/build_variant.py" -- "$SOURCES/$SRC" "$OUT" "$ID" "$OPTS" > "$OUT/$ID.log" 2>&1 || { tail -20 "$OUT/$ID.log"; exit 1; }
  cp "$OUT/$PREFIX-$ID.glb" "$RES/"
done < "$OUT/jobs.txt"
# The app's list: every fitted character's record, in list order.
python3 - "$LIST" "$OUT" "$RES/$INDEX" "$PREFIX" "$BASE" <<'PY'
import json, os, sys
config, out, dest, prefix, base = sys.argv[1:]
characters = []
for c in json.load(open(config))["characters"]:
    path = os.path.join(out, f"{prefix}-{c['id']}.json")
    if os.path.exists(path):
        rec = json.load(open(path)); rec["name"] = c["name"]; characters.append(rec)
json.dump({"base": base, "characters": characters}, open(dest, "w"), indent=2)
PY
(cd "$CHEF/verify" && { [ -d node_modules ] || npm install --silent --no-audit --no-fund; } && node verify-variants.mjs "$RES" "$INDEX")
if [ "$RENDER" != "0" ]; then
  mkdir -p "$DOCS"
  while read -r ID SRC OPTS; do
    rm -rf "$OUT/review-$ID"
    "$BLENDER" -b "$CHEF/chef-rigged.blend" -P "$CHEF/blender/review_variant.py" -- "$OUT/$PREFIX-$ID.blend" "$ROOT/Sources/DioramaApp/Resources/Chef/chef-manifest.json" "$OUT/review-$ID" \
      "$CLIPS" front,production > "$OUT/review-$ID.log" 2>&1
    python3 "$CHEF/blender/sheets.py" "$OUT/review-$ID"
    python3 - "$OUT/review-$ID" "$DOCS" "$ID" <<'PY'
import glob, os, sys
from PIL import Image
src, dest, ident = sys.argv[1:]
for f in glob.glob(os.path.join(src, "sheet_*.png")):
    im = Image.open(f).convert("RGB"); s = min(1.0, 1200 / im.width)
    im.resize((int(im.width * s), int(im.height * s))).save(os.path.join(dest, f"{ident}_{os.path.basename(f)[6:-4]}.jpg"), quality=80)
PY
  done < "$OUT/jobs.txt"
fi
