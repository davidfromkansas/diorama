"""Small funded probe: independent CLI restart, passive collector reconnect, one worker."""
import json, pathlib, subprocess, time

root = pathlib.Path(__file__).resolve().parents[1]
base = root / '.local/hook-verification/claude'
sid = json.loads((root / 'evidence/claude-live-hook-verification.json').read_text())['session_id']
before = {p.name for p in (base / 'events').glob('*.json')}
cli = str(pathlib.Path.home() / '.local/bin/claude')
version = subprocess.check_output([cli, '--version'], text=True).split()[0]
prompt = ('Designated Diorama resume verification. Run /bin/echo DIORAMA_RESUMED once. '
          'Then use Agent exactly once with subagent_type general-purpose. Tell the worker to reply '
          'DIORAMA_CHILD_DONE without using any tools or reading files. Use the current inherited model. '
          'After it returns, reply DIORAMA_RESUME_DONE. Do nothing else.')
args = [cli, '-p', prompt, '--resume', sid, '--model', 'claude-haiku-4-5-20251001', '--max-budget-usd', '0.50',
        '--settings', str(base / 'settings.json'), '--output-format', 'json',
        '--allowedTools', 'Bash(/bin/echo:*)', 'Agent']
p = subprocess.Popen(args, cwd=base / 'work', stdin=subprocess.DEVNULL,
                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
observed = False
reconnected = False
seen = set()
deadline = time.monotonic() + 60
while p.poll() is None and time.monotonic() < deadline:
    files = {f.name for f in (base / 'events').glob('*.json')} - before
    if files:
        observed = True
    if files and not reconnected:
        seen = set()
        reconnected = True
    seen.update(files)
    time.sleep(.2)
timed_out = p.poll() is None
if timed_out:
    p.terminate()
try:
    out, err = p.communicate(timeout=5)
except subprocess.TimeoutExpired:
    p.kill()
    out, err = p.communicate()
(base / 'resume-result.txt').write_text(out + '\n' + err)
try:
    response = json.loads(out)
except json.JSONDecodeError:
    response = {}
records = [json.loads(f.read_text()) for f in (base / 'events').glob('*.json') if f.name not in before]
result = dict(client='Claude Code', version=version, exit_code=p.returncode, timed_out=timed_out,
              same_session=response.get('session_id') == sid, is_error=response.get('is_error'),
              completed_marker='DIORAMA_RESUME_DONE' in response.get('result', ''),
              reported_cost_usd=response.get('total_cost_usd'), source_process_restarted=True,
              hook_kinds=sorted({r['kind'] for r in records}), observed_while_cli_running=observed,
              observer_recreated_without_agent_control=reconnected, provider_hook_settings_modified=False)
(root / 'evidence/claude-resume-hook-verification.json').write_text(json.dumps(result, indent=2) + '\n')
(root / 'evidence/claude-resume-hooks.json').write_text(json.dumps(records, indent=2) + '\n')
print(json.dumps(result, indent=2))
