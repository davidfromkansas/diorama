"""Probe official project methods using only designated disposable records."""
import json,pathlib,uuid
from probe_rpc import RPC
p=pathlib.Path('.local/project-discovery/evidence.json');report=json.loads(p.read_text())
rpc=RPC(['--stdio'])
def save():p.write_text(json.dumps(report,indent=2))
def matching_projects():
 cursor=None;matches=[]
 while True:
  result=rpc.call('project/list',{'limit':100,'cursor':cursor})
  matches += [x for x in result['data'] if any(r.get('path') in [report['folder'],report['empty_control']] for r in x['roots'])]
  cursor=result.get('nextCursor')
  if not cursor:return matches
try:
 report['project_list_before']=matching_projects();save()
 params={'idempotencyKey':str(uuid.uuid4()),'name':'Diorama Discovery Test 20260919','roots':[{'path':report['folder']}],'threads':[report['thread_id']]}
 report['import_params']=params;save()
 report['project_import']=rpc.call('project/import',params);save()
 report['project_import_repeated']=rpc.call('project/import',params);save()
 report['project_list_after']=matching_projects();save()
 t=rpc.call('thread/read',{'threadId':report['thread_id'],'includeTurns':False})['thread']
 report['imported_thread_project_id']=t.get('projectId');save()
except Exception as e:
 report['project_probe_error']=str(e);save()
finally:rpc.close()
print(json.dumps({k:v for k,v in report.items() if 'project' in k or 'import' in k},indent=2))
