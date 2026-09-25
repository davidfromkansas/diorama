# Projects in Diorama 0.4.0

Projects are explicitly registered Git repositories. Imported activity retains the previous discovery browser; opening the app does not promote discovered folders into Projects.

## Everyday flow

1. Add Project → Open project, Open GitHub project, or New Project.
2. New Session opens a persistent draft. First Send fetches the base (normally origin/main), creates a dedicated branch/worktree, snapshots Project context, then starts the Codex thread with that working directory.
3. Sessions, Pull Requests, Files, and Context stay under the Project. Cmd+1–4 switches sections; Cmd+N opens a new draft. Narrow windows replace the session list with a Sessions/Back control.
4. Archive retains files and branch. Cleanup is a separate action on an archived session's branch menu and refuses changed/untracked/ignored files or commits absent from the configured base. Branches are retained.

## Context and files

Repository content comes from the fetched base. Instructions and repository-relative references/URLs are stored in Diorama. Official thread/start and thread/fork developerInstructions carry the captured context, without appending it to the visible user message. Existing sessions are not silently updated.

Files can show the base revision directly from Git or a managed session worktree. The browser supports folders, search, text/image preview, references, and attachments to the selected conversation draft (or a new session when none is selected). Attaching a base file creates an immutable local snapshot; it does not alter the primary checkout. Text previews and subprocess output are bounded. External document uploads into shared Project context and automatic memory are not implemented.

## Persistence and integration

Project records live at ~/Library/Application Support/Diorama/Projects/projects.json. Managed worktrees, attachment snapshots, and PR caches live alongside the records. Writes are atomic. Canonical Git common-directory identity groups linked worktrees; independent clones remain distinct. Existing conversations retain their recorded cwd.

Preparation saves a pending workspace identifier before creating files. Thread creation and first-message submission have persistent uncertainty flags. An unknown outcome is never automatically replayed; users can inspect the prepared conversation or create a separate session. A definitive RPC rejection can be retried.

Git commands use argument arrays, not interpolated shell commands. GitHub functionality uses Diorama’s OAuth account from Settings → GitHub and its own Keychain entry. It does not use Terminal’s gh login. Owned sessions offer a Create PR preview; review and merging remain on GitHub. Publishing a newly created repository is optional, defaults to private, and pushes only its initial empty commit. No GitHub repository is created during automated verification.

## Validation

Core tests cover separate worktrees, independent edits, canonical-path retries, fresh remote commits, explicit cached fallback, immutable context snapshots, atomic persistence, and conservative cleanup. API fixtures verify thread instructions and fork cwd fields. Rendering tests cover the Context view in light/dark appearances. Full regression suite and signed release bundle checks are recorded in the live task canvas.

## Practical limits

- The GitHub repository chooser loads 100 repositories per page and offers Load more; a known repository URL can also be entered directly. PR lists support Load more.
- Setup scripts, automatic ignored-file copying, dependencies, and dev-server port allocation are not configured automatically.
- Claude Code imports remain read-only. Diorama does not edit Desktop's private project metadata.
- Uncertain creation requires inspecting imported history; there is no automatic guessing of thread identity.
