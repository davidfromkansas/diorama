"""Link only MAPLE-8264 to the uniquely matching Desktop-added test project."""
import json,pathlib
from probe_rpc import RPC
p=pathlib.Path('.local/project-discovery/fresh-20260920-002606.json');e=json.loads(p.read_text());r=RPC(['--stdio'])
report={'thread_id':e['thread_id'],'original_project_id':e['project']['id'],'desktop_visual_result':'pending'}
out=p.with_name('fresh-desktop-reassignment.json')
def save():out.write_text(json.dumps(report,indent=2))
try:
 cursor=None;matches=[]
 while True:
  reply=r.call('project/list',{'limit':100,'cursor':cursor})
  matches.extend(x for x in reply['data'] if x['name']==e['name'] and x['roots']==e['create_params']['roots'])
  cursor=reply.get('nextCursor')
  if not cursor:break
 report['matching_projects']=matches;save()
 targets=[x for x in matches if x['id']!=e['project']['id']]
 assert len(targets)==1,'Cannot uniquely identify Desktop-added project'
 target=targets[0]['id'];report['desktop_project_id']=target
 t=r.call('thread/read',{'threadId':e['thread_id'],'includeTurns':False})['thread']
 assert t['projectId']==e['project']['id'],'Unexpected existing assignment'
 params={'threadId':e['thread_id'],'projectId':target};report['request']=params;save()
 reply=r.call('thread/metadata/update',params)
 report['update_project_id']=reply['thread'].get('projectId');save()
finally:r.close()
r=RPC(['--stdio'])
try:
 t=r.call('thread/read',{'threadId':e['thread_id'],'includeTurns':False})['thread'];report['fresh_read_project_id']=t.get('projectId')
 listed=r.call('thread/list',{'projectId':target,'cwd':e['folder'],'limit':100})['data']
 report['listed_in_desktop_project']=any(t['id']==e['thread_id'] for t in listed)
 report['fresh_project']=r.call('project/read',{'projectId':target})['project'];save();print(json.dumps(report,indent=2))
finally:r.close()
