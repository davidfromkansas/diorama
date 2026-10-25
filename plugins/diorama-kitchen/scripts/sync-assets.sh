#!/usr/bin/env bash
# Copies the kitchen's models, textures and sounds from the Mac app's resources into the plugin,
# so the plugin is self-contained once installed. Sounds are converted from .caf to .mp3 (every
# browser plays mp3). Run from anywhere after changing a kitchen asset in the app.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
resources="$here/../../Sources/DioramaApp/Resources"
out="$here/assets"
for folder in Chef KitchenStations KitchenProps Food Restaurant BreakRoom; do
  rm -rf "${out:?}/$folder"; mkdir -p "$out/$folder"
  find "$resources/$folder" -maxdepth 1 -type f \( -name '*.glb' -o -name '*.json' -o -name '*.jpg' -o -name '*.obj' -o -name '*.mtl' \) \
    -exec cp {} "$out/$folder/" \;
done
rm -rf "$out/KitchenSounds"; mkdir -p "$out/KitchenSounds"
for file in "$resources"/KitchenSounds/*.caf; do
  name="$(basename "$file" .caf)"
  ffmpeg -hide_banner -loglevel error -y -i "$file" -ac 1 -codec:a libmp3lame -q:a 4 "$out/KitchenSounds/$name.mp3"
done
du -sh "$out"/*
