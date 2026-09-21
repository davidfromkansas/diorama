---
name: diorama-release
description: Build, verify, package, and publish a Diorama macOS DMG on GitHub Releases when asked to release Diorama or publish a downloadable version.
---

# Release Diorama

Repository: https://github.com/davidfromkansas/diorama. Locate its checkout from the current workspace or Git remotes; the usual local path is `/Users/david_lietjauw/Documents/ChatGPT/Diorama`.

A request to publish/release authorizes tag and release creation. A request only to build or preview does not. Complete authorized publishing without a redundant confirmation.

## Prepare an exact version

- Inspect Git status, remote, release tags, `build-macos.sh`, and existing release notes. Do not discard uncommitted work or sweep unrelated files into a release commit. Source changes intended for the release must be committed before building; keep `.local`, credentials, `.diorama/canvases`, and generated binaries out of Git.
- Read the version/build from `build-macos.sh`. For new app changes after a published version, choose the next appropriate version and increment the build, unless the user specified them. Never move a published tag or overwrite existing assets by default.
- Use a clean detached worktree of the release commit, with a separate build directory. Run `swift test --scratch-path BUILD_DIR`, then `DIORAMA_BUILD_PATH=BUILD_DIR DIORAMA_APP_PATH=OUTPUT/Diorama.app zsh build-macos.sh`. Preserve logs. Confirm actual bundle version, minimum macOS, and executable architectures rather than assuming them.

## Package and verify

- `scripts/package-release.sh APP_PATH OUTPUT_DIR` creates a DMG with an Applications shortcut and SHA-256 file. It refuses an existing output file and never publishes.
- Inspect `security find-identity -v -p codesigning`. Set `DIORAMA_SIGN_IDENTITY` to an available Developer ID Application identity. Without one, clearly label an ad-hoc build; do not claim it is Developer ID signed.
- If the user has a notarytool Keychain profile, set `DIORAMA_NOTARY_PROFILE`; packaging submits, waits, staples, and validates. Never request credentials in chat or dump secret Keychain values. If notarization is unavailable, disclose it and publish only within the user's accepted distribution scope; do not label an unnotarized preview as notarized.
- Verify the DMG with `hdiutil verify`, mount read-only, verify the contained app using `codesign --verify --deep --strict`, check metadata/architectures and Applications link, then detach. A valid signature alone does not prove Gatekeeper acceptance; use `spctl` / stapler when claiming notarization.

## Publish

Write concise release notes to a file: version/build, macOS and CPU support, install instructions, key changes, verified tests, signing/notarization status, and known limitations. Never imply fresh authenticated tests passed if only fixtures ran.

Push the intended commit without force; create a tag such as `v0.5.0` at that exact commit, then push the tag. Create a draft release with `gh release create TAG DMG SHA256 --verify-tag --draft --title TITLE --notes-file NOTES`. Inspect assets and target before publishing with `gh release edit TAG --draft=false --latest` (use prerelease flags instead if agreed). Do not publish a failed notarization as a normal release without resolving or explicitly disclosing the scope change.

If a network operation is uncertain, inspect remote tags/releases before retrying. Avoid duplicate releases or replacing artifacts. For GitHub email privacy rejection, use the account's verified no-reply address for unpublished commits without changing GitHub privacy settings or rewriting published history.

Download the published DMG into a temporary directory and compare its SHA-256 with the local artifact. Report the direct DMG link, release page, version/build, and any material distribution limitation. A source push alone is not a downloadable release.
