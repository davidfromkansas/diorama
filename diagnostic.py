#!/usr/bin/env python3
"""Read-only, explicitly allowlisted agent transcript observer. Standard library only."""
import argparse
import collections
import json
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


def text_content(value):
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return '\n'.join(x.get('text', '') for x in value
                         if isinstance(x, dict) and x.get('type') in ('text', 'input_text', 'output_text'))
    return json.dumps(value, ensure_ascii=False)


class Transcript:
    def __init__(self, config):
        self.config = config
        self.path = Path(config['path']).expanduser().resolve()
        self.provider = config['provider']
        if self.provider not in ('codex', 'claude', 'hooks'):
            raise ValueError('provider must be codex, claude, or hooks')
        self.offset = 0
        self.identity = None
        self.reset()

    def reset(self):
        self.entries = collections.deque(maxlen=2000)
        self.counts = collections.Counter()
        self.session_id = None
        self.project = None
        self.parent = self.config.get('parent_id')
        self.state = 'unavailable'
        self.state_at = None
        self.error = None
        self.last_observed = None
        self.malformed = 0
        self.seen = set()

    def add(self, kind, body, record, call_id=None):
        self.entries.append({'kind': kind, 'text': text_content(body),
                             'timestamp': record.get('timestamp'), 'call_id': call_id})

    def status(self, state, record):
        self.state = state
        self.state_at = record.get('timestamp')

    def consume(self, r):
        if not isinstance(r, dict):
            self.malformed += 1
            return
        self.last_observed = time.time()
        t = r.get('type', '')
        self.counts[t or r.get('hook_event_name', 'unknown')] += 1
        if self.provider == 'codex':
            p = r.get('payload', {})
            if not isinstance(p, dict):
                return
            if t == 'session_meta':
                self.session_id = p.get('id') or p.get('session_id')
                self.project = p.get('cwd')
                self.source = p.get('source')
            elif t == 'event_msg':
                state = {'task_started': 'working', 'task_complete': 'completed',
                         'turn_aborted': 'interrupted'}.get(p.get('type'))
                if state:
                    self.status(state, r)
                    self.add('event', p.get('type'), r)
            elif t == 'response_item':
                k = p.get('type')
                if k == 'message' and p.get('role') in ('user', 'assistant'):
                    self.add(p['role'], p.get('content', []), r)
                elif k in ('function_call', 'custom_tool_call'):
                    self.add('tool call', p.get('name', '') + '\n' + text_content(p.get('arguments', p.get('input', ''))), r, p.get('call_id'))
                elif k in ('function_call_output', 'custom_tool_call_output'):
                    self.add('tool result', p.get('output', ''), r, p.get('call_id'))
                # System/developer instructions, hidden reasoning and encrypted blobs are excluded.
        elif self.provider == 'claude':
            self.session_id = r.get('sessionId', self.session_id)
            self.project = r.get('cwd', self.project)
            # parentUuid is a MESSAGE pointer, not a parent-agent/session id.
            if t in ('user', 'assistant'):
                message = r.get('message', {})
                if not isinstance(message, dict):
                    return
                uid = r.get('uuid')
                if uid and uid in self.seen:
                    return
                if uid:
                    self.seen.add(uid)
                content = message.get('content', [])
                if isinstance(content, str):
                    self.add(t, content, r)
                elif isinstance(content, list):
                    for block in content:
                        if not isinstance(block, dict):
                            continue
                        kind = block.get('type')
                        if kind == 'text':
                            self.add(t, block.get('text', ''), r)
                        elif kind == 'tool_use':
                            self.add('tool call', block.get('name', '') + '\n' + text_content(block.get('input', {})), r, block.get('id'))
                        elif kind == 'tool_result':
                            self.add('tool result', block.get('content', ''), r, block.get('tool_use_id'))
                # A last assistant message is NOT proof that the agent has finished.
        else:
            self.session_id = r.get('session_id', self.session_id)
            self.project = r.get('cwd', self.project)
            event = r.get('hook_event_name', 'unknown')
            states = {'UserPromptSubmit': 'working', 'PreToolUse': 'working',
                      'PermissionRequest': 'waiting for approval', 'Stop': 'completed',
                      'Interrupt': 'interrupted', 'SessionEnd': 'ended'}
            if event in states:
                self.status(states[event], r)
            self.add('event', {k: r[k] for k in ('hook_event_name', 'tool_name', 'agent_id', 'agent_type') if k in r}, r)

    def poll(self):
        try:
            stat = self.path.stat()
            identity = (stat.st_dev, stat.st_ino)
            if self.identity != identity or stat.st_size < self.offset:
                self.offset = 0
                self.reset()
            self.identity = identity
            with self.path.open('rb') as stream:
                stream.seek(self.offset)
                # Bound each poll; a growing source must not monopolize the observer.
                for _ in range(5000):
                    line = stream.readline(4 * 1024 * 1024 + 1)
                    if not line or not line.endswith(b'\n'):
                        if len(line) > 4 * 1024 * 1024:
                            self.error = 'Record exceeds 4 MiB; observation paused at this record'
                            return
                        break  # retry incomplete record on next poll
                    self.offset = stream.tell()
                    try:
                        self.consume(json.loads(line))
                    except (ValueError, TypeError, AttributeError):
                        self.malformed += 1
            self.error = None
        except OSError as exc:
            self.error = str(exc)

    def snapshot(self):
        return {'label': self.config.get('label', self.path.name), 'provider': self.provider,
                'client': self.config.get('client', 'unclassified'), 'session_id': self.session_id,
                'project': self.project, 'parent_id': self.parent, 'path': str(self.path),
                'state': self.state, 'state_at': self.state_at, 'last_observed': self.last_observed,
                'error': self.error, 'malformed': self.malformed, 'counts': dict(self.counts),
                'method': 'version-dependent transcript parsing' if self.provider != 'hooks' else 'hook event file',
                'entries': list(self.entries), 'bytes_read': self.offset,
                'limitations': 'Last recorded state, not a heartbeat. 1-second polling; source flush latency unknown. Most recent 2,000 entries shown. No inferred title, approval, subagent, or completion state.'}


