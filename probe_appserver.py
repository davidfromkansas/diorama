#!/usr/bin/env python3
"""Probe only explicitly supplied thread IDs. Never list/resume/start/interrupt threads."""
import argparse
import collections
import json
import queue
import subprocess
import threading
import time


def probe(ids):
    process = subprocess.Popen(['codex', 'app-server', '--stdio'], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    inbox = queue.Queue()
    def reader():
        for line in process.stdout:
            try:
                inbox.put(json.loads(line))
            except ValueError:
                pass
    threading.Thread(target=reader, daemon=True).start()
    def send(obj):
        process.stdin.write(json.dumps(obj) + '\n')
        process.stdin.flush()
    def request(i, method, params):
        send({'id': i, 'method': method, 'params': params})
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            try:
                item = inbox.get(timeout=max(.01, deadline-time.monotonic()))
            except queue.Empty:
                break
            if item.get('id') == i:
                return item
        return {'error': {'message': 'No response within 20 seconds'}}
    results = []
    try:
        init = request(1, 'initialize', {'clientInfo': {'name': 'diorama_access_probe', 'version': '0.1.0'}, 'capabilities': {'experimentalApi': True}})
        results.append({'operation': 'initialize', 'ok': 'result' in init, 'error': init.get('error')})
        if 'error' in init:
            return results
        send({'method': 'initialized', 'params': {}})
        for i, sid in enumerate(ids, 2):
            reply = request(i, 'thread/read', {'threadId': sid, 'includeTurns': True})
            thread = reply.get('result', {}).get('thread', {})
            turns = thread.get('turns', [])
            counts = collections.Counter(item.get('type', 'unknown') for turn in turns for item in turn.get('items', []))
            results.append({'operation': 'thread/read', 'thread_id': sid, 'ok': 'result' in reply,
                            'error': reply.get('error'), 'turn_count': len(turns), 'item_types': dict(counts),
                            'status': thread.get('status'), 'thread_fields': sorted(thread)})
        return results
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('thread_ids', nargs='+')
    print(json.dumps(probe(parser.parse_args().thread_ids), indent=2))
