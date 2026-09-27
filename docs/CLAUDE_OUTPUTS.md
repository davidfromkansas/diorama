# Claude output viewing — 2026-09-27

Latest combined build: `dist/Diorama.app`. See [Independent provider outputs](DEEP_PROVIDER_OUTPUTS.md) for subsequent Claude metadata, metrics, delegation, source inspection, tests and remaining acceptance gaps. Build names below describe earlier verification runs.

This development build adds passive rich conversation cards and explicit output previews. It is not a declaration of full CLI/Desktop real-time certification.

## Implemented

- Shared saved-transcript and SDK-history normalization; tool calls/results correlate by native tool ID within their source and agent. Rows retain identity when results arrive. Orphan results remain readable.
- Artifact Quickstart guidance stays collapsed tool output. A successful Artifact call with an explicit `file_path` produces an output card, including the Desktop variant with no action argument observed in the reported session. Successful Write/Edit operations expose their explicit file references. Prose paths alone never produce outputs.
- Text, images, documents, embedded resources and resource links; unsupported blocks receive placeholders. Internal context attachments and reasoning are excluded; unknown record types are counted without their bodies.
- Tool outcome cards, plan details, task checklist cards, source-reported events and agent inspector links. Child snapshots remain available in the bounded observation cache. Work with explicit non-main ownership is not assigned to the main desk.
- On-demand local HTML, image, text, Markdown and PDF previews. Other formats/remote links have external-open controls. Previewing a historical file shows its current disk contents, not an invented historical version.
- HTML uses ephemeral WebKit storage and an opaque sandboxed iframe. No native messaging bridge or network access. Explicit relative script/style/image companions are embedded within bounded limits; traversal and symlink escapes are blocked. Dynamic dependencies remain unavailable.
- No new prompts, execution attachment, resume, approval handling or hooks are introduced by viewing.

## Verification evidence

| Check | Result |
|---|---|
| Full Swift suite, serial run | Passed: final run 333 tests / 82 suites; `/tmp/diorama-rich-final-suite.log` |
| Full Swift suite, concurrent run | Failed: timing-sensitive watcher/motion tests interfered under concurrent native rendering; retained in `/tmp/diorama-rich-full.log` |
| Claude helper suite | Passed: 6 tests, including rich history preservation and reasoning exclusion |
| Real CLI output | Passed: Claude Code 2.1.283 wrote/read `counter.html`; saved transcript parsed as a completed Write card; local HTML preview loaded |
| Desktop Artifact format | Passed sanitized regression for observed `file_path`/icon/description input without action, plus Quickstart guidance |
| HTML sandbox | Existing native WebKit tests passed: scripts render, opaque parent isolation, native bridge absent, networking blocked |
| Companion files | Passed relative embedding, traversal non-embedding, symlink escape rejection, remote-local distinction |
| Layouts | Native ImageRenderer images inspected at 420 and 900 points; `artifacts/claude-outputs/cards-*.png` |
| Packaged app outside checkout | Built, ad-hoc signed and signature verified; native window launched |
| Packaged interactive preview through UI | Passed in final named build: discovered real CLI conversation, opened completed Write card, clicked Increment and visually confirmed 0 → 1; Escape returned to the conversation. Earlier temporary-copy control timed out. |
| 30 correlated rendered updates / 3 turns for each client | Not verified in this change; the single CLI artifact smoke test is not a latency certification |

A later serial run reproduced a 20-subagent timing failure. The fix batches hook-history reads once per child group and publishes the parent conversation before child I/O; 22 affected tests passed in `/tmp/diorama-rich-hooks-batch.log`. It also preserves missing-transcript error presentation. Aggregate timing probes now count result changes to existing cards, not only new row IDs. These probes still do not prove pixel presentation.

## Test this build

Open `dist/Diorama-Claude-Outputs.app`, add `/private/tmp/diorama-artifact-test`, select its Claude conversation, choose Conversation, and find the completed Write card for `counter.html`. Click Preview, then the counter button. The test app is separate from installed copies; use the explicitly named build.

For another test, ask Claude Code in a disposable folder to use Write to make a self-contained HTML counter with inline CSS/JavaScript and no network dependencies. Diorama should show the completed file card without manually refreshing. Repeat separately in Claude Code CLI and Desktop's local Code tab. Dedicated Artifact calls need explicit provider file/resource evidence; Quickstart guidance is not an artifact.

## Remaining acceptance work

Full multi-turn CLI/Desktop rendered-latency comparisons, source-side failure/approval variants, broader keyboard/focus/reading-position checks in the packaged app, and richer attachment/progress formats not yet observed remain unverified. Task cards show reported inputs/outcomes; they do not invent task ownership or infer a progress percentage. Unknown formats are diagnostic gaps, not claims of complete Claude coverage.
