"""Designated new-folder/thread probe; Desktop sidebar verification remains manual."""
import json, pathlib, subprocess, datetime
from probe_rpc import RPC, BIN
root=pathlib.Path.home()/'Documents/ChatGPT'
folder=root/'Diorama Discovery Test 20260919'
empty=root/'Diorama Empty Folder Test 20260919'
report_path=pathlib.Path('.local/project-discovery/evidence.json')
report_path.parent.mkdir(parents=True,exist_ok=True)
# Exclusive creation avoids accidentally using an existing project.
folder.mkdir();empty.mkdir()
report={'tested_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'version':subprocess.check_output([BIN,'--version'],text=True).strip(),'folder':str(folder),'empty_control':str(empty),'desktop_sidebar':'not yet observed'}
def save(): report_path.write_text(json.dumps(report,indent=2))
save()
rpc=RPC(['--stdio'])
try:
 thread=rpc.call('thread/start',{'cwd':str(folder),'threadSource':'user'})['thread']
 report['thread_id']=thread['id'];save()
 report['response']=rpc.turn(thread['id'],'Diorama discovery test PINE-4821. Do not use tools, access files, or use the network. Reply PINE-4821 only.')
 save()
finally:rpc.close()
rpc=RPC(['--stdio'])
try:
 report['lists']={}
 for label,extra in [('default',{}),('appServer',{'sourceKinds':['appServer']}),('interactive',{'sourceKinds':['cli','vscode']})]:
  result=rpc.call('thread/list',{'cwd':str(folder),'limit':100,**extra})
  report['lists'][label]=[{'id':t['id'],'source':t.get('source'),'cwd':t.get('cwd'),'preview':t.get('preview')} for t in result['data']]
 t=rpc.call('thread/read',{'threadId':report['thread_id'],'includeTurns':True})['thread']
 report['fresh_read']={'id':t['id'],'cwd':t.get('cwd'),'source':t.get('source'),'turn_count':len(t.get('turns',[]))}
 report['empty_folder_threads']=len(rpc.call('thread/list',{'cwd':str(empty),'sourceKinds':['cli','vscode','appServer'],'limit':100})['data'])
 save();print(json.dumps(report,indent=2))
finally:rpc.close()
