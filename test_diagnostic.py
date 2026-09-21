import json
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from http.server import ThreadingHTTPServer
from diagnostic import Transcript, Observer, handler_for


class TranscriptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)/'test.jsonl'
        self.path.touch()

    def append(self, record):
        with self.path.open('a') as f:
            f.write(json.dumps(record)+'\n')

    def source(self, provider='codex'):
        return Transcript({'path': str(self.path), 'provider': provider})

    def test_codex_messages_tools_status_and_exclusions(self):
        s = self.source()
        for t,p in [('session_meta', {'id':'a','cwd':'/project'}),
                    ('event_msg', {'type':'task_started'}),
                    ('response_item', {'type':'message','role':'user','content':[{'type':'input_text','text':'hello'}]}),
                    ('response_item', {'type':'function_call','name':'exec','arguments':'ls','call_id':'c'}),
                    ('response_item', {'type':'function_call_output','output':'done','call_id':'c'}),
                    ('response_item', {'type':'reasoning','summary':'PRIVATE'}),
                    ('response_item', {'type':'message','role':'system','content':'PRIVATE'}),
                    ('event_msg', {'type':'task_complete'})]:
            self.append({'type':t,'payload':p})
        s.poll()
        self.assertEqual(s.session_id,'a')
        self.assertEqual(s.project,'/project')
        self.assertEqual(s.state,'completed')
        self.assertEqual(len(s.entries),5)
        self.assertNotIn('PRIVATE',json.dumps(s.snapshot()))
        s.poll()
        self.assertEqual(len(s.entries),5)

    def test_partial_utf8_append_and_reconnect(self):
        raw = json.dumps({'type':'response_item','payload':{'type':'message','role':'assistant','content':'月'}},ensure_ascii=False).encode()+b'\n'
        split = raw.index('月'.encode())+1
        self.path.write_bytes(raw[:split]); s=self.source();s.poll()
        self.assertEqual(len(s.entries),0)
        with self.path.open('ab') as f:f.write(raw[split:])
        s.poll();self.assertEqual(s.entries[0]['text'],'月')
        restarted=self.source();restarted.poll()
        self.assertEqual(list(s.entries),list(restarted.entries))

    def test_malformed_and_rotation(self):
        self.path.write_text('bad\n[]\n')
        s=self.source();s.poll();self.assertEqual(s.malformed,2)
        self.path.unlink();self.path.touch()
        self.append({'type':'session_meta','payload':{'id':'new'}})
        s.poll();self.assertEqual(s.session_id,'new')

    def test_missing_source(self):
        s=self.source();self.path.unlink();s.poll()
        self.assertIsNotNone(s.error)
        self.assertEqual(s.state,'unavailable')

    def test_claude_blocks_no_inferred_completion_or_parent(self):
        self.append({'type':'assistant','uuid':'u','sessionId':'s','parentUuid':'message-not-agent','cwd':'/p','message':{'content':[{'type':'text','text':'hello'},{'type':'thinking','thinking':'PRIVATE'},{'type':'tool_use','id':'c','name':'Read','input':{'path':'x'}}]}})
        self.append({'type':'user','sessionId':'s','message':{'content':[{'type':'tool_result','tool_use_id':'c','content':[{'type':'text','text':'result'}]}]}})
        s=self.source('claude');s.poll()
        self.assertEqual(len(s.entries),3)
        self.assertEqual(s.state,'unavailable')
        self.assertIsNone(s.parent)
        self.assertNotIn('PRIVATE',json.dumps(s.snapshot()))

    def test_hooks_approval_interrupt(self):
        s=self.source('hooks')
        self.append({'session_id':'s','hook_event_name':'PermissionRequest','tool_name':'Bash'})
        s.poll();self.assertEqual(s.state,'waiting for approval')
        self.append({'session_id':'s','hook_event_name':'Interrupt'})
        s.poll();self.assertEqual(s.state,'interrupted')

    def test_observer_allowlist_concurrency_and_http_access(self):
        manifest=Path(self.temp.name)/'manifest.json'
        other=Path(self.temp.name)/'unrelated.jsonl';other.write_text('SECRET')
        manifest.write_text(json.dumps({'sources':[{'provider':'codex','path':str(self.path)},{'provider':'claude','path':str(self.path)}]}))
        observer=Observer(manifest)
        server=ThreadingHTTPServer(('127.0.0.1',0),handler_for(observer,'test-token'))
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        try:
            url='http://127.0.0.1:%s'%server.server_port
            with self.assertRaises(urllib.error.HTTPError) as e:urllib.request.urlopen(url+'/api/snapshot')
            self.assertEqual(e.exception.code,401)
            req=urllib.request.Request(url+'/api/snapshot',headers={'Authorization':'Bearer test-token'})
            with urllib.request.urlopen(req) as response:data=json.load(response)
            self.assertEqual(len(data['sources']),2)
            self.assertNotIn('SECRET',json.dumps(data))
            req=urllib.request.Request(url+'/api/snapshot',headers={'Authorization':'Bearer test-token','Host':'evil.example'})
            with self.assertRaises(urllib.error.HTTPError) as e:urllib.request.urlopen(req)
            self.assertEqual(e.exception.code,403)
        finally:
            server.shutdown();server.server_close();thread.join()


if __name__ == '__main__':
    unittest.main()
