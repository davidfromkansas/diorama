# Local development

- Maintain one development app at `dist/Diorama.app`. Update that app instead of creating task-specific `.app` copies in `/tmp` or other locations.
- Stage updates in `.local/development/Diorama.app`; this is an internal installation staging directory, not a second app to launch.
- Use release configuration for the interactive development app. Preserve `DIORAMA_DEVELOPMENT_ROOT` so source auto-reload continues to work.
- Do not replace a running app bundle. Use the existing development relaunch flow after safe shutdown. Never interrupt active agent work without the user's authorization.
- Release packaging may use separate staging directories; it must not create additional development apps.
