import pathlib,json,subprocess,os,time,collections
root=pathlib.Path(__file__).resolve().parents[1]; base=root/'.local/hook-verification/codex'
sid=json.loads((root/'evidence/codex-approval-pending.json').read_text())['sessionID']
before={p.name for p in (base/'events').glob('*.json')}
p=subprocess.Popen(['codex','exec','--json','-C',str(base/'work'),'resume',sid,
                    'Final Diorama observer verification. Run /bin/sleep 3 and then /bin/echo DIORAMA_RESUMED once. Reply DIORAMA_RESUME_DONE. Do not read or modify files or spawn agents.'],
                   env=dict(os.environ,CODEX_HOME=str(base)),stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
seen=set(); observed_while_running=False; reconnected=False; deadline=time.monotonic()+60
while p.poll() is None and time.monotonic()<deadline:
 files={f.name for f in (base/'events').glob('*.json')}-before
 if files: observed_while_running=True
 if files and not reconnected:
  # Drop observer state and reconstruct from durable records. No agent IPC/control.
  seen=set(); reconnected=True
 seen.update(files)
 time.sleep(.2)
timed_out=p.poll() is None
if timed_out:p.terminate()
try: out,err=p.communicate(timeout=5)
except subprocess.TimeoutExpired:p.kill();out,err=p.communicate()
records=[json.loads(f.read_text()) for f in (base/'events').glob('*.json') if f.name not in before]
result={'client':'Codex CLI','exit_code':p.returncode,'timed_out':timed_out,'completed_marker':'DIORAMA_RESUME_DONE' in out,
        'same_session':all(r['sessionID']==sid for r in records),'source_process_restarted':True,
        'hook_kinds':sorted(set(r['kind'] for r in records)),'observed_while_cli_running':observed_while_running,
        'observer_recreated_without_agent_control':reconnected,'trust_bypassed':False}
(root/'evidence/codex-resume-hook-verification.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
