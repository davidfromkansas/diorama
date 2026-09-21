import json,pathlib,subprocess,time,os
root=pathlib.Path(__file__).resolve().parents[1]
base=root/'.local/hook-verification/claude'
cli=str(pathlib.Path.home()/'.local/bin/claude')
version=subprocess.check_output([cli,'--version'],text=True).split()[0]
args=[cli,'-p','--model','claude-haiku-4-5-20251001','--settings',str(base/'settings.json'),'--output-format','json','--max-budget-usd','0.50',
      '--allowedTools','Bash(/bin/echo:*)','Bash(/usr/bin/false:*)',
      'Designated Diorama verification. Run /bin/echo DIORAMA_HOOK_SUCCESS once, then /usr/bin/false once (expected failure), then reply DIORAMA_DONE. Do not read or modify files, access network tools, or spawn agents.']
args.insert(2, args.pop())
before={p.name for p in (base/'events').glob('*.json')}
start=time.monotonic()
try:
 p=subprocess.run(args,cwd=base/'work',capture_output=True,text=True,timeout=45)
 text=p.stdout+'\n'+p.stderr
 (base/'result.txt').write_text(text)
 cause=next((label for marker,label in [('Credit balance is too low','insufficient_credit'),('Invalid API key','invalid_api_key'),('not logged in','not_authenticated'),('DIORAMA_DONE','completed')] if marker in text),'other_error' if p.returncode else 'completed_without_marker')
 result={'client':'Claude Code','version':version,'exit_code':p.returncode,'outcome':cause}
 try:
  response=json.loads(p.stdout)
  result.update(model='claude-haiku-4-5-20251001',reported_cost_usd=response.get('total_cost_usd'),session_id=response.get('session_id'),is_error=response.get('is_error'))
 except json.JSONDecodeError:
  pass
except subprocess.TimeoutExpired:
 result={'client':'Claude Code','version':version,'outcome':'timed_out'}
records=[json.loads(f.read_text()) for f in (base/'events').glob('*.json') if f.name not in before]
(root/'evidence/claude-funded-turn-hooks.json').write_text(json.dumps(records,indent=2)+'\n')
result.update(elapsed_seconds=round(time.monotonic()-start,1),hook_kinds=sorted(set(r['kind'] for r in records)),hook_count=len(records),provider_hook_settings_modified=False)
(root/'evidence/claude-live-hook-verification.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
