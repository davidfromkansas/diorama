# Signed GitHub releases

`.github/workflows/release-macos.yml` builds Apple Silicon releases on GitHub's macOS 15 runner using Xcode 26.2 and Node 22.19.0. It runs on new `v*` tags; ordinary branch pushes and pull requests do not publish releases or receive signing credentials.

## One-time credentials

Configure these repository Actions secrets under Settings → Secrets and variables → Actions. Use original credential files or enter values directly into GitHub; never commit them or paste passwords into a task.

| Secret | Value |
| --- | --- |
| `MAC_CSC_LINK` | Base64-encoded Developer ID Application `.p12` export, including its private key |
| `MAC_CSC_KEY_PASSWORD` | Password protecting that export |
| `APPLE_API_KEY_BASE64` | Base64-encoded App Store Connect team API `.p8` key |
| `APPLE_API_KEY_ID` | That API key's ID |
| `APPLE_API_ISSUER` | App Store Connect team Issuer ID |

This uses the same secret naming as AgentSim. Certificates may use the same Developer ID identity; credentials remain independently configured per repository. GitHub's job token publishes to this repository, so no separate publishing token is required. GitHub secrets cannot be read back to copy them between repositories.

The job imports signing material and Apple’s pinned G2 intermediate into a temporary Keychain, adds it to the disposable runner’s search list, validates notarization credentials, and deletes the temporary Keychain/key files when done. Credential values are not written to source, release artifacts, or uploaded logs. A signing or notarization failure stops publication; there is no ad-hoc fallback in CI.

## Release a new version

1. Bump both version and build in `build-macos.sh`. Commit the intended source and release changes. Do not reuse a published version.
2. Push the commit and create a lightweight `vVERSION` tag at that exact commit. Push the tag to start the release job. A manual retry must also select that existing tag.
3. The job checks that tag and bundle version agree and no release already exists. It runs Swift/helper tests, builds the app, signs the Node runtime, reporter, app and DMG, submits to Apple, and staples the accepted ticket.
4. The job verifies the actual mounted app signature, architectures, Applications shortcut and Gatekeeper acceptance. Only then does it create a draft, inspect the tag/assets, publish, download the installer and compare the checksum/bytes.
5. Check the run and download link. If publication succeeds but download verification fails, inspect the published release before retrying. Existing releases (including drafts) deliberately block reruns; never overwrite assets to hide a failed attempt.

Signing does not establish clean-user onboarding, fresh provider login, or compatibility with Intel Macs. The current release is Apple Silicon and macOS 14+. A private repository still requires download access, even when notarized.

## Local packaging

`scripts/package-release.sh APP OUTPUT` retains local ad-hoc preview support. Set `DIORAMA_REQUIRE_NOTARIZATION=1`, `DIORAMA_SIGN_IDENTITY`, and `DIORAMA_NOTARY_PROFILE` for a distributable build. Optional `DIORAMA_SIGN_KEYCHAIN` and `DIORAMA_NOTARY_KEYCHAIN` select an existing non-default Keychain without changing the user's Keychain search list. `scripts/verify-release.sh DMG` requires a notarized Apple Silicon package and verifies the mounted installer.
