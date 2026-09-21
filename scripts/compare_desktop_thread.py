"""Read designated test-folder conversations only; retain metadata, not unrelated history."""
import json,pathlib
from probe_rpc import RPC
root=pathlib.Path('.local/project-discovery');e=json.loads((root/'fresh-20260920-002606.json').read_text());r=RPC(['--stdio']);out={}
try:
 result=r.call('thread/list',{'cwd':e['folder'],'sourceKinds':['cli','vscode','appServer','exec','unknown'],'limit':100})
 out['listed']=[{k:t.get(k) for k in ['id','projectId','cwd','source','name','preview','path']} for t in result['data']]
 out['threads']=[]
 for item in result['data']:
  if item['id']==e['thread_id'] or 'DESKTOP-4192' in (item.get('preview','')+str(item.get('name',''))):
   t=r.call('thread/read',{'threadId':item['id'],'includeTurns':True})['thread']
   out['threads'].append({k:v for k,v in t.items() if k!='turns'})
   out['threads'][-1]['turn_summaries']=[{'id':x['id'],'status':x.get('status'),'items':[{'type':i.get('type'),'text':i.get('text'),'content':i.get('content') if i.get('type')=='userMessage' else None} for i in x.get('items',[])]} for x in t.get('turns',[])]
finally:r.close()
p=root/'desktop-native-comparison.json';p.write_text(json.dumps(out,indent=2));print(json.dumps(out,indent=2))
