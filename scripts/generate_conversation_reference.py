"""Generate a version-pinned reference from Codex's locally exported JSON Schema."""
import argparse
import datetime
import json
from pathlib import Path

ITEMS = {
    "userMessage": ("User text and attached inputs", "Message; attachment placeholders", "Goal / constraints; attachment gallery"),
    "hookPrompt": ("Prompt fragments supplied by a hook", "Collapsed system context", "Context indicator; do not treat as user-authored progress"),
    "agentMessage": ("Assistant message; may include phase, questions and citations", "Markdown message", "Short update or answer; agent explicitly authors canvas conclusions"),
    "functionCallOutput": ("Standalone function output", "Raw tool row", "Recognized result cards; retain provenance"),
    "plan": ("Proposed plan text; schema labels this experimental", "Assistant Markdown", "Plan panel; separate from structured turn/plan/updated steps"),
    "reasoning": ("Reasoning record", "Excluded", "Excluded from canvas and visual summaries"),
    "commandExecution": ("Command, working directory, status and output", "Raw tool row", "Command status / exit code / duration; verification evidence"),
    "fileChange": ("File edits and diffs", "Raw tool row", "Diff cards; changed-file summary"),
    "mcpToolCall": ("MCP tool invocation and result/error", "Raw tool row", "Tool-specific cards, tables or galleries when payload supports them"),
    "dynamicToolCall": ("Dynamic client tool invocation", "Raw tool row; execution requests unsupported", "Recognized output cards; displaying is not permission to execute"),
    "collabAgentToolCall": ("Agent collaboration call and reported agent states", "Raw tool row", "Delegated task cards and dependency flow"),
    "subAgentActivity": ("Subagent thread/path activity", "Raw tool row", "Linked agent activity badge"),
    "webSearch": ("Search/open/find action and optional results", "Raw tool row", "Queries, source cards and research evidence"),
    "imageView": ("Image inspected at a local path", "Inline local preview + raw details", "Image preview; not a historical snapshot"),
    "sleep": ("Interruptible wait duration", "Raw tool row", "Waiting indicator, never fabricated progress"),
    "imageGeneration": ("Generated image result, state and optional saved path", "Raw tool row", "Generation status and image gallery when image data is available"),
    "enteredReviewMode": ("Review started", "Event row", "Review phase marker"),
    "exitedReviewMode": ("Review ended", "Event row", "Review outcome when supplied"),
    "contextCompaction": ("Conversation history compacted", "Event row", "Small context marker; never mark work complete"),
}

def variants(schema, tag):
    return [{"name": item["properties"][tag]["enum"][0],
             "fields": list(item["properties"]),
             "required": item.get("required", []),
             "description": item.get("description", ""),
             "parameters": item["properties"].get("params", {}).get("$ref", "").split("/")[-1]}
            for item in schema["oneOf"]]

