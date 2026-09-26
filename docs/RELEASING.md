# Signed GitHub releases

`.github/workflows/release-macos.yml` builds Apple Silicon releases on GitHub's macOS 15 runner using Xcode 26.2 and Node 22.19.0. It runs on new `v*` tags; ordinary branch pushes and pull requests do not publish releases or receive signing credentials.

## Public downloads

Downloads are published to **davidfromkansas/diorama-releases**, an independent public repository containing only a README and release assets. The stable link is https://github.com/davidfromkansas/diorama-releases/releases/latest. Source, CI logs, and Apple credentials stay in the private **davidfromkansas/diorama** repository. Public tags reference documentation commits; source tags are verified independently inside the private build. Never push private commits to the public repository.

## One-time credentials

Configure these repository Actions secrets under Settings → Secrets and variables → Actions. Use original credential files or enter values directly into GitHub; never commit them or paste passwords into a task.

| Secret | Value |
| --- | --- |
| `MAC_CSC_LINK` | Base64-encoded Developer ID Application `.p12` export, including its private key |
| `MAC_CSC_KEY_PASSWORD` | Password protecting that export |
| `APPLE_API_KEY_BASE64` | Base64-encoded App Store Connect team API `.p8` key |
| `APPLE_API_KEY_ID` | That API key's ID |
| `APPLE_API_ISSUER` | App Store Connect team Issuer ID |
| `RELEASES_GITHUB_TOKEN` | Fine-grained token limited to `davidfromkansas/diorama-releases`, Contents read/write, 90-day expiry |

This uses the same secret naming as AgentSim. Certificates may use the same Developer ID identity; credentials remain independently configured per repository. The built-in job token has read-only access to the private source. Only the dedicated publishing token writes public releases. Create/renew that token in GitHub Settings → Developer settings → Personal access tokens → Fine-grained tokens, selecting only `diorama-releases` and Contents read/write. Store it directly as `RELEASES_GITHUB_TOKEN` in the private repository’s Actions secrets. Renew before its 90-day expiry; expired/missing authorization must stop publication, never trigger a broader credential fallback. GitHub secrets cannot be read back to copy them between repositories.

The job imports signing material and Apple’s pinned G2 intermediate into a temporary Keychain, adds it to the disposable runner’s search list, validates notarization credentials, and deletes the temporary Keychain/key files when done. Credential values are not written to source, release artifacts, or uploaded logs. A signing or notarization failure stops publication; there is no ad-hoc fallback in CI.

## Release a new version

1. Bump both version and build in `build-macos.sh`. Commit the intended source and release changes. Do not reuse a published version.
2. Push the commit and create a lightweight `vVERSION` tag at that exact commit. Push the tag to start the release job. A manual retry must also select that existing tag.
3. The job checks that the private source tag and bundle version agree and no public release already exists. It runs the full Swift suite serially to avoid concurrent AppKit/WebKit test interference, runs helper tests, builds the app, signs the Node runtime, reporter, app and DMG, submits to Apple, and staples the accepted ticket.
4. The job verifies the actual mounted app signature, architectures, Applications shortcut and Gatekeeper acceptance. Only then does `scripts/publish-release.sh` create or verify a public documentation-only tag, create a draft, download and compare draft assets, publish, and download again without authentication to compare checksums/bytes. Public notes omit private source/build links. Every release operation names its destination repository explicitly.
5. Check the run and download link. If publication succeeds but download verification fails, inspect the published release before retrying. Existing releases (including drafts) deliberately block reruns; never overwrite assets to hide a failed attempt.

Signing does not establish clean-user onboarding, fresh provider login, or compatibility with Intel Macs. The current release is Apple Silicon and macOS 14+. The public release repository permits unauthenticated downloads; the application source remains private. Existing releases in the private repository are retained. The initial public release is the unchanged notarized 0.7.5 (50) installer; older builds are not backfilled.

## Local packaging

`scripts/package-release.sh APP OUTPUT` retains local ad-hoc preview support. Set `DIORAMA_REQUIRE_NOTARIZATION=1`, `DIORAMA_SIGN_IDENTITY`, and `DIORAMA_NOTARY_PROFILE` for a distributable build. Optional `DIORAMA_SIGN_KEYCHAIN` and `DIORAMA_NOTARY_KEYCHAIN` select an existing non-default Keychain without changing the user's Keychain search list. `scripts/verify-release.sh DMG` requires a notarized Apple Silicon package and verifies the mounted installer.
