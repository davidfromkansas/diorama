# Project local servers

The office footer shows confirmed project TCP listeners beside Inbox. The panel is read-only: it never starts/stops servers or opens a browser automatically. Possible matches from reported URLs do not contribute to the confirmed count.

Discovery uses the system lsof inventory plus libproc identity, start time, working directory and ancestry. Matching prefers the most specific registered project/worktree path. Duplicate address records and related parent/child workers on identical endpoints are grouped. Detection is explicitly labeled partial because it covers accessible local processes, not every service on the machine. A listener is not a health check.

Scans run off the main actor, with a three-second command timeout, every five seconds while visible/active/unpaused. Opening, refresh, activation and URL evidence trigger refreshes. A generation guard rejects cancelled results; one inventory runs at a time. Errors retain previous rows with a stale notice. URL history reads are fingerprinted, capped at 512 KiB per source, two concurrent reads and 256 cached sources. No provider turn is started.

Runtime state is memory-only. Process identities include start times. Port reuse suppresses old URL evidence for the rest of this view lifetime, conservatively requiring rediscovery after reopening the project before offering browser actions. Labels omit URL queries, fragments and credentials. Browser actions preserve the original reported URL and use the default browser.

Limitations: remote/container ownership is not inferred; inaccessible processes are absent; cached history is bounded and may miss older URLs. Five-second refresh latency excludes scan/history-read time. Actual performance and live verification are recorded in the task response; no universal FPS guarantee is implied.

## Verification (2026-10-02)

- Release build and signing succeeded. The existing auto-reload flow is responsible for installation after owned active turns finish.
- 37 targeted server/inbox/navigation/external-observation tests ran: 36 passed initially; the external-history append timing check was 678 ms against its 500 ms threshold. Its isolated rerun passed at 400 ms.
- A disposable HTTP listener was detected by the native inventory in 112 ms. After the fixture stopped, lsof confirmed that its port was no longer listening. No provider execution was started.
- Full live panel interaction, narrow-window/VoiceOver checks and sustained frame measurements remain pending while the previous app owns active agent work. These are not claimed as verified.

## Live app follow-up

Installed into dist/Diorama.app after user-authorized normal shutdown of remaining owned tasks. In the office, a disposable project TCP listener appeared as 1 listening without manual refresh, and shutdown returned the count to 0 on the next refresh (checked after six seconds). Verified the project directory/port row, Inbox/Servers mutual exclusion and Escape preserving the current scope. Test listeners were stopped. An initial attribution check before the subsequent reload showed no match; repeated start/stop checks in the installed app succeeded, so cold-start discovery latency remains unmeasured. Full VoiceOver, narrow-window and sustained FPS verification remain unclaimed.
