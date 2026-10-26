"""Diorama Kitchen for Hermes: watch a session's agents work as chefs in a live 3D kitchen.

The hooks pass each step (a request, a tool call, a subagent, a question for you) to the
kitchen's local server; ``/kitchen`` opens the kitchen for the session it is typed in. In
Hermes Desktop the kitchen opens in a tab inside the app; elsewhere, in your browser.
The kitchen only watches: every hook returns nothing and never changes a turn.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys

from . import hermes_bridge as bridge

def _session(kwargs):
    return kwargs.get("session_id") or kwargs.get("task_id") or ""


def _exit_code(result):
    try:
        parsed = json.loads(result) if isinstance(result, str) else result
        if isinstance(parsed, dict):
            for key in ("exit_code", "returncode"):
                if isinstance(parsed.get(key), int):
                    return parsed[key]
    except Exception:
        pass
    return None


def on_session_start(**kwargs):
    bridge.send("on_session_start", _session(kwargs), model=kwargs.get("model"), platform=kwargs.get("platform"))


def pre_llm_call(**kwargs):
    bridge.send("pre_llm_call", _session(kwargs), turn_id=kwargs.get("turn_id"), user_message=bridge.text_of(kwargs.get("user_message")),
                model=kwargs.get("model"), parent_session_id=kwargs.get("parent_session_id") or None, platform=kwargs.get("platform"))


def on_interim_message(**kwargs):
    bridge.send("on_interim_message", _session(kwargs), turn_id=kwargs.get("turn_id"), text=bridge.clip(kwargs.get("text")))


def pre_tool_call(**kwargs):
    bridge.send("pre_tool_call", _session(kwargs), turn_id=kwargs.get("turn_id"), tool_name=kwargs.get("tool_name"),
                tool_call_id=kwargs.get("tool_call_id") or None, args=bridge.clip_args(kwargs.get("args") or {}))


def post_tool_call(**kwargs):
    bridge.send("post_tool_call", _session(kwargs), turn_id=kwargs.get("turn_id"), tool_name=kwargs.get("tool_name"),
                tool_call_id=kwargs.get("tool_call_id") or None, status=kwargs.get("status"),
                error_message=bridge.clip(kwargs.get("error_message"), 300), exit_code=_exit_code(kwargs.get("result")),
                duration_ms=kwargs.get("duration_ms"))


def post_llm_call(**kwargs):
    bridge.send("post_llm_call", _session(kwargs), turn_id=kwargs.get("turn_id"), model=kwargs.get("model"),
                assistant_response=bridge.clip(kwargs.get("assistant_response")))


def on_session_end(**kwargs):
    bridge.send("on_session_end", _session(kwargs), turn_id=kwargs.get("turn_id"), completed=kwargs.get("completed"),
                failed=kwargs.get("failed"), interrupted=kwargs.get("interrupted"), turn_exit_reason=kwargs.get("turn_exit_reason"),
                reason=kwargs.get("reason"))


def subagent_start(**kwargs):
    child = kwargs.get("child_session_id") or kwargs.get("child_subagent_id")
    bridge.send("subagent_start", kwargs.get("parent_session_id"), child_session_id=child, child_subagent_id=kwargs.get("child_subagent_id"),
                child_role=kwargs.get("child_role"), child_goal=bridge.clip(kwargs.get("child_goal")), parent_turn_id=kwargs.get("parent_turn_id"))


def subagent_stop(**kwargs):
    bridge.send("subagent_stop", kwargs.get("parent_session_id"), child_session_id=kwargs.get("child_session_id"),
                child_role=kwargs.get("child_role"), child_status=kwargs.get("child_status"),
                child_summary=bridge.clip(kwargs.get("child_summary"), 500), duration_ms=kwargs.get("duration_ms"))


def on_human_input_request(**kwargs):
    bridge.send("on_human_input_request", _session(kwargs), kind=kwargs.get("kind"), request_id=kwargs.get("request_id"),
                prompt=bridge.clip(kwargs.get("prompt"), 300))


def post_compaction(**kwargs):
    bridge.send("post_compaction", _session(kwargs), old_session_id=kwargs.get("old_session_id"))


def on_session_reset(**kwargs):
    bridge.send("on_session_reset", _session(kwargs), old_session_id=kwargs.get("old_session_id"), new_session_id=kwargs.get("new_session_id"))


HOOKS = (on_session_start, pre_llm_call, on_interim_message, pre_tool_call, post_tool_call, post_llm_call, on_session_end,
         subagent_start, subagent_stop, on_human_input_request, post_compaction, on_session_reset)


def _open_browser(url):
    command = ["open", url] if sys.platform == "darwin" else ["cmd", "/c", "start", "", url] if os.name == "nt" else ["xdg-open", url]
    try:
        subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return True
    except Exception:
        return False


def kitchen_command(raw_args="", session_id=None, **kwargs):
    """/kitchen: opens the kitchen for this session (in Hermes Desktop, as a tab in the app)."""
    session = session_id or kwargs.get("session_key") or bridge.latest_session()
    if not session:
        return "Send a message first, then type /kitchen to watch this session in the kitchen."
    try:
        url = bridge.open_kitchen(session)
    except Exception as error:
        return str(error)
    if os.environ.get("HERMES_DESKTOP") == "1":
        try:
            from hermes_cli.plugin_events import broadcast_plugin_event
            broadcast_plugin_event("diorama-kitchen", "open", {"session": str(session)})
            return f"Opened the kitchen in a new tab. It's also at {url}"
        except Exception:
            pass
    return f"Kitchen {'opened' if _open_browser(url) else 'ready'}: {url}"


def register(ctx):
    for hook in HOOKS:
        ctx.register_hook(hook.__name__, hook)
    ctx.register_command("kitchen", kitchen_command, description="Watch this session's agents work in Diorama's 3D kitchen")
