import json,pathlib
import probe_rpc
probe_rpc.BIN='/Applications/ChatGPT.app/Contents/Resources/codex'
r=probe_rpc.RPC(['--stdio']);root=pathlib.Path('.local/project-discovery');e=json.loads((root/'fresh-desktop-reassignment.json').read_text());d=json.loads((root/'desktop-native-comparison.json').read_text());out={'binary':probe_rpc.BIN,'threads':[]}
try:
 for item in d['threads']:
  t=r.call('thread/read',{'threadId':item['id'],'includeTurns':False})['thread'];out['threads'].append({k:t.get(k) for k in ['id','projectId','cwd','source','cliVersion','section','extra','name']})
 out['project_member_ids']=[t['id'] for t in r.call('thread/list',{'projectId':e['desktop_project_id'],'limit':100})['data']]
finally:r.close()
(root/'bundled-reader-comparison.json').write_text(json.dumps(out,indent=2));print(json.dumps(out,indent=2))
