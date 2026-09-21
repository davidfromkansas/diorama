"""Designated Desktop-owned test only; no prompts or archive changes."""
import datetime, json, pathlib, subprocess
from probe_rpc import RPC, BIN
ROOT=pathlib.Path(__file__).resolve().parents[1]
ID='01a0b6cc-6ea4-7f51-842c-112fe57860db'
r={'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'thread_id':ID,'cli_version':subprocess.check_output([BIN,'--version'],text=True).strip(),'desktop_open_evidence':'User confirmed sending READY in Desktop and leaving it open; matching completed transcript turn 01a0b6f8-b04f-7532-9bed-9f2891d23020 at 2026-09-19T00:02:33.145Z.','checks':{}}
c=None
try:
 c=RPC(['--stdio'])
 t=c.call('thread/read',{'threadId':ID,'includeTurns':True})['thread']
 assert t['id']==ID
 assert not any(x.get('status')=='inProgress' for x in t.get('turns',[])), 'Recorded active turn; stop probe'
 assert c.call('thread/goal/get',{'threadId':ID}).get('goal','unknown') is None, 'Goal present or unknown; stop probe'
 def resume(label):
  try:
   t=c.call('thread/resume',{'threadId':ID})['thread']
   r['checks'][label]={'resumed_same_id':t['id']==ID}
  except Exception as e:r['checks'][label]={'error':str(e)}
 resume('before_unsubscribe')
 r['checks']['separate_connection_unsubscribe']=c.call('thread/unsubscribe',{'threadId':ID})
 resume('after_unsubscribe')
except Exception as e:r['error']=str(e)
finally:
 if c:c.close()
 r['scope']='Only thread/read, goal/get, resume and unsubscribe on separate App Server. No turn/start, Desktop shutdown, archive change, or lock manipulation.'
 (ROOT/'evidence/desktop-release-baseline.json').write_text(json.dumps(r,indent=2)+'\n')
 print(json.dumps(r,indent=2))
