#!/usr/bin/env python3
"""Bounded source-client driver. Never called by Diorama observation.

Run only in the designated disposable project. Reports IDs/counts/times, not bodies.
The CLI's structured stream is source evidence, not proof of displayed pixels.
"""
import argparse
import json
from pathlib import Path
import subprocess
import threading
import time

parser = argparse.ArgumentParser()
parser.add_argument("--folder", required=True)
parser.add_argument("--session", required=True)
parser.add_argument("--output", required=True)
parser.add_argument("--cli", required=True)
parser.add_argument("--provider", choices=["claude", "codex"], default="claude")
args = parser.parse_args()
root = Path(args.folder).resolve()
if not str(root).startswith("/private/tmp/diorama-acceptance-"):
    raise SystemExit("A designated disposable acceptance folder is required")

report = {"source": "Claude Code CLI" if args.provider == "claude" else "Codex CLI", "session": args.session, "turns": [],
          "pixel_latency_measured": False}
for turn in range(1, 4):
    prompt = (f"Disposable viewer verification turn {turn}. Stay inside {root}. "
              "Do exactly eight separate Read tool calls on README.md, one at a time. "
              f"Before each call print VIEWER_V2_CLI_T{turn}_STEP followed by its number. "
              f"Then use Write once to create turn-{turn}.html: a tiny standalone HTML page "
              f"with heading VIEWER_V2_CLI_T{turn}, a counter starting at zero and an increment button. "
              "No remote dependencies, no commands, no other files or external services. "
              f"Finish with VIEWER_V2_CLI_T{turn}_DONE.")
    command = [args.cli, "-p", prompt, "--resume", args.session, "--output-format", "stream-json",
               "--verbose", "--include-partial-messages", "--no-chrome", "--tools", "Read,Write",
               "--allowedTools", "Read,Write"]
    if args.provider == "codex":
        prompt = (f"Disposable Diorama Codex verification turn {turn}. Stay inside {root}. "
                  "Do eight separate read-only command tool calls, one at a time, each running cat README.md. "
                  f"Before each call print VIEWER_V2_CODEX_T{turn}_STEP followed by its number. "
                  f"Then use apply_patch to create codex-turn-{turn}.html, a tiny standalone HTML page "
                  f"with heading VIEWER_V2_CODEX_T{turn} and a counter increment button. "
                  "No network, dependencies, other files or external services. "
                  f"Finish with VIEWER_V2_CODEX_T{turn}_DONE.")
        command = [args.cli, "exec", "--sandbox", "workspace-write", "resume", "--skip-git-repo-check", "--json", args.session, prompt]
    started = time.time()
    samples = []
    with subprocess.Popen(command, cwd=root, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True) as process:
        timeout = threading.Timer(150, process.terminate)
        timeout.start()
        for line in process.stdout:
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            sample = {"received_at": time.time(), "type": event.get("type"), "uuid": event.get("uuid")}
            if event.get("type") == "stream_event":
                sample["subtype"] = event.get("event", {}).get("type")
            if event.get("type") == "result":
                sample.update(subtype=event.get("subtype"), is_error=event.get("is_error"))
            samples.append(sample)
        code = process.wait(timeout=30)
        timeout.cancel()
        # Keep only the exit status; errors can contain personal environment data.
    report["turns"].append({"turn": turn, "started_at": started, "finished_at": time.time(),
                            "exit_code": code, "samples": samples})
    Path(args.output).write_text(json.dumps(report, indent=2))
    print(f"turn={turn} exit={code} source_events={len(samples)}", flush=True)
    if code:
        break
