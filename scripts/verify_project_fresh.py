"""Fresh disposable project probe. Never reuses or deletes previous records."""
import datetime,json,pathlib,subprocess,uuid
from probe_rpc import RPC,BIN
stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
name='Diorama Fresh Test '+stamp
folder=pathlib.Path.home()/'Documents/ChatGPT'/name
folder.mkdir()
out=pathlib.Path('.local/project-discovery')/('fresh-'+stamp+'.json')
report={'name':name,'folder':str(folder),'version':subprocess.check_output([BIN,'--version'],text=True).strip(),'desktop_display':'pending user observation','marker':'MAPLE-8264'}
def save():out.write_text(json.dumps(report,indent=2))
save();rpc=RPC(['--stdio'])
try:
 params={'idempotencyKey':str(uuid.uuid4()),'name':name,'roots':[{'path':str(folder)}]}
 report['create_params']=params;save()
 project=rpc.call('project/create',params)['project'];report['project']=project;save()
 t=rpc.call('thread/start',{'cwd':str(folder),'threadSource':'user','projectId':project['id']})['thread'];report['thread_id']=t['id'];save()
 report['response']=rpc.turn(t['id'],'Diorama fresh project test MAPLE-8264. Do not use tools, access files, or use the network. Reply MAPLE-8264 only.');save()
finally:rpc.close()
rpc=RPC(['--stdio'])
try:
 t=rpc.call('thread/read',{'threadId':report['thread_id'],'includeTurns':False})['thread']
 report['fresh_read_project_id']=t.get('projectId')
 r=rpc.call('thread/list',{'projectId':project['id'],'cwd':str(folder),'limit':100})
 report['listed_in_project']=any(t['id']==report['thread_id'] for t in r['data'])
 report['fresh_project']=rpc.call('project/read',{'projectId':project['id']})['project'];save()
 print(json.dumps(report,indent=2));print('Evidence:',out)
finally:rpc.close()
