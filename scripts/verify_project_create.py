"""Create a designated project and verify durable thread project assignment."""
import json,pathlib,uuid
from probe_rpc import RPC
p=pathlib.Path('.local/project-discovery/evidence.json');report=json.loads(p.read_text())
folder=pathlib.Path(report['folder']).with_name('Diorama Created Project Test 20260919');folder.mkdir()
rpc=RPC(['--stdio'])
def save():p.write_text(json.dumps(report,indent=2))
try:
 params={'idempotencyKey':str(uuid.uuid4()),'name':folder.name,'roots':[{'path':str(folder)}]}
 report['create_params']=params;save()
 project=rpc.call('project/create',params)['project'];report['project_create']=project;save()
 thread=rpc.call('thread/start',{'cwd':str(folder),'threadSource':'user','projectId':project['id']})['thread']
 report['created_project_thread']={'id':thread['id'],'projectId':thread.get('projectId')};save()
 report['created_project_response']=rpc.turn(thread['id'],'Diorama project creation test BIRCH-7392. Do not use tools, access files, or use the network. Reply BIRCH-7392 only.');save()
finally:rpc.close()
rpc=RPC(['--stdio'])
try:
 report['fresh_project_read']=rpc.call('project/read',{'projectId':project['id']})
 report['fresh_imported_project_read']=rpc.call('project/read',{'projectId':report['project_import']['project']['id']})
 t=rpc.call('thread/read',{'threadId':thread['id'],'includeTurns':True})['thread']
 report['fresh_project_thread']={'id':t['id'],'projectId':t.get('projectId'),'cwd':t.get('cwd'),'turn_count':len(t['turns'])};save()
 print(json.dumps({k:v for k,v in report.items() if k.startswith(('create','fresh_project','project_create'))},indent=2))
finally:rpc.close()
