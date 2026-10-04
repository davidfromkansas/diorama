#!/bin/bash
# Called after notarization. Produces the feed next to the immutable DMG.
set -euo pipefail
: "${DIORAMA_UPDATE_PRIVATE_KEY:?Missing update signing key}" "${RELEASE_VERSION:?}" "${RELEASE_BUILD:?}"
output=${1:?Output directory required}
tools=${2:?Sparkle tools directory required}
[[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$RELEASE_BUILD" =~ ^[0-9]+$ ]]
base="https://github.com/davidfromkansas/diorama-releases/releases/download/v$RELEASE_VERSION/"
printf '%s' "$DIORAMA_UPDATE_PRIVATE_KEY" | "$tools/generate_appcast" --ed-key-file - --maximum-deltas 0 \
  --download-url-prefix "$base" --full-release-notes-url "https://github.com/davidfromkansas/diorama-releases/releases/tag/v$RELEASE_VERSION" "$output"
python3 scripts/verify-update-feed.py "$output/appcast.xml" "$output" "$RELEASE_VERSION" "$RELEASE_BUILD"

swift scripts/verify-update-signature.swift "$output/appcast.xml" "$output/Diorama.app" "$output/Diorama-$RELEASE_VERSION-$RELEASE_BUILD-arm64.dmg"
