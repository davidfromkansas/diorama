---
description: Open a live 3D office that shows what this session's agents are doing
allowed-tools: Bash(node:*)
---

!`node ${CLAUDE_PLUGIN_ROOT}/scripts/kitchen.mjs open ${CLAUDE_SESSION_ID} office`

The line above is the result of opening the office view for this session. Reply with one short sentence that gives the user the office link from it (or, if it says something went wrong, what it says to do). Do not run any tools or do anything else.
