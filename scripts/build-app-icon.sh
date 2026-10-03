#!/bin/bash
# Package the approved artwork at every standard macOS icon resolution.
set -euo pipefail
source_image=${1:?Usage: build-app-icon.sh SOURCE_PNG OUTPUT_ICNS}
output_icon=${2:?Missing output ICNS path}
work_dir=$(mktemp -d /tmp/diorama-icon.XXXXXX)
trap 'rm -rf "$work_dir"' EXIT
iconset="$work_dir/AppIcon.iconset"
mkdir -p "$iconset" "$(dirname "$output_icon")"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$source_image" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  sips -z "$retina_size" "$retina_size" "$source_image" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$output_icon"
