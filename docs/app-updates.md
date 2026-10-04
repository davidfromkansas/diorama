# macOS updates

Diorama uses Sparkle 2.10 with a custom SwiftUI card in the active window. The stable feed is the `appcast.xml` asset at `https://github.com/davidfromkansas/diorama-releases/releases/latest/download/appcast.xml`. Prereleases are excluded by GitHub's latest stable endpoint. Each enclosure uses an immutable release-tag URL.

The card checks at launch when overdue, then at six-hour intervals and overdue activation. Download is explicit. Dismissing the card hides it across windows until the next launch; downloads continue. **Check for Updates…** makes it visible again. Restart is explicit. Active work or background terminals require **Stop agents and restart** consent. Diorama saves window state, pauses goals, stops its agents and terminal commands, and shuts down the transports before authorizing Sparkle installation. Failure to stop keeps the app open. Interrupted work is not automatically resumed.

Sparkle prepares an installer before offering Restart. Ordinary quit cancels that installer using its `.skip` ready-stage reply (which does not skip the version permanently) and waits for cancellation before quitting. Closing a window does not quit. Force-quitting or a process crash cannot run this cancellation handshake; Sparkle may finish a prepared installation after that termination. This does not resume agent work. Include crash recovery in signed-release qualification. Development bundles carrying `DevelopmentRoot.txt` never instantiate Sparkle; the development-only **Preview update notification** menu exercises simulated UI states without downloads, installation, or agent activity.

## Release configuration

Before publishing the first update-capable release:

1. Generate an Ed25519 key pair using the pinned Sparkle `generate_keys` tool on the release administrator's machine. Keep a secure offline backup. Never commit the private key.
2. Set repository variable `DIORAMA_UPDATE_PUBLIC_KEY` to the public key and repository secret `DIORAMA_UPDATE_PRIVATE_KEY` to the exported private key. Existing Developer ID and notarization credentials remain required.
3. Build and notarize the release. CI embeds the public key, signs nested Sparkle components inside-out, generates the signed feed after packaging, validates metadata and the DMG signature against the app’s embedded public key, uploads to a draft release, downloads and compares the feed, then publishes. Feed and DMG must be published together. Never overwrite an existing release's assets.
4. Select `stable` for the manually dispatched release workflow when the version is ready for the stable channel. Tag-triggered releases retain the existing prerelease default.
5. Verify a real Developer ID-signed older build upgrades to a newer signed build. Exercise valid/invalid signatures, interrupted download, unsupported OS, ordinary quit while ready, active-work consent/cancellation, shutdown failure, and launch after installation. Confirm no turn starts automatically.

Existing releases without Sparkle need one manual installation of an update-capable version. This change does not publish a release or provision signing credentials.

## Local verification

- `python3 scripts/test-update-feed.py`
- `swift scripts/verify-update-signature.swift --self-test`
- `swift test -c release --no-parallel --filter AppUpdateTests`
- Run `ExecutionTests` for terminal shutdown, uncertain work, submission gating, and imported-history resume behavior.
- The rendering test writes real SwiftUI card screenshots to `/tmp/diorama-update-{available,downloading,ready,failed}.png`, with a visible simulated-update label.

A real signed installation remains a release gate; unit tests and simulated screenshots do not replace it.
