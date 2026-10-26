"""Backend for the kitchen tab in Hermes Desktop, mounted at /api/plugins/diorama-kitchen/.

``GET /open?session=<id>`` starts the kitchen's local server if needed and returns the page
address for that session, with the key that lets the app's sandboxed frame read it.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

from fastapi import APIRouter

router = APIRouter()


def _bridge():
    name = "diorama_kitchen_hermes_bridge"
    if name not in sys.modules:
        spec = importlib.util.spec_from_file_location(name, Path(__file__).resolve().parent.parent / "hermes_bridge.py")
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module
        spec.loader.exec_module(module)
    return sys.modules[name]


@router.get("/open")
def open_kitchen(session: str = ""):
    bridge = _bridge()
    session = session or bridge.latest_session() or ""
    if not session:
        return {"ok": False, "error": "Send a message in a chat first, then open the kitchen."}
    try:
        state = bridge.ensure_server()
        watched = bridge._post(state["port"], "/api/watch", {"session": session, "provider": "hermes"})
        return {"ok": True, "session": session, "url": watched.get("url"), "embed": watched.get("embed")}
    except Exception as error:
        return {"ok": False, "error": str(error)}
