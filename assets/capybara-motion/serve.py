#!/usr/bin/env python3
import http.server,functools
from pathlib import Path
root=Path(__file__).resolve().parent.parent
with http.server.ThreadingHTTPServer(('127.0.0.1',8767),functools.partial(http.server.SimpleHTTPRequestHandler,directory=str(root))) as server:
 print('Capybara motion lab: http://127.0.0.1:8767/capybara-motion/',flush=True)
 server.serve_forever()
