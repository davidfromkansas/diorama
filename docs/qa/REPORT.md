# Diorama QA report: kitchen chefs and the new Home

**Date:** 10 Oct 2026. **Build:** `dist/Diorama.app` from branch `polish`, uncommitted.

**Method:** hands-on use of the running dev app through computer use, as three personas (see [PERSONAS.md](PERSONAS.md)). Each problem was fixed in code, rebuilt with `swift build`, and re-checked in the app after the dev reload. Media is in [media/](media/).

## Summary: what's left before launch

The kitchen and Home now behave as designed in normal use, and the local merge and the GitHub PR flow both work end to end.

What still stands between this build and a launch, most important first:

| # | Issue | Why it matters | Effort |
|---|---|---|---|
| L1 | **Pushes fail for users with GitHub email privacy on.** Diorama commits with the user's global git email; GitHub rejects the push, and Diorama shows a misleading error ("Check for an existing repository or PR…"). | Shipping work is the end of the core loop. Many GitHub users have this setting on, the default for new accounts. | Medium: detect the rejection and explain it, or commit with the user's `…@users.noreply.github.com` address from the connected GitHub account. |
| L2 | **No way to publish a local project from where users work.** On a project with no remote, *Push & open PR…* shows the raw `error: No such remote 'origin'`. *Publish to GitHub…* is only in the project's list-view menu, which the kitchen view doesn't reach. | Users with a local repo hit a dead end at their first PR. | Small to medium: route *Push & open PR…* into the publish flow when there's no remote. |
| L3 | **Development and installed copies share one data store.** Two copies of Diorama with the same app ID (`local.diorama.prototype`) read and write the same `projects.json`. The other copy's save silently erased four projects I'd added in this one. | Data loss for anyone, you included, who runs a dev build next to the installed app. | Small: give dev builds their own bundle ID and Application Support folder. |
| L4 | **Release signing / Keychain.** Every ad-hoc-signed rebuild loses access to the saved GitHub login. Home then shows "Allow access", and macOS asks again. | Users of the shipped app must never see this after an update. Release builds need a stable Developer ID signature. | For release: confirm the release pipeline signs with Developer ID. For dev: create the "Diorama Development" certificate (`build-macos.sh` already uses it if present). |
| L5 | **The answer button is below the fold.** On an agent's question card, *Send answer* sits under the message composer until you scroll. | "It needs me" is the main thing Home is for. Answering must be obvious. | Small. |
| L6 | **Removing a project.** *Remove from Diorama* can't be reached from the kitchen view. Re-adding a project gives it a new identity, so its earlier conversations don't re-attach. | Users will add the wrong folder and need a way out. Re-adding looks like losing history. | Small for the menu; medium to re-attach by folder. |

