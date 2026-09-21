"""Bounded live probe in an isolated CODEX_HOME with normally reviewed hook trust."""
import json,pathlib,os,subprocess,time
root=pathlib.Path(__file__).resolve().parents[1]
base=root/'.local/hook-verification/codex'
env=dict(os.environ,CODEX_HOME=str(base))
before={p.name for p in (base/'events').glob('*.json')}
args=['codex','exec','--json','-C',str(base/'work'),
      'Designated Diorama hook verification. Run /bin/echo DIORAMA_HOOK_SUCCESS once, then /usr/bin/false once (expected failure), then reply exactly DIORAMA_DONE. Do not read or edit any files, use network tools, or spawn agents.']
start=time.monotonic()
try:
 p=subprocess.run(args,env=env,stdin=subprocess.DEVNULL,capture_output=True,text=True,timeout=60)
 (base/'exec-result.jsonl').write_text(p.stdout); (base/'exec-stderr.txt').write_text(p.stderr)
 result={'client':'Codex CLI','version':'0.153.4','exit_code':p.returncode,'timed_out':False,
         'completed_marker':'DIORAMA_DONE' in p.stdout,'trust_bypassed':False}
except subprocess.TimeoutExpired:
 result={'client':'Codex CLI','version':'0.153.4','timed_out':True,'trust_bypassed':False}
records=[json.loads(p.read_text()) for p in (base/'events').glob('*.json') if p.name not in before]
result.update(elapsed_seconds=round(time.monotonic()-start,1),hook_kinds=sorted(set(r['kind'] for r in records)),hook_count=len(records),
              tool_names=sorted(set(r.get('tool','') for r in records)),provider_hook_settings_modified=False)
(root/'evidence/codex-live-hook-verification.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
