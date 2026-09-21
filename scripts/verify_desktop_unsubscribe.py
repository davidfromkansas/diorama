"""Probe only the designated disposable conversation; never sends a prompt."""
import datetime, json, pathlib, plistlib, subprocess
from probe_rpc import RPC, BIN
ROOT=pathlib.Path(__file__).resolve().parents[1]
ID='01a0b6cc-6ea4-7f51-842c-112fe57860db'
r={'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'thread_id':ID,'cli_version':subprocess.check_output([BIN,'--version'],text=True).strip(),'scope':'Separate official App Server connection, no Desktop connection access, no prompt or archive mutation.'}
r['desktop_version']=plistlib.loads(pathlib.Path('/Applications/ChatGPT.app/Contents/Info.plist').read_bytes()).get('CFBundleShortVersionString')
r['desktop_process_seen_before']=subprocess.run(['pgrep','-f','/Applications/ChatGPT.app/Contents/MacOS/'],capture_output=True).returncode==0
c=None
try:
 c=RPC(['--stdio'])
 t=c.call('thread/read',{'threadId':ID,'includeTurns':True})['thread']
 assert t['id']==ID
 r['recorded_turn_in_progress']=any(x.get('status')=='inProgress' for x in t.get('turns',[]))
 g=c.call('thread/goal/get',{'threadId':ID})
 r['goal_absent']=g.get('goal','missing') is None
 r['unsubscribe']=c.call('thread/unsubscribe',{'threadId':ID})
 if r['recorded_turn_in_progress'] or not r['goal_absent']: r['resume_skipped']='active or uncertain work'
 else:
  try:
   resumed=c.call('thread/resume',{'threadId':ID})
   r['resume_same_id']=resumed['thread']['id']==ID
  except Exception as e:r['resume_error']=str(e)
except Exception as e:r['error']=str(e)
finally:
 if c: c.close()
 r['desktop_process_seen_after']=subprocess.run(['pgrep','-f','/Applications/ChatGPT.app/Contents/MacOS/'],capture_output=True).returncode==0
 (ROOT/'evidence/desktop-unsubscribe.json').write_text(json.dumps(r,indent=2)+'\n')
 print(json.dumps(r,indent=2))
