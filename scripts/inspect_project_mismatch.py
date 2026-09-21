"""Read only designated project/thread metadata after Desktop folder addition."""
import json,pathlib
from probe_rpc import RPC
p=pathlib.Path('.local/project-discovery/evidence.json');e=json.loads(p.read_text());r=RPC(['--stdio']);out={}
try:
 cursor=None;matches=[]
 while True:
  reply=r.call('project/list',{'limit':100,'cursor':cursor})
  matches.extend(x for x in reply['data'] if 'Diorama Created Project Test' in x['name'] or any(y['path']==e['create_params']['roots'][0]['path'] for y in x['roots']))
  cursor=reply.get('nextCursor')
  if not cursor:break
 out['matching_projects']=matches
 t=r.call('thread/read',{'threadId':e['created_project_thread']['id'],'includeTurns':False})['thread']
 out['thread']={k:t.get(k) for k in ['id','projectId','cwd','source','name']}
finally:r.close()
p=pathlib.Path('.local/project-discovery/desktop-comparison.json');p.write_text(json.dumps(out,indent=2));print(json.dumps(out,indent=2))
