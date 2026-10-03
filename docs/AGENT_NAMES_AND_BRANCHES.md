# Agent names and descriptive branches

Agent names are presentation metadata, saved locally in Application Support/Diorama/AgentNames.json. Native provider/session/agent identities still route all observations and execution. Main-agent aliases bind merged provider segments to one display name. Assigned names are unique within a project; meaningful reported Codex nicknames take precedence. Imported conversation titles and Claude task descriptions are not treated as names. Missing provider nicknames receive persistent one-word names.

The new-task form suggests an editable branch name from the initial prompt. New branches use 1–6 lowercase hyphen-separated words. Vague prompts require an explicit name when creating a branch. Existing folders, branches, and UUID-based worktree paths are unchanged. Local refs, known remote refs, and pending in-process reservations participate in collision checks. A numeric suffix remains within six words. Git performs the final atomic creation. A repository-local branch marker allows recovery of an already prepared workspace without renaming it.

Regression coverage includes name persistence/merged aliases, task-title separation, name-pool exhaustion, old option decoding, local/remote collisions, concurrent creations, and worktree recovery. These checks create disposable Git repositories and do not invoke coding providers.