class Observer:
    def __init__(self, manifest):
        data = json.loads(Path(manifest).read_text())
        self.sources = [Transcript(c) for c in data['sources']]
        self.lock = threading.Lock()

    def snapshot(self):
        with self.lock:
            for source in self.sources:
                source.poll()
            return {'observed_at': time.time(), 'sources': [s.snapshot() for s in self.sources]}


def handler_for(observer, token):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            expected = '127.0.0.1:' + str(self.server.server_port)
            if self.headers.get('Host') != expected:
                self.send_error(403)
                return
            path = urlsplit(self.path).path
            if path == '/api/snapshot':
                if not secrets.compare_digest(self.headers.get('Authorization', ''), 'Bearer ' + token):
                    self.send_error(401)
                    return
                content = json.dumps(observer.snapshot(), ensure_ascii=False).encode()
                mime = 'application/json'
            elif path in ('/', '/viewer.js', '/style.css'):
                name = {'/': 'index.html', '/viewer.js': 'viewer.js', '/style.css': 'style.css'}[path]
                content = (Path(__file__).parent / 'viewer' / name).read_bytes()
                mime = {'/': 'text/html', '/viewer.js': 'text/javascript', '/style.css': 'text/css'}[path]
            else:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header('Content-Type', mime + '; charset=utf-8')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Referrer-Policy', 'no-referrer')
            self.send_header('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'")
            self.send_header('Content-Length', str(len(content)))
            self.end_headers()
            self.wfile.write(content)
    return Handler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--manifest', required=True, help='Explicit file allowlist; never scans home directories')
    parser.add_argument('--port', type=int, default=0, help='0 selects an available loopback port')
    parser.add_argument('--snapshot', action='store_true')
    args = parser.parse_args()
    observer = Observer(args.manifest)
    if args.snapshot:
        print(json.dumps(observer.snapshot(), indent=2))
        return
    token = secrets.token_urlsafe(32)
    server = ThreadingHTTPServer(('127.0.0.1', args.port), handler_for(observer, token))
    print('Open http://127.0.0.1:%d/#%s' % (server.server_port, token), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
