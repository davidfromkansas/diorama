# Compact portfolio Home

Home answers where work is happening and where intervention is needed. Project tiles are 198 points high with 16-point gutters, using two columns at a content width of 1,040 points and one below it. The sidebar and office → team → agent → work-screen navigation remain available. Home stays mounted to retain scroll position; the office scene stays mounted with rendering paused while Home is visible.

## Blank platforms and future movement

`PortfolioPlatform` draws only the pale-mint slab, with no agent markers or decorative center diamond. `PortfolioSurface` owns the project identity, normalized (u, v) coordinates, bounds, and isometric projection. A future agent-position layer can project stable agent identities onto this surface independently of the metadata card. Movement data, interpolation, hit testing, and a visibility-aware animation clock should be added to that layer when agent movement is implemented. No simulated movement or position state is manufactured now.

Metrics, navigation, and platform geometry are separate components. The existing activity indicator respects visibility, app activity, observation freshness, and Reduced Motion. Spatial hierarchy projection is cached between observation ticks so monitor/camera frame callbacks cannot repeatedly scan the entire library. Child lookup uses an explicit parent index.

## Live observations and usage

Existing discovery/watchers register original provider sources before logical conversation merging. A background portfolio observer reads connected project/worktree sources without selecting, attaching, resuming, or executing a conversation. Selected conversations continue to load details through the existing readers and controls.

`PortfolioUsageIndex` is an actor with an incremental, rebuildable JSON cache under the user's Caches/Diorama directory. It reads historical JSONL in bounded slices, retains acknowledged totals across missing/truncated files, retries trailing incomplete lines, and skips oversized artifact lines with a partial-coverage label. The cache contains source identities, usage ledgers, and byte offsets, not transcript content. Archived sources participate regardless of the conversation filter.

Codex cumulative usage replaces prior counters. Claude message IDs deduplicate repeated block snapshots; separately reported cache input categories are included. Saved and streamed aggregates are alternative scopes and are never blindly summed. When disjointness cannot be proved, the larger known lower bound is shown as Partial. Child usage with possible parent overlap is excluded and coverage is marked Partial. Consequently, buffered reports or ambiguous Claude live/saved boundaries can delay a displayed increase until saved history catches up. Missing usage is Unavailable, never a fabricated zero.

Exceptions are deduplicated by scoped agent identity and ordered approval, input, then reported failure, with oldest known timestamps and stable IDs breaking ties. Exception buttons open the source agent's work screen. Existing provider restrictions remain in force.

## Verification

The full serial suite passed: **391 tests in 95 suites** (`swift test --no-parallel`). The local macOS debug bundle built and signed successfully.

Deterministic tests cover external Codex watcher updates, external Claude working/input changes without selection, cumulative replacement, message deduplication, mixed providers, merged and archived history, parent/child overlap, missing files after restart, truncation, cache rebuilds, partial JSON, oversized artifacts, stable project order/scroll identity, attention routing, and 100-project rendering at narrow and wide sizes.

Native inspection verified Home → office → team → agent → expanded work screen → Home, exact usage popovers, live reported usage changes without project selection, and restored Home scroll position. Accessibility inspection confirmed hidden Home controls are removed from the office tree. Narrow/wide layouts were inspected through rendered fixtures. Reduced Motion and execution restrictions are covered by regression tests; OS-level VoiceOver narration and live approval/steering/stop submissions were not exercised.

The native debug prototype reads real local project data. No paid turn is created for verification. Live approval submission, steering, and stop actions need a suitable active request and are not manufactured for the test.
