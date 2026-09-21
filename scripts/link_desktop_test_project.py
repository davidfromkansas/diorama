"""Assign only the designated disposable thread to the Desktop-added test project."""
import json,pathlib
from probe_rpc import RPC
root=pathlib.Path('.local/project-discovery');e=json.loads((root/'evidence.json').read_text());c=json.loads((root/'desktop-comparison.json').read_text())
original=e['project_create']['id'];targets=[p for p in c['matching_projects'] if p['id']!=original and p['roots']==e['create_params']['roots']]
assert len(targets)==1,'Ambiguous designated target'
target=targets[0]['id'];thread=e['created_project_thread']['id'];r=RPC(['--stdio'])
report={'thread_id':thread,'original_project_id':original,'desktop_project_id':target}
def save():(root/'desktop-reassignment.json').write_text(json.dumps(report,indent=2))
try:
 before=r.call('thread/read',{'threadId':thread,'includeTurns':False})['thread'];assert before['projectId']==original
 report['request']={'threadId':thread,'projectId':target};save()
 reply=r.call('thread/metadata/update',report['request']);report['update_response_id']=reply.get('thread',{}).get('projectId');save()
finally:r.close()
r=RPC(['--stdio'])
try:
 t=r.call('thread/read',{'threadId':thread,'includeTurns':False})['thread'];report['fresh_thread_project_id']=t.get('projectId')
 listed=r.call('thread/list',{'projectId':target,'cwd':e['create_params']['roots'][0]['path'],'limit':100})['data'];report['listed_in_desktop_project']=any(t['id']==thread for t in listed)
 report['desktop_project']=r.call('project/read',{'projectId':target})['project'];save();print(json.dumps(report,indent=2))
finally:r.close()
