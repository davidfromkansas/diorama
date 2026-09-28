#!/usr/bin/env python3
"""Serve the fully local viewer. No install, CDN, or build step required."""
import argparse, functools, http.server
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--port',type=int,default=8766);args=p.parse_args()
root=Path(__file__).resolve().parent
handler=functools.partial(http.server.SimpleHTTPRequestHandler,directory=str(root))
with http.server.ThreadingHTTPServer(('127.0.0.1',args.port),handler) as server:
    print(f'Capybara studio: http://127.0.0.1:{args.port}/viewer/',flush=True)
    server.serve_forever()
