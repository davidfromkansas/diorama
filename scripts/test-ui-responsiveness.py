#!/usr/bin/env python3
"""Run the offline UI regression after `swift build -c release --build-tests -Xswiftc -enable-testing`.

An external deadline also catches a blocked main thread, which an in-process
Swift concurrency timeout cannot reliably interrupt. No development app is killed.
"""
import os
from pathlib import Path
import signal
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
process = subprocess.Popen(
    ["swift", "test", "-c", "release", "--skip-build", "--no-parallel",
     "--filter", sys.argv[1] if len(sys.argv) > 1 else "conversationSettlesAfterResize"],
    cwd=root,
    start_new_session=True,
)
try:
    sys.exit(process.wait(timeout=60))
except subprocess.TimeoutExpired:
    print("UI responsiveness regression exceeded 60 seconds; stopping only its test process group.", file=sys.stderr)
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    sys.exit(124)
