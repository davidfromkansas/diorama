"""Designated tool-free probe of official review settings; no global config edits."""
import json, pathlib, time
from probe_rpc import RPC
folder=pathlib.Path('.local/approval-settings-probe').resolve();folder.mkdir(parents=True,exist_ok=True)
rpc=RPC(['--stdio'])
try:
    initial=rpc.call('thread/start',{'cwd':str(folder)})
    id=initial['thread']['id']
    results={'thread':id,'initialReviewer':initial.get('approvalsReviewer'),'choices':[]}
    for choice in ['user','auto_review']:
        tid=rpc.call('turn/start',{'threadId':id,'approvalsReviewer':choice,'input':[{'type':'text','text':'Disposable settings test. Reply OK only. Do not use tools.'}],'effort':'low'})['turn']['id']
        end=time.monotonic()+90
        while not any(e.get('method')=='turn/completed' and e.get('params',{}).get('turn',{}).get('id')==tid for e in rpc.events): rpc.next(max(.01,end-time.monotonic()))
        resumed=rpc.call('thread/resume',{'threadId':id})
        results['choices'].append({'requested':choice,'reported':resumed.get('approvalsReviewer'),'policy':resumed.get('approvalPolicy')})
    results['passed']=all(c['requested']==c['reported'] for c in results['choices'])
    (folder/'evidence.json').write_text(json.dumps(results,indent=2));print(json.dumps(results))
finally: rpc.close()
