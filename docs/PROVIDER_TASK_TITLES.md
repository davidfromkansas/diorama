# Provider task titles

Diorama reuses provider title metadata without making naming-model requests. Codex thread names and name-update notifications feed the same task label used by the roster, sidebar, conversation header, office, and inbox. Claude local discovery reads custom-title and summary records, sessions-index metadata, and existing Desktop coding-session metadata. Subagents keep their own assignment.

Labels show at most six words with an ellipsis; full names remain available to hover, accessibility, search, and rename. This is display shortening, not AI summarization. Titles do not imply completion and only change semantically when the source reports a different name.

Title provenance distinguishes prompt fallback, reported summary, unknown-provenance provider name, and explicit title. Missing observations retain richer known names. The optional provider-task-titles.json cache in Diorama's application support directory stores only title text and provenance, separately from provider files. Merged conversations use their active execution segment's reported title and retain the canonical identity.

Discovery runs on existing background actors. Unchanged transcript metadata is cached. Claude title reads are limited to the first and last 512 KiB; its optional sessions-index.json is bounded at 4 MiB and cached by file metadata. Codex local fallback reads only the initial 512 KiB. Titles solely in omitted history, without an index or cached copy, remain unavailable until reported again. No additional polling, transcript-wide scans, provider renames, or execution turns are introduced.

Inbox titles update through metadata-only ingestion without changing messages, unread state, archive state, or timestamps. Roster title changes keep meaningful activity timestamps and revision unchanged. Office nodes remain retained; only changed labels are reconciled.

## Verification — 2026-10-02

- Initial integrated run: 74 tests passed; expanded run: 77 passed. Final-source discovery/title/inbox/navigation run: 65 tests across 10 suites passed (overlapping coverage, not additive).
- Deterministic cases include appended Claude metadata outside the head window, indexed existing titles without transcript changes, cached names after restart/outage, provider renames, merged active-source identity, six-word presentation, and metadata-only inbox/roster updates.
- Existing inbox 10,000-summary pagination and native navigation/scrolling regressions passed. No paid provider turns or naming requests were started. Live provider-generated rename behavior was not manufactured for testing.
- Inspected the installed office: roster and sidebar use compact labels, full roster names remain accessible, and selecting Otto opens the same existing conversation. Closed the panel without sending a message. A final presentation-only correction applies the already-tested title cleanup to full-text tooltips/accessibility so legacy embedded Diorama markup is not narrated. Provider strings remain unchanged. Full VoiceOver narration was not exercised.
