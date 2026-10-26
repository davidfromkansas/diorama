"""Diorama Kitchen for Hermes: passes a session's activity to the kitchen's local server.

Hermes calls the hooks in ``__init__.py``; each one hands a small, clipped event to ``send()``,
which queues it and returns at once (a hook must never slow a turn or fail a tool). A background
thread posts the events to the server when one is running and keeps the recent ones, so a
kitchen opened later (or a restarted server) still sees the session's history.

``open_kitchen()`` starts the server if needed and returns the page's address for a session.
"""

from __future__ import annotations

import collections
import glob
import itertools
import json
import os
import shutil
import subprocess
import threading
import time
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent
STATE_DIR = Path(os.environ.get("DIORAMA_KITCHEN_HOME") or Path.home() / ".diorama-kitchen")
SERVER_FILE = STATE_DIR / "server.json"
LATEST_FILE = STATE_DIR / "hermes-latest.json"   # for `diorama-kitchen --hermes`
HISTORY_PER_SESSION = 1500
MAX_SESSIONS = 24

_lock = threading.Lock()
_wake = threading.Event()
_history: "collections.OrderedDict[str, collections.deque]" = collections.OrderedDict()
_pending: collections.deque = collections.deque(maxlen=20000)
_thread: threading.Thread | None = None
_server_pid = None
_latest = None
_newest = None
_order = itertools.count()


def clip(value, limit=1000):
    if value is None:
        return None
    if not isinstance(value, str):
        value = str(value)
    return value[:limit]


def text_of(content, limit=2000):
    """A message's text: a plain string, or the text parts of a multimodal message."""
    if isinstance(content, list):
        content = "\n".join(str(part.get("text", "")) for part in content if isinstance(part, dict) and part.get("type") == "text")
    return clip(content, limit) or ""


def clip_args(args, depth=0):
    """Tool arguments with long strings shortened (a written file's content is not needed)."""
    if isinstance(args, str):
        return args[:2000]
    if isinstance(args, dict) and depth < 4:
        return {str(k): clip_args(v, depth + 1) for k, v in list(args.items())[:40]}
    if isinstance(args, (list, tuple)) and depth < 4:
        return [clip_args(v, depth + 1) for v in list(args)[:60]]
    if isinstance(args, (int, float, bool)) or args is None:
        return args
    return clip(args, 200)


def send(event: str, session_id, **fields):
    """Queues one event for the kitchen. Never raises and never blocks."""
    global _newest
    try:
        record = {"provider": "hermes", "event": event, "id": uuid.uuid4().hex, "time": int(time.time() * 1000),
                  "session_id": str(session_id or "")}
        record.update({k: v for k, v in fields.items() if v is not None})
        key = record["session_id"] or "-"
        with _lock:
            record["seq"] = next(_order)
            log = _history.get(key)
            if log is None:
                log = _history[key] = collections.deque(maxlen=HISTORY_PER_SESSION)
                while len(_history) > MAX_SESSIONS:
                    _history.popitem(last=False)
            else:
                _history.move_to_end(key)
            log.append(record)
            _pending.append(record)
            if event == "pre_llm_call" and not record.get("parent_session_id") and record["session_id"]:
                _newest = record["session_id"]
        _ensure_thread()
        _wake.set()
    except Exception:
        pass


def _ensure_thread():
    global _thread
    if _thread is None or not _thread.is_alive():
        _thread = threading.Thread(target=_run, name="diorama-kitchen", daemon=True)
        _thread.start()


def server_state():
    try:
        return json.loads(SERVER_FILE.read_text())
    except Exception:
        return None