**Lower priority** (polish; these don't block the core flows):
- The review sheet's title and suggested commit message describe the *first* request even after the agent was asked for something else.
- The PR sheet says "checks running" with merge disabled for up to 2 minutes when a repo has no CI, without explaining that it's waiting for CI to appear.
- At small window sizes the launch screen cuts off its Codex and Claude cards.
- A full break room (its 10-chef cap) packs the rug, and the emoji bubbles hide under the chefs' hats.
- An unexplained macOS prompt asked to let "Diorama" access the Documents folder; it was declined. It most likely came from the other copy in `~/Documents/ChatGPT/Diorama`, but that's worth confirming before launch.

**Not covered in this pass:**
- VoiceOver run live: labels were reviewed in code, but the accessibility API wasn't available to my tools.
- 10+ agents on one card (I tested 8 across projects).
- An agent that fails.
- Real CI checks on a PR.

## Personas

Full details are in [PERSONAS.md](PERSONAS.md).
1. **Sam, solo developer:** one agent at a time; checks in now and then. "Is it done? Does it need me?"
2. **Priya, power user:** many projects, 8–10 agents on Claude and Codex, keyboard-first, watches ranking and usage.
3. **Noor, newcomer:** one project and has never run an agent.

## Setup
- **Sample projects in `~/Diorama`** (folders kept):
  - `kitchen-check`: a git repo with tests.
  - `kitchen-check-2`: a git repo with a fake github.com remote.
  - `kitchen-check-plain`: a plain folder.
  - `kitchen-check-with-a-really-long-project-name-for-layout-checks`: a git repo with a fake GitLab remote.
- **Tasks:** about 25 small tasks on Codex (GPT-6.1-Sol and GPT-6-Astra) and Claude (Haiku 5.5), started from both the Create modal and Home's New task. They covered:
  - editing (renames, docstrings, comments);
  - testing (`sleep N && python3 -m unittest`);
  - reading (NOTES.md summaries);
  - questions answered after about 2 minutes;
  - quick one-liners.

  Up to 8 ran at once across two projects.
- **Merges:** one local merge, and one real GitHub PR on a throwaway private repo that was then deleted.

## Problems found and fixed

Each entry: what I did → what I expected → what happened → the fix → files changed.

### Home

1. **Home stayed on the last section.**
   - **Did / expected:** came back to Home after starting a question task; expected Needs you.
   - **Got:** it stayed on Recent projects.
   - **Fix:** Home re-opens on Needs you, else Active, else Recent every time it's shown, and entering a section starts at its top card.
   - **Files:** `HomeView.swift`. Media: `home-stuck-on-recent-before.jpg`, `home-opens-needs-you-after.jpg`.
2. **"Signed out · Reconnect" right after launch.**
   - **Did / expected:** launched the app; expected connected (the launch screen said so).
   - **Got:** both Claude Code and Codex read Signed out, because Home read the connection status before the first check finished.
   - **Fix:** Home waits for a settled check, like the launch screen does. Home also refreshes GitHub's status (the old sidebar button used to).
   - **Files:** `HomeModel.swift`, `HomeView.swift`. Media: `connections-signed-out-before.jpg`, `connections-after.jpg`.
3. **Ranking rule (decided with you).**
   - **Needs you:** projects with any agent waiting, most waiting first. They appear only there until answered.
   - **Active:** projects with agents working or finished-but-unread, ranked by most working, then most unread.
   - **Quiet agents:** an agent reported running but silent for 30 minutes no longer counts as working. Abandoned sessions led Active forever before.
   - **Recent:** everything else.
   - **Files:** `HomeModel.swift`, `HomeCards.swift`, `HomeTests.swift`. Media: `home-live-first-after.jpg`, `home-rerank.mp4`.
4. **Finished rows said "Waiting for a task".**
   - **Did / expected:** looked at an unread finished task in Active; expected it to read as something to review.
   - **Got:** it showed the sidebar's idle line.
   - **Fix:** it now says "Not opened yet".
   - **Files:** `HomeCards.swift`. Media: `active-done-waiting-for-task-before.jpg`, `active-not-opened-yet-after.jpg`.
5. **Read work stayed "to review".**
   - **Did / expected:** opened a finished task's result through Review N; expected the count to drop.
   - **Got:** it stayed at 6.
   - **Fix:** done work you've read is no longer unread on Home.
   - **Files:** `HomeModel.swift`.
6. **Small windows broke the layout.**
   - **Did:** resized the window to its minimum.
   - **Got:** the card row ran under the usage cards, and the front card's content spilled out.
   - **Fix:**
     - the row height follows the window;
     - the front card is at least 600 pt wide and its hero narrows;
     - the count pills drop their labels when tight;
     - long names wrap to 3 lines.
   - **Files:** `HomeCards.swift`, `HomeRecent.swift`, `HomeView.swift`. Media: `home-min-window-before.jpg`, `home-min-window-after.jpg`, `home-fullscreen-after.jpg`.
7. **The Recent count ignored the search.**
   - **Got:** the section badge said 12 while showing "1 of 3".
   - **Fix:** the badge counts matches.
   - **Files:** `HomeView.swift`.
8. **Reduce Motion still animated the cards.**
   - **Did:** turned Reduce Motion on and pressed →.
   - **Got:** the cards still slid and scaled.
   - **Fix:** with Reduce Motion on, cards and sections switch instantly.
   - **Files:** `HomeCards.swift`, `HomeView.swift`.
9. **VoiceOver heard identical buttons.**
   - **Got:** every card's buttons were "New task" and "Open kitchen".
   - **Fix:** they're now "New task in kitchen-check" and "Open kitchen-check's kitchen".
   - **Files:** `HomeCards.swift`, `HomeRecent.swift`.
10. **Open kitchen kept an old conversation open.**
    - **Did / expected:** Open kitchen from a card; expected just the kitchen.
    - **Got:** the last conversation panel stayed open.
    - **Fix:** the panel closes.
    - **Files:** `HomeView.swift`. Media: `open-kitchen-panel-before.jpg`, `open-kitchen-tags-after.jpg`.
11. **The back cards overflowed the window.** The cards behind ran off the right edge. They're now spaced to finish inside the row. **Files:** `HomeCards.swift`.

### Kitchen

12. **The manager stood inside the waiting chef.**
    - **Did / expected:** let a chef wait at the gong; expected the manager to stand across from it.
    - **Got:** they stood shoulder to shoulder, because the manager's spot was measured from the gong-strike spot, not the waiting spot.
    - **Fix:** the manager targets where the chef is going and keeps 1.6 m clear.
    - **Files:** `KitchenSceneSurface.swift`, `KitchenAgents.swift`. Media: `manager-too-close-before.jpg`, `manager-spacing-after.jpg`, `gong-and-manager.mp4`.
13. **Name tags drifted across the room.**
    - **Did:** had 7 chefs at the serving window.
    - **Got:** tags stacked upward over other stations.
    - **Fix:** a tag pushed more than 3 tag-heights away hides until hover or selection; the sidebar still lists the agent.
    - **Files:** `KitchenSceneSurface.swift`. Media: `tags-drift-before.jpg`, `open-kitchen-tags-after.jpg`.
14. **Carried items floated in the air.**
    - **Got:** the suspect you named was real. Arriving somewhere with no counter (break room, gong), the item was "set down" at counter height in mid-air.
    - **Fix:** there it vanishes in a poof instead.
    - **Files:** `PantryCarry.swift`. Media: `working-done-break-room.mp4`.
15. **The pantry card followed you.** The pantry card stayed open when switching projects. It now closes. **Files:** `SpatialWorkspaceView.swift`.

### Other

16. **The project-unavailable screen was squeezed into a corner.**
    - **Did:** moved a project's folder while it was open.
    - **Got:** the Retry / Locate screen sat in the top-left of an empty window.
    - **Fix:** it's centred.
    - **Files:** `WorkspaceShell.swift`. Media: `unavailable-before.jpg`, `unavailable-after.jpg`.

## Checked and working

### Kitchen
- **Stations:**
  - editing and commands at the cooking island and stove;
  - tests at tasting;
  - questions at the gong ("Needs you");
  - finished work at the serving window with a plate;
  - accepted or idle chefs in the break room.
- **Gong:** one strike with sound. The manager walks from the dining door to whoever waited longest, both talk, and the manager leaves after you answer (`gong-and-manager.mp4`).
- **Break room:** one chef per machine (arcade, vending, espresso), taking turns; the rest in chat circles (`break-room-arcade.jpg`).
- **Name tags** match the sidebar and conversation titles.
- **Motion:** no T-poses or teleporting seen. Chefs path around counters.

### Home
- **Sections:** opens on the right one, the menu order is fixed, and the counts are right.
- **Membership** follows the rule above, and Home updates on its own within seconds.
- **Cards:**
  - **Keys:** ←/→ flip with the swing and wrap; ↑/↓ change sections (`card-flip.mp4`).
  - **Clicks:** clicking a card behind brings it forward. Rapid presses land correctly.
  - **Buttons:** Answer, Review request and Review N open the right conversation. New task opens the Create modal in that project. Open kitchen works.
  - **Recent:** the GitHub / Git (including a GitLab remote) / Local badges are right, and search filters the cards.
- **Connections:**
  - The GitHub modal shows connected as @davidfromkansas.
  - The gear's Connections panel matches Settings.
  - The Claude Code and Codex cards show % used and the reset time.
- **Persistence:** quitting and reopening keeps the section and search.
- **Window sizes:** minimum, about 1100 pt and full screen all lay out correctly.

### Merging
- **Local:** Commit, then Merge into main, in the review sheet. Git confirms the merge commit on `main`, and the chef celebrates and goes to rest (`local-commit-then-merge.jpg`).
- **GitHub:**
  1. Push & open PR… pushed the branch and created PR #1, and the chef went to "tasting".
  2. After the 2-minute wait for CI, the sheet showed "Ready to merge · no checks".
  3. Merge PR merged it on GitHub (`pr-ready-to-merge.jpg`).
  4. Getting there needed the workarounds in L1 and L2 (`pr-no-remote-raw-error.jpg`, `pr-rejected-misleading-error.jpg`, `pr-waiting-for-checks.jpg`).

## Usability notes per persona

- **Sam (solo):**
  - "Does it need me?" takes about 1 second: Home opens on Needs you with an orange Answer button.
  - "Is it done?" also takes about 1 second: green "To review" counts and Review N.
  - Friction: on the question card, *Send answer* is below the fold (L5).
- **Priya (power user):**
  - With 8 agents across 3 projects, the keyboard flow is fast, and the ranking was stable while she watched.
  - Before the quiet-session rule, two abandoned sessions sat at the front of Active ahead of real results; that's fixed.
  - The bottom usage cards answer "how much do I have left" at a glance.
- **Noor (newcomer):**
  - Add project → Find or connect worked first try, and the empty states explain each section.
  - The kitchen is charming but not self-explanatory; the station signs help.
  - The dead ends are getting a local project onto GitHub (L2) and undoing a mistaken add (L6).

## Decisions needed from you

1. **L1 (email privacy):** commit with the GitHub no-reply address automatically, or only explain the error and link to the setting?
2. **L3 (shared store):** OK to give dev builds a separate bundle ID and data folder? Projects added in one wouldn't appear in the other.
3. **L6 (re-adding a project):** should it re-attach the earlier conversations for the same folder?
4. **Break room:** keep the 10-chef cap, or show fewer resting chefs (e.g. 6) so the room reads better?

## Usage

**Test tasks:** about 25 short tasks.
- **Diorama's token counters:** about 1.3M tokens on `kitchen-check` and about 0.95M on `kitchen-check-2`, plus about 0.4M on the merge and PR tasks; roughly **2.7M tokens** in total, mostly cached input.
- **Weekly meters during the session:**
  - Codex went from 11% to 12% used.
  - Claude went from 55% to 60%, but that figure includes this Claude Code session as well as the Haiku test tasks.

## Cleanup done
- **Test tasks:** all finished; none left running.
- **Remotes:** the two fake remotes removed. The test repo's local git identity was reset.
- **GitHub:** `davidfromkansas/diorama-qa-kitchen-check` deleted.
- **Diorama's project list:**
  - The four sample projects are no longer in it. Three were erased by the other Diorama copy's save (L3); `kitchen-check` I removed myself.
  - I backed up `projects.json` before editing it.
  - Folders are kept in `~/Diorama`.
- **Settings and git:** Reduce Motion is back off. Nothing was committed.
