#!/usr/bin/env python3
"""Resume only the designated Codex probe, observe concurrently, emit content-free evidence."""
import json
import subprocess
import time
from pathlib import Path
from diagnostic import Transcript

manifest = json.loads(Path('.local/manifest.json').read_text())
config = next(s for s in manifest['sources'] if s['label'] == 'Codex CLI isolated probe')
source = Transcript(config)
source.poll()
sid = source.session_id
before = source.offset
states = []
with open('.local/evidence/codex-resume.jsonl', 'w') as stdout, open('.local/evidence/codex-resume.stderr', 'w') as stderr:
    process = subprocess.Popen(['codex', 'exec', '--ignore-user-config', '--json', 'resume', sid,
        'Diorama observation test: run the shell command /bin/sleep 3 once, then reply exactly DIORAMA_CODEX_RESUMED_OK. Do not read or change any files.'],
        stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr)
    deadline = time.monotonic() + 60
    grew_while_running = False
    reconnect_equal = None
    while process.poll() is None and time.monotonic() < deadline:
        source.poll()
        if not states or states[-1] != source.state:
            states.append(source.state)
        if source.offset > before:
            grew_while_running = True
        if reconnect_equal is None and source.state == 'working':
            replacement = Transcript(config)
            replacement.poll()
            reconnect_equal = replacement.session_id == source.session_id and replacement.offset >= source.offset
            source = replacement
        time.sleep(.25)
    timed_out = process.poll() is None
    if timed_out:
        process.terminate()
    try:
        code = process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        code = process.wait()
    source.poll()
    states.append(source.state)
    result = {'session_id': sid, 'returncode': code, 'timed_out': timed_out,
              'grew_while_cli_running': grew_while_running, 'states_observed': states,
              'observer_recreated_during_run': reconnect_equal, 'bytes_added': source.offset-before,
              'tool_call_seen': any(e['kind'] == 'tool call' for e in source.entries),
              'tool_result_seen': any(e['kind'] == 'tool result' for e in source.entries),
              'method': 'existing CLI transcript polled every 250ms; observer objects recreated without controlling CLI'}
    Path('.local/evidence/live-codex.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))