def _post(port, route, body, timeout=2.0):
    request = urllib.request.Request(f"http://127.0.0.1:{port}{route}", data=json.dumps(body).encode(), method="POST",
                                     headers={"content-type": "application/json"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read() or b"{}")


def _note_latest():
    """Records the session that last started a turn (subagents aside) for `diorama-kitchen --hermes`."""
    global _latest
    newest = _newest
    if newest and newest != _latest:
        try:
            STATE_DIR.mkdir(parents=True, exist_ok=True)
            LATEST_FILE.write_text(json.dumps({"session": newest, "time": int(time.time() * 1000)}))
            _latest = newest
        except Exception:
            pass


def _run():
    global _server_pid
    while True:
        _wake.wait(timeout=1.5)
        _wake.clear()
        _note_latest()
        state = server_state()
        if not state or not state.get("port"):
            _server_pid = None
            continue
        with _lock:
            if state.get("pid") != _server_pid:
                # A server we haven't talked to: give it everything we remember (ids make repeats harmless).
                batch = [r for log in _history.values() for r in log]
                batch.sort(key=lambda r: r["seq"])
            else:
                batch = list(_pending)
            _pending.clear()
        if not batch:
            _server_pid = state.get("pid")
            continue
        try:
            for start in range(0, len(batch), 500):
                _post(state["port"], "/api/hermes", {"events": batch[start:start + 500]})
            _server_pid = state.get("pid")
        except Exception:
            # Not reachable right now: try again next tick with a fresh look at the server.
            _server_pid = None


# MARK: Opening the kitchen

def _version():
    try:
        return json.loads((ROOT / ".claude-plugin" / "plugin.json").read_text())["version"]
    except Exception:
        return None


def find_node():
    """Node.js 18+: the one the installer recorded, PATH, then the usual install places (apps
    started from the Dock don't get your shell's PATH)."""
    candidates = []
    try:
        candidates.append((STATE_DIR / "node-path").read_text().strip())
    except Exception:
        pass
    candidates.append(shutil.which("node") or "")
    home = str(Path.home())
    candidates += ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node", f"{home}/.volta/bin/node", f"{home}/.local/bin/node"]
    candidates += sorted(glob.glob(f"{home}/.nvm/versions/node/*/bin/node"), reverse=True)
    candidates += sorted(glob.glob(f"{home}/.local/share/fnm/node-versions/*/installation/bin/node"), reverse=True)
    candidates += sorted(glob.glob(f"{home}/.asdf/installs/nodejs/*/bin/node"), reverse=True)
    for path in candidates:
        if not path or not os.path.isfile(path) or not os.access(path, os.X_OK):
            continue
        try:
            out = subprocess.run([path, "-e", "process.stdout.write(process.versions.node)"], capture_output=True, text=True, timeout=5).stdout
            if int(out.split(".")[0]) >= 18:
                return path
        except Exception:
            continue
    return None


def _healthy(state):
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{state['port']}/api/health", timeout=1.5) as response:
            return json.loads(response.read())
    except Exception:
        return None


def ensure_server():
    """The running server's state, starting (or replacing an older) one if needed. Raises with a
    message for the person when it can't."""
    state = server_state()
    health = _healthy(state) if state else None
    version = _version()
    if health and version and health.get("version") != version:
        try:
            os.kill(int(state["pid"]), 15)
        except Exception:
            pass
        time.sleep(0.3)
        health = None
    if health:
        return state
    node = find_node()
    if not node:
        raise RuntimeError("Diorama Kitchen needs Node.js 18 or later (https://nodejs.org). Install it, then try again.")
    env = dict(os.environ, DIORAMA_KITCHEN_HOME=str(STATE_DIR))
    subprocess.Popen([node, str(ROOT / "server" / "server.mjs")], env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True, close_fds=True)
    for _ in range(50):
        time.sleep(0.1)
        state = server_state()
        if state and _healthy(state):
            return state
    raise RuntimeError(f"The kitchen server could not start. Try running: {node} \"{ROOT / 'server' / 'server.mjs'}\"")


def open_kitchen(session_id) -> str:
    """Starts the server if needed, points it at a Hermes session and returns the page address."""
    state = ensure_server()
    session_id = str(session_id or "")
    _wake.set()
    _ensure_thread()
    watched = _post(state["port"], "/api/watch", {"session": session_id, "provider": "hermes"})
    return watched.get("url") or f"http://127.0.0.1:{state['port']}/?session={session_id}&provider=hermes"


def latest_session():
    """The Hermes session that last started a turn (subagents aside), here or in another Hermes process."""
    if _newest:
        return _newest
    try:
        return json.loads(LATEST_FILE.read_text()).get("session")
    except Exception:
        return None
