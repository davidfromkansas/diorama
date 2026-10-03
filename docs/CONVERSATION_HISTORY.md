# Conversation history presentation

Conversation is the default history mode. It retains messages, proposed plans, reported task checklists, artifacts, delegation, and failures. Consecutive routine tool records are grouped within provider and turn boundaries. Expanding a group reveals the existing tool input/output renderers. Counts describe records, not unique operations or verified outcomes.

Detailed displays every loaded entry using the existing diagnostic renderers, including system context, usage, and source input/output. No history is deleted or reparsed when switching. The mode is a local UI preference, independent of provider execution permissions. The nearest visible scroll anchor is retained, and the composer stays mounted.

Usage opens separately and displays provider reports individually, without summing overlapping response and cumulative totals. Its scope is loaded history. Plan and Tasks shortcuts use the activity snapshot, including observation-only sessions. Requests and approval controls remain outside transcript grouping.

Verification: deterministic projection tests cover grouping boundaries, stable identity, metadata retention, scroll anchors, failures, questions, plans, and artifacts. Existing navigation/rendering tests check the composed session UI. No model calls are needed.
