"""Explicitly authorized, detached Desktop exit/reopen probe for ONE disposable task."""
import datetime, json, os, pathlib, subprocess, time
from probe_rpc import RPC
ROOT=pathlib.Path(__file__).resolve().parents[1]
REPORT=ROOT/'evidence/desktop-exit-lifecycle.json'
LOG=ROOT/'.local/desktop-exit-native.log'
APP='/Applications/ChatGPT.app'
ID='01a0b6cc-6ea4-7f51-842c-112fe57860db'
r={'date':datetime.datetime.now(datetime.timezone.utc).isoformat(),'thread_id':ID,'phase':'preparing','desktop_return_turn_verified':False}
def save(): REPORT.write_text(json.dumps(r,indent=2)+'\n')
def running():
 p=subprocess.run(['osascript','-e','application id "com.openai.codex" is running'],capture_output=True,text=True,timeout=8)
 if p.returncode:raise RuntimeError('Could not inspect Desktop running state: '+p.stderr.strip())
 return p.stdout.strip()=='true'
rpc=None;quit_requested=False
try:
 time.sleep(10) # Let the launching assistant finish its message before its host closes.
 r['desktop_running_before']=running();save()
 if not r['desktop_running_before']:raise RuntimeError('Desktop was not running; test would not verify actual exit')
 rpc=RPC(['--stdio'])
 try:
  rpc.call('thread/resume',{'threadId':ID})
  raise RuntimeError('Desktop did not hold the designated writer; no exit attempted')
 except RuntimeError as e:
  if 'active writer' not in str(e):raise
  r['writer_held_before_exit']=True
 rpc.close();rpc=None
 r['phase']='quitting_desktop';save();quit_requested=True
 p=subprocess.run(['osascript','-e','tell application "'+APP+'" to quit'],capture_output=True,text=True,timeout=25)
 r['quit_command_exit']=p.returncode
 if p.returncode:raise RuntimeError('Desktop quit did not complete: '+p.stderr.strip())
 end=time.monotonic()+20
 while running() and time.monotonic()<end:time.sleep(.5)
 r['desktop_exit_observed']=not running();save()
 if not r['desktop_exit_observed']:raise RuntimeError('Desktop remained running; no force quit attempted')
 r['phase']='running_native_resume_probe';save()
 env=dict(os.environ,DIORAMA_DESKTOP_EXIT_PROBE='1')
 with LOG.open('w') as output:
  p=subprocess.run(['swift','test','--skip-build','--filter','DesktopExitResumeProbe'],cwd=ROOT,env=env,stdout=output,stderr=subprocess.STDOUT,timeout=180)
 r['native_test_exit']=p.returncode
 if p.returncode:raise RuntimeError('Native resume check failed; see desktop-exit-native.json and private test log')
 r['phase']='native_probe_passed';save()
except Exception as e:r['error']=type(e).__name__+': '+str(e);save()
finally:
 if rpc:rpc.close()
 if quit_requested:
  try:
   r['reopen_command_exit']=subprocess.run(['open','-a',APP],capture_output=True,text=True,timeout=15).returncode
   end=time.monotonic()+25
   while not running() and time.monotonic()<end:time.sleep(.5)
   r['desktop_reopened']=running()
  except Exception as e:r['reopen_error']=str(e)
 r['phase']='awaiting_desktop_return_check' if r.get('native_test_exit')==0 and r.get('desktop_reopened') else 'finished_with_limitation'
 save()