def inventory(folder):
    notifications = json.loads((folder / "ServerNotification.json").read_text())
    requests = json.loads((folder / "ServerRequest.json").read_text())
    return {"items": variants(notifications["definitions"]["ThreadItem"], "type"),
            "user_inputs": variants(notifications["definitions"]["UserInput"], "type"),
            "notifications": variants(notifications, "method"),
            "server_requests": variants(requests, "method")}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--schema-dir", type=Path, required=True)
    parser.add_argument("--experimental-dir", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--output-root", type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    normal, experimental = inventory(args.schema_dir), inventory(args.experimental_dir)
    snapshot = {"codex_version": args.version, "generated_on": datetime.date.today().isoformat(),
                "source": "codex app-server generate-json-schema (ordinary and --experimental)",
                "ordinary_export": normal, "experimental_export": experimental}
    root = args.output_root
    (root / "docs").mkdir(exist_ok=True)
    (root / "docs/codex-protocol-inventory.json").write_text(json.dumps(snapshot, indent=2) + "\n")
    lines = ["# Conversation items and events reference", "",
             f"Generated from **Codex CLI {args.version}** on {snapshot['generated_on']}. This is exhaustive for the `ThreadItem`, `UserInput`, `ServerNotification`, and `ServerRequest` unions in this installed version, including comparison with the experimental export. It is not a universal list across providers or future versions. It does not inventory client-initiated request methods or every nested result schema.", "",
             "Source: local CLI schema, with terminology checked against the [official App Server documentation](https://learn.chatgpt.com/docs/app-server). [Machine-readable inventory](docs/codex-protocol-inventory.json). Presence in a schema does not mean an event is emitted in every client/configuration; some ordinary-export types are themselves documented as experimental or deprecated.", "",
             "## Conversation items", "",
             f"**{len(normal['items'])} item types.** Items have an ID and a `type`; turns contain items. Live `item/started` and `item/completed` notifications carry these items. The completed item is authoritative, rather than concatenated streaming deltas.", "",
             "| Type | Meaning | Diorama now | Useful visual / canvas input |", "|---|---|---|---|"]
    for item in normal["items"]:
        meaning, current, visual = ITEMS.get(item["name"], ("New schema item — inspect fields below", "Not audited", "To assess"))
        lines.append(f"| `{item['name']}` | {meaning} | {current} | {visual} |")
    lines += ["", "`collabAgentToolCall` is the current spelling. Diorama also accepts the older `collabToolCall` spelling for compatibility; it is not in this version's union.", "", "### Item fields", "", "Fields below are schema properties, not a promise every value is present/non-null. Required-property lists are in the JSON inventory.", ""]
    for item in normal["items"]:
        lines.append(f"- **`{item['name']}`:** " + ", ".join(f"`{f}`" for f in item["fields"] if f != "type"))
    lines += ["", "## Content inside user messages", "", "These are `UserInput` variants, not separate conversation item types.", "", "| Type | Fields |", "|---|---|"]
    for item in normal["user_inputs"]:
        lines.append(f"| `{item['name']}` | " + ", ".join(f"`{f}`" for f in item["fields"] if f != "type") + " |")
    lines += ["", "## Live notifications", "", f"**{len(normal['notifications'])} methods** in the ordinary export. Notifications have no request ID and do not require a reply. Not all are conversation content: account, filesystem, model, and connection events appear here too.", "",
              "For a live UI, prioritize `turn/started`, `turn/completed`, `thread/status/changed`, `turn/plan/updated`, `turn/diff/updated`, item lifecycle, tool output deltas, and `serverRequest/resolved`. Diorama currently handles a subset. HTML view is agent-authored; it does not pretend these events can mechanically explain architecture or decisions.", "", "| Method | Parameter schema |", "|---|---|"]
    for event in normal["notifications"]:
        lines.append(f"| `{event['name']}` | `{event['parameters']}` |")
    lines += ["", "## Server requests", "", "These carry request IDs and require a response. They are not notifications and must not be answered by an HTML page.", "", "| Method | Parameter schema |", "|---|---|"]
    for event in normal["server_requests"]:
        lines.append(f"| `{event['name']}` | `{event['parameters']}` |")
    lines += ["", "## Experimental export differences", ""]
    for section in normal:
        added = {v["name"] for v in experimental[section]} - {v["name"] for v in normal[section]}
        lines.append(f"- **{section.replace('_', ' ')}:** " + (", ".join(f"`{v}`" for v in sorted(added)) + " added." if added else "No additional union variants."))
    lines += ["", "This comparison concerns variant names; nested experimental fields and provider-specific MCP payloads can still differ.", "", "## How this relates to HTML view", "",
              "The page is a concise, agent-maintained interpretation of the work: goal, current state, diagram, plan, status, decisions/questions, latest changes, and next action. Use commands/diffs/results as evidence, not as a substitute for that interpretation. Keep native execution state outside the document, since a saved page may be stale. Never include hidden reasoning or use canvas content to grant approvals.", "",
              "The native HTML viewer refreshes when its file changes. Maintaining the file is an instruction to the agent, not an event-derived guarantee. See [HTML_VIEW.md](HTML_VIEW.md) for storage, update rules, and limitations.", "", "## Regenerate", "", "```sh",
              "codex --version", "codex app-server generate-json-schema --out /tmp/diorama-schema-stable", "codex app-server generate-json-schema --experimental --out /tmp/diorama-schema-experimental",
              f"python3 scripts/generate_conversation_reference.py --schema-dir /tmp/diorama-schema-stable --experimental-dir /tmp/diorama-schema-experimental --version {args.version}", "```", "",
              "Use the actual installed version in `--version`. Review newly added variants before claiming UI support. Schema generation is offline and does not start an agent turn."]
    (root / "CONVERSATION_ITEMS.md").write_text("\n".join(lines) + "\n")
    print({key: len(value) for key, value in normal.items()})

if __name__ == "__main__":
    main()
