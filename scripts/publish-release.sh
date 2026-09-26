#!/bin/bash
# Called only after signed-installer verification in the private release workflow.
set -euo pipefail
: "${GH_TOKEN:?}" "${RUNNER_TEMP:?}" "${RELEASE_TAG:?}" "${RELEASE_VERSION:?}" "${RELEASE_BUILD:?}" "${GITHUB_SHA:?}"
: "${RELEASE_REPOSITORY:?}"
test "$RELEASE_REPOSITORY" = davidfromkansas/diorama-releases
[[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$RELEASE_BUILD" =~ ^[0-9]+$ ]]
test "$RELEASE_TAG" = "v$RELEASE_VERSION"
test "$(git rev-parse "$RELEASE_TAG^{commit}")" = "$GITHUB_SHA"
image="Diorama-$RELEASE_VERSION-$RELEASE_BUILD-arm64.dmg"
(cd "$RUNNER_TEMP/output" && shasum -a 256 -c "$image.sha256")
test "$(gh api "repos/$RELEASE_REPOSITORY" --jq .private)" = false
gh api --paginate "repos/$RELEASE_REPOSITORY/releases?per_page=100" --jq '.[].tag_name' > "$RUNNER_TEMP/public-release-tags"
if grep -Fxq "$RELEASE_TAG" "$RUNNER_TEMP/public-release-tags"; then
  echo 'Release already exists; refusing to replace its assets.' >&2
  exit 1
fi
# Public tags must reference only documentation history, never GITHUB_SHA.
public_sha=$(gh api "repos/$RELEASE_REPOSITORY/git/matching-refs/tags/$RELEASE_TAG" --jq ".[] | select(.ref == \"refs/tags/$RELEASE_TAG\") | .object.sha")
create_tag=0
if [[ -z "$public_sha" ]]; then
  public_sha=$(gh api "repos/$RELEASE_REPOSITORY/git/ref/heads/main" --jq .object.sha)
  create_tag=1
fi
[[ "$public_sha" =~ ^[a-f0-9]{40}$ ]]
test "$(gh api "repos/$RELEASE_REPOSITORY/git/trees/$public_sha?recursive=1" --jq '.tree[].path')" = README.md
if [[ "${1:-}" == --check-only ]]; then
  echo 'Public destination, source tag, checksum, and documentation-only target verified.'
  exit 0
fi
notes="$RUNNER_TEMP/release-notes.md"
cat > "$notes" <<EOF_NOTES
Diorama **$RELEASE_VERSION ($RELEASE_BUILD)** — Developer ID signed and Apple notarized.

Download **$image**, open it, and drag **Diorama** into **Applications**. No GitHub account is required to download.

- Requires Apple Silicon (M1 or newer) and macOS 14 or later. Intel Macs are not supported.
- Connect OpenAI or Claude during onboarding; GitHub setup is optional and never automatically uploads code.
- The corresponding official Codex CLI or Claude Code CLI must be installed and authenticated. Desktop apps are optional. Claude subscription authentication is supported.
- Swift regression and Claude helper tests passed. Installer signature, notarization ticket, and Gatekeeper checks passed.
- Early testing build: fresh-Mac setup and authentication still need user testing. Claude Desktop observation depends on its local storage format and excludes Chat, Cowork, cloud, and SSH sessions.

Choose the DMG installer. GitHub's automatic source archives contain only this repository's documentation.
EOF_NOTES
if [[ "$create_tag" == 1 ]]; then
  gh api --method POST "repos/$RELEASE_REPOSITORY/git/refs" -f "ref=refs/tags/$RELEASE_TAG" -f "sha=$public_sha" --silent
fi
gh release create "$RELEASE_TAG" "$RUNNER_TEMP/output/$image" "$RUNNER_TEMP/output/$image.sha256" --repo "$RELEASE_REPOSITORY" --verify-tag --draft --title "Diorama $RELEASE_VERSION ($RELEASE_BUILD)" --notes-file "$notes" --target "$public_sha"
gh release view "$RELEASE_TAG" --repo "$RELEASE_REPOSITORY" --json tagName,isDraft,assets
test "$(gh api "repos/$RELEASE_REPOSITORY/git/ref/tags/$RELEASE_TAG" --jq .object.sha)" = "$public_sha"
# Verify the uploaded draft before making it public.
gh release download "$RELEASE_TAG" --repo "$RELEASE_REPOSITORY" --pattern "$image*" --dir "$RUNNER_TEMP/draft-download"
(cd "$RUNNER_TEMP/draft-download" && shasum -a 256 -c "$image.sha256")
cmp "$RUNNER_TEMP/output/$image" "$RUNNER_TEMP/draft-download/$image"
gh release edit "$RELEASE_TAG" --repo "$RELEASE_REPOSITORY" --draft=false --latest
# Verify public availability without sending the publishing token.
mkdir -p "$RUNNER_TEMP/public-download"
for asset in "$image" "$image.sha256"; do
  curl --fail --silent --show-error --location "https://github.com/$RELEASE_REPOSITORY/releases/download/$RELEASE_TAG/$asset" -o "$RUNNER_TEMP/public-download/$asset"
done
(cd "$RUNNER_TEMP/public-download" && shasum -a 256 -c "$image.sha256")
cmp "$RUNNER_TEMP/output/$image" "$RUNNER_TEMP/public-download/$image"
