# Live spatial workspace

Home is a scrolling portfolio grid with blank isometric platforms beside compact metadata cards. Click a platform or project title to enter its office, a team area to enter its conversation, and a workstation to inspect its agent. Open work screen expands the existing conversation renderer. Explore offers the same navigation as a native button list. Breadcrumbs jump to ancestors; Escape returns one level. Drag orbits, scrolling changes framing, and More → Reset View restores the scope framing.

The scene is owned by WorkspaceShell and survives navigation between sessions and conventional tools. SpatialWorkspaceModel projects existing project/worktree membership and merged provider conversations into scoped identities. It does not start execution. Only reported subagents are included. Archived conversations are hidden unless explicitly enabled. Imported conversations remain available through Imported Activity.

State and observation freshness roll up from agents. Finished turns do not imply verified work or a completed feature. Attention shortcuts open the originating agent; unavailable and last-known observations remain labeled at every scope. Detailed work uses existing transcript, activity, artifact, and execution views. Subagents use provider-scoped child inspection without parent execution controls.

The SceneKit renderer reuses existing workstation/avatar assets, retains identity-based slots, bounds detailed furniture to 24 agents and office overview pages to 12 conversations, and suspends playback while hidden or inactive. Reduced Motion skips camera travel. Camera retargeting starts from its current pose. Spatial focus and slots are in memory; existing saved project settings are unchanged.

## Local prototype

`dist/Diorama Portfolio.app` is a separately packaged debug build with bundle identifier `local.diorama.portfolio`. It uses real Diorama project and conversation data. It is not a fixture/demo mode. Production source changes also apply to the normal app build.

## Verification

- Full suite: 375 tests passed with `swift test --no-parallel`.
- After adding merged-provider and interrupted-camera coverage: 28 tests passed across SpatialWorkspaceTests, WorkspaceNavigationTests, WorkspaceMotionTests, and ExternalViewerTests.
- Parallel full-suite execution produced timing failures in existing motion and external-viewer latency tests; serial execution passed.
- Live native inspection covered campus, project, team, agent, expanded transcript/artifacts, and return navigation using connected projects.
- Deterministic tests cover stale/waiting/failed states, empty projects, large rosters, stable placement, reduced motion, and narrow/wide composer layouts.
- No paid agent turn was created. Live approval, steering, stop, and attention-request submission require a suitable live request and were not exercised; their existing handlers are reused.

The office geometry remains a functional prototype. Home uses Canvas and has no per-tile SceneKit render loop. See [Compact portfolio Home](COMPACT_PORTFOLIO_HOME.md) for usage accounting and extension points.
