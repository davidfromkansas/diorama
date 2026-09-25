# GitHub workflow — implementation and verification

Settings → GitHub signs in through Diorama's registered OAuth application using device authorization. The public client ID is packaged in Info.plist; no client secret is shipped. Credentials use the `local.diorama.github.oauth` Keychain service. Terminal's GitHub CLI account and global Git configuration are not changed.

Connecting never publishes a project or fetches on conversation startup. Repository import supports paginated account/organization repository browsing. Local projects offer Publish to GitHub in their project menu, with private visibility selected initially and a committed-history preview. Uncommitted changes remain local.

Owned GitHub-connected sessions offer Create PR in the Changes inspector. The preview includes branch, destination, commits, file selection, diffs, title and description. A temporary Git index isolates the selected-file commit from unrelated staged entries; normal Git commit hooks still run. Mutations serialize per checkout and exclude active Diorama work. Git receives a verified HTTPS URL and Diorama's bounded credential helper, with redirects disabled. URL rewrites are rejected.

PR progress is stored under the Projects directory in `github-operations`, without credentials. Retrying reconciles a prepared commit and existing PR before repeating remote steps. A successful PR is saved in the workspace before its pending record is removed. Existing PR records decode without the new optional destination/merge fields.

Saved PR identities refresh directly, including after deletion of the source branch. GitHub supplies draft/open/closed/merged state; failed refreshes retain the last known state. A confirmed merge offers Update local destination-branch in the Checks inspector. The action fetches explicitly and requires a clean, inactive checkout and a fast-forward. It never resets history or removes worktrees.

## Development signing

This Mac currently has no valid code-signing certificate. Development bundles are ad-hoc signed and verified by the build script. Their changing signature can require macOS Keychain approval after rebuilding; the credential helper can also require approval. Stable Developer ID signing is needed to validate a smooth credential experience across distributed app updates. No broader Keychain access is granted as a workaround.

## Evidence and remaining acceptance

- Live device authorization succeeded for the supplied Diorama OAuth client ID; the user approved macOS Keychain access.
- On September 25, 2026, Diorama created and pushed the private disposable repository `davidfromkansas/diorama-github-check-20260925`. Git URL preflight and GitHub email privacy failures found during testing were fixed without changing global Git settings or disabling privacy protection. New published-project and selected-file commits use the connected account's GitHub no-reply identity.
- Diorama created PR #1 with README.md, then updated the same PR with a second commit. The README-only diff was reviewed and merged on GitHub. Diorama detected Merged and its explicit Update local main action fast-forwarded the clean local checkout to `e9e7cbecb9b6ede365b3f7b5de96607acf5884e3`. The session worktree remains intact.
- Final regression suite: 262 tests in 69 suites passed. Account/workflow coverage includes successful sign-in, denial, expiration, cancellation, concurrent refresh, disconnect during response, API failures, selected commits, unrelated staged edits, renames, stale previews, private author identity, and unsafe destinations.
- Live account repository browsing and private repository import succeeded into a separate local folder, with the expected merged commit.
- Live organization permission restrictions, exhaustive interrupted-operation fault injection, and reconnect across Developer ID-signed releases remain unverified. These are not claimed as completed acceptance checks.
- If repository creation's response is lost before its numeric ID is saved, publishing stops for explicit repository review rather than assuming that an existing same-name repository belongs to the interrupted operation.
- Automatic approval review rejected a disposable agent command that also proposed an unrelated HTML file. That turn was cancelled; only README.md was written and included in the live PR test.

References: [GitHub device flow](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow), [GitHub pull requests API](https://docs.github.com/en/rest/pulls/pulls), [Apple Keychain queries](https://developer.apple.com/documentation/security/secitemcopymatching(_:_:)).
