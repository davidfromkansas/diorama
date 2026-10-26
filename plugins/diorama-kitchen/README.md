# Diorama Kitchen

Watch a Claude Code, Codex or Hermes session's agents work as chefs in Diorama's kitchen, live in your browser (or in a tab inside Hermes Desktop). The main agent and every subagent get a chef; they walk to stations for what they're doing (reading, searching, editing, running commands, tests), raise a hand when they need you, and head to the break room when they're done.

## Install

In a terminal:

```
curl -fsSL https://raw.githubusercontent.com/davidfromkansas/diorama/main/install.sh | bash
```

This downloads only the kitchen (about 70 MB) to `~/.diorama-kitchen`, adds a `diorama-kitchen` command to `~/.local/bin` and, if Claude Code or Hermes is installed, adds the plugin there too. Run it again to update. Needs Node.js 18 or later and git.

## Use

In your project folder, while Claude Code or Codex is working there, run:

```
diorama-kitchen
```

Your browser opens on the kitchen for the newest session in that folder. Add `--claude` or `--codex` to pick a tool when you use both. In Claude Code you can also type `/kitchen` to open the kitchen for that exact session.

**Hermes:** restart Hermes after installing, then type `/kitchen` in a chat. In Hermes Desktop, turn on Diorama Kitchen under **Capabilities → Plugins** once; after that `/kitchen`, the **Kitchen** button in the status bar or ⌘K → **Open kitchen** opens the kitchen in a tab beside the chat, following whichever chat you're in. From a terminal, `diorama-kitchen --hermes` opens the latest Hermes session in your browser.

- **Click a chef** (or its tag) to follow it and open its details: task, plan, files changed this turn and recent steps.
- **Hold or drag a chef** to pick it up and set it down elsewhere.
- **Scroll** to zoom; **arrow keys** and **Q/W** move and turn; **R** resets the view; **Esc** clears the selection; **?** lists the keys.
- **Sound** turns on after your first click; the speaker button mutes it.

To try it without a session, open the page with `?demo` after opening the kitchen once (e.g. `http://127.0.0.1:47811/?demo`).

## How it works

- `diorama-kitchen` (or `/kitchen`) starts a small server on `127.0.0.1` (port 47811, or any free port) and tells it which session to follow.
- For Claude Code, the server reads the session's transcript and its subagents' transcripts, and the plugin's hooks pass along live events such as approvals and subagent starts. For Codex, it reads the session's rollout in `~/.codex/sessions` and those of the subagents it spawns. For Hermes, the same folder is a Hermes plugin (`plugin.yaml`, `__init__.py`): its hooks pass each step to the server, keeping recent ones so a kitchen opened later still sees the session's history, and `desktop/plugin.js` adds the Kitchen tab to Hermes Desktop. Nothing leaves your machine, and the kitchen never changes your session.
- The server stops by itself after 10 minutes with no page open. `diorama-kitchen stop` stops it sooner.

## Developing

The scene's models, textures and sounds come from the Mac app. After changing one there, run `scripts/sync-assets.sh` (needs `ffmpeg`) to copy them in. three.js is vendored in `web/js/vendor` under its MIT license (`THREE_LICENSE`).
