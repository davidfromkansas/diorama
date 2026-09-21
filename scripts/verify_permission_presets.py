"""Opt-in tool-free check of official permission preset inputs on a disposable thread."""
import json, pathlib, time
from probe_rpc import RPC
folder=pathlib.Path('.local/permission-presets-probe').resolve();folder.mkdir(parents=True,exist_ok=True)
rpc=RPC(['--stdio'])
try:
    id=rpc.call('thread/start',{'cwd':str(folder)})['thread']['id']
    results=[]
    for name,reviewer,policy,sandbox in [('full','user','never',{'type':'dangerFullAccess'}),('ask','user','on-request',{'type':'workspaceWrite','writableRoots':[str(folder)],'networkAccess':False}),('auto','auto_review','on-request',{'type':'workspaceWrite','writableRoots':[str(folder)],'networkAccess':False})]:
        reply=rpc.call('turn/start',{'threadId':id,'approvalsReviewer':reviewer,'approvalPolicy':policy,'sandboxPolicy':sandbox,'input':[{'type':'text','text':'Disposable settings check. Do not use tools or access files or network. Reply OK only.'}],'effort':'low'})
        tid=reply['turn']['id'];end=time.monotonic()+90
        while not any(e.get('method')=='turn/completed' and e.get('params',{}).get('turn',{}).get('id')==tid for e in rpc.events): rpc.next(max(.01,end-time.monotonic()))
        settings=rpc.call('thread/resume',{'threadId':id})
        results.append({'name':name,'reviewer':settings.get('approvalsReviewer'),'policy':settings.get('approvalPolicy'),'sandbox':settings.get('sandbox'),'passed':settings.get('approvalsReviewer')==reviewer and settings.get('approvalPolicy')==policy and settings.get('sandbox',{}).get('type')==sandbox['type']})
    report={'thread':id,'results':results,'passed':all(r['passed'] for r in results)}
    (folder/'evidence.json').write_text(json.dumps(report,indent=2));print(json.dumps(report))
finally: rpc.close()
