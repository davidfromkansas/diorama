# Local-first new conversations

Brand-new project conversations show a working-folder chooser, searchable local branch picker, and Create worktree checkbox. Existing and imported conversations do not show these controls.

Worktree creation is on by default. The starting reference defaults to local main, then master, then the current branch (or current revision for detached HEAD). Startup never fetches a remote. Fetch from remote is an explicit project-context action and does not pull or merge.

Turning off Create worktree uses the chosen folder directly, including its uncommitted edits, and selects its current branch. Switching this shared checkout requires confirmation, a clean working tree, and no active Diorama session using the folder. Direct folders are protected from worktree cleanup.

Folder, reference, and mode are saved with the draft. Folder changes preserve its text and attachments and do not change existing project roots. A successfully prepared location is locked for retries. Existing workspaces decode as managed worktrees, while new direct sessions carry an explicit marker. Linked continuations retain their source commit.

Validation: 22 project/navigation/UI checks passed, followed by 48 local-start, project UI, Codex and Claude execution checks. The opt-in Taipei probe successfully created a disposable worktree at local main without fetching; the probe removed its own checkout and branch afterward. Tests cover direct-mode edits, unsafe switching, cleanup protection, branch fallback, detached HEAD, missing references, empty repositories, and persisted retry state.
