# Diorama Kitchen for Claude Code

Watch a Claude Code session's agents work as chefs in Diorama's kitchen, live in your browser. The main agent and every subagent get a chef; they walk to stations for what they're doing (reading, searching, editing, running commands, tests), raise a hand when they need you, and head to the break room when they're done.

## Install

```
/plugin marketplace add davidfromkansas/diorama
/plugin install diorama-kitchen@diorama
```

Needs Node.js 18 or later on your PATH.

## Use

Run `/kitchen` in any Claude Code session. Your browser opens on that session's kitchen and the command prints its address. Run it in another session to open that session's kitchen in a new tab.

- **Click a chef** (or its tag) to follow it and open its details: task, plan, files changed this turn and recent steps.
- **Hold or drag a chef** to pick it up and set it down elsewhere.
- **Scroll** to zoom; **arrow keys** and **Q/W** move and turn; **R** resets the view; **Esc** clears the selection; **?** lists the keys.
- **Sound** turns on after your first click; the speaker button mutes it.

To try it without a session, open the page with `?demo` after running `/kitchen` once (e.g. `http://127.0.0.1:47811/?demo`).

## How it works

- `/kitchen` starts a small server on `127.0.0.1` (port 47811, or any free port) and tells it which session to follow.
- The server reads the session's transcript and its subagents' transcripts, and the plugin's hooks pass along live events such as approvals and subagent starts. Nothing leaves your machine, and the kitchen never changes your session.
- The server stops by itself after 10 minutes with no page open. `node <plugin>/scripts/kitchen.mjs stop` stops it sooner.

## Developing

The scene's models, textures and sounds come from the Mac app. After changing one there, run `scripts/sync-assets.sh` (needs `ffmpeg`) to copy them in. three.js is vendored in `web/js/vendor` under its MIT license (`THREE_LICENSE`).
