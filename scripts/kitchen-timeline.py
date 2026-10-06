#!/usr/bin/env python3
"""Lay an agent's kitchen log (what its chef did on screen) next to its conversation.

Usage: scripts/kitchen-timeline.py <agent name or conversation id> [--day YYYY-MM-DD]

Reads ~/Library/Application Support/Diorama/KitchenLog/<day>.jsonl (written by the app) and the
agent's Codex (~/.codex/sessions) or Claude Code (~/.claude/projects) transcript, then prints one
timeline: transcript events on the left, chef moves on the right.
"""
import glob, json, os, re, sys
from datetime import datetime, timezone

HOME = os.path.expanduser("~")
LOG_DIR = os.path.join(HOME, "Library/Application Support/Diorama/KitchenLog")
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")


def parse_time(value):
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (AttributeError, ValueError):
        return None


def kitchen_lines(query, day):
    files = [os.path.join(LOG_DIR, day + ".jsonl")] if day else sorted(glob.glob(os.path.join(LOG_DIR, "*.jsonl")))
    rows = []
    for path in files:
        if not os.path.exists(path):
            continue
        for line in open(path):
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if query.lower() in (row.get("agent", "").lower(), "") or query in row.get("conversation", ""):
                rows.append(row)
    return rows


def short(text, n=90):
    text = " ".join(str(text).split())
    return text if len(text) <= n else text[: n - 1] + "…"


def codex_events(path):
    calls = {}
    for line in open(path):
        r = json.loads(line)
        p, t, time = r.get("payload", {}), r.get("payload", {}).get("type"), parse_time(r.get("timestamp"))
        if r.get("type") == "event_msg" and t in ("task_started", "task_complete", "turn_aborted"):
            yield time, {"task_started": "TURN START", "task_complete": "TURN DONE", "turn_aborted": "TURN STOPPED"}[t]
        elif t == "message" and p.get("role") in ("user", "assistant"):
            text = " ".join(c.get("text", "") for c in p.get("content", []) if isinstance(c, dict))
            if text and not text.startswith("<"):
                yield time, ("YOU  " if p["role"] == "user" else "SAYS ") + short(text)
        elif t in ("custom_tool_call", "function_call"):
            raw = p.get("input") or p.get("arguments") or ""
            m = re.search(r'tools\.(\w+)\((?:\{cmd:"((?:[^"\\]|\\.)*)")?', raw)
            name = m.group(1) if m else p.get("name", "tool")
            detail = (m.group(2) if m and m.group(2) else "")
            if name == "apply_patch":
                detail = ", ".join(os.path.basename(f) for f in re.findall(r"\*\*\* (?:Update|Add) File: ([^\\\n]+)", raw))
            calls[p.get("call_id")] = name
            yield time, "CALL " + short(name + " " + detail.replace("\\n", " "))
        elif t in ("custom_tool_call_output", "function_call_output"):
            out = json.dumps(p.get("output"))
            m = re.search(r'exit_code\\*":(-?\d+)|Process exited with code (-?\d+)', out)
            code = (m.group(1) or m.group(2)) if m else None
            if code not in (None, "0"):
                yield time, "  ✗ " + calls.get(p.get("call_id"), "tool") + f" exit {code}"


def claude_events(path):
    for line in open(path):
        r = json.loads(line)
        time, message = parse_time(r.get("timestamp")), r.get("message") or {}
        content = message.get("content")
        if r.get("type") == "user" and isinstance(content, str):
            yield time, "YOU  " + short(content)
        for block in content if isinstance(content, list) else []:
            kind = block.get("type")
            if kind == "text" and r.get("type") == "assistant":
                yield time, "SAYS " + short(block.get("text", ""))
            elif kind == "tool_use":
                args = block.get("input") or {}
                yield time, "CALL " + short(block.get("name", "") + " " + str(args.get("command") or args.get("file_path") or args.get("skill") or ""))
            elif kind == "tool_result" and block.get("is_error"):
                yield time, "  ✗ tool failed"


def transcript(conversation):
    match = UUID.search(conversation or "")
    if not match:
        return []
    uuid = match.group(0)
    codex = glob.glob(os.path.join(HOME, ".codex/sessions/**/*" + uuid + "*.jsonl"), recursive=True)
    if codex:
        return list(codex_events(codex[0]))
    claude = glob.glob(os.path.join(HOME, ".claude/projects/**/" + uuid + ".jsonl"), recursive=True)
    return list(claude_events(claude[0])) if claude else []


def main():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    query = sys.argv[1]
    day = sys.argv[sys.argv.index("--day") + 1] if "--day" in sys.argv else None
    kitchen = kitchen_lines(query, day)
    conversations = sorted({row.get("conversation", "") for row in kitchen})
    if not kitchen:
        print(f"No kitchen log for {query!r} in {LOG_DIR}"); sys.exit(1)
    for conversation in conversations:
        rows = [r for r in kitchen if r.get("conversation") == conversation]
        events = [(t, text, "") for t, text in transcript(conversation) if t]
        for r in rows:
            station = r.get("station", "")
            what = {"heading": "→ " + station, "arrived": "● at " + station, "jumped": "⇢ jumped to " + station,
                    "emote": "✦ emote " + r.get("emotes", "")}.get(r.get("event"), r.get("event", ""))
            extra = r.get("gesture") or r.get("clip") or r.get("loop") or ""
            events.append((parse_time(r.get("time")), "", f"{what} ({extra})" + (f"  ← {r.get('tool')}" if r.get("event") != "arrived" and r.get("tool") else "")))
        events.sort(key=lambda e: e[0] or datetime.min.replace(tzinfo=timezone.utc))
        print(f"\n{rows[0].get('agent', '?')} · {conversation}\n" + "-" * 120)
        print(f"{'time':8}  {'conversation':78}  kitchen")
        for t, left, right in events:
            local = t.astimezone().strftime("%H:%M:%S") if t else "--:--:--"
            print(f"{local:8}  {left:78}  {right}")


if __name__ == "__main__":
    main()
