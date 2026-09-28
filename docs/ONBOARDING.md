# Focused onboarding

First launch presents Connect an AI account, then optional GitHub setup. One provider with an available model is sufficient. Existing onboarding completion and project preferences are retained. Settings offers Review setup without clearing completion or disconnecting accounts.

Provider cards distinguish missing tools, known sign-out, checking, connected, and unverified errors. Checks run independently; a failed model catalog cannot invalidate the other provider. Refresh retains previous state while checking and rejects stale view results. After a login handoff, activation triggers refresh and foreground polling runs every five seconds for up to two minutes. Manual refresh remains available.

Login continues through the existing official CLI in Terminal/browser. Claude uses subscription authentication; no API billing fallback was added. Missing tools link to official installation guidance. Locate existing installation validates a selected executable with a five-second version check and saves only its path. Login, execution, and Codex history lookup share the selection. Global installations and shell configuration are unchanged. Active Diorama work blocks changing executable selection.

GitHub setup reuses device authorization. Back or Skip cancels view-owned polling, not the saved account. Projects are not published during setup. The existing workspace is shown afterward.

Validation: 268 Swift tests passed, including per-provider failures, partial readiness while another check is pending, connection classification, invalid/missing executable selections, and existing model-selection regressions. Clean-user install, live signed-out login return, spoken VoiceOver, and missing-provider machine tests require a separate test environment; they are not established by existing-machine or rendering tests.

Native verification on the development Mac confirmed both account cards, the Review setup entry, keyboard Return to continue, Back preserving the model, and Skip returning to Settings without disconnecting providers. GitHub was unavailable because its rebuilt app credential required Keychain access; Skip remained usable. Release build and deep strict signature verification passed. No new provider login, model request, or credential change was performed during this UI check.
