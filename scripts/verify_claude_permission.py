"""Observe a permission request in noninteractive mode; reporter makes no decision."""
import json, pathlib, subprocess

root = pathlib.Path(__file__).resolve().parents[1]
base = root / '.local/hook-verification/claude'
cli = str(pathlib.Path.home() / '.local/bin/claude')
before = {p.name for p in (base / 'events').glob('*.json')}
target = base / 'work/permission-probe.txt'
prompt = (f'Designated permission probe: attempt the Write tool exactly once to write DIORAMA_PERMISSION_TEST '
          f'to {target}. If denied, do not retry or use another tool. Then reply DIORAMA_PERMISSION_DONE.')
p = subprocess.run([cli, '-p', prompt, '--model', 'claude-haiku-4-5-20251001', '--max-budget-usd', '0.25',
                    '--settings', str(base / 'settings.json'), '--output-format', 'json', '--tools', 'Write'],
                   cwd=base / 'work', stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=45)
(base / 'permission-result.txt').write_text(p.stdout + '\n' + p.stderr)
response = json.loads(p.stdout)
records = [json.loads(f.read_text()) for f in (base / 'events').glob('*.json') if f.name not in before]
result = dict(client='Claude Code', version=subprocess.check_output([cli, '--version'], text=True).split()[0],
              exit_code=p.returncode, is_error=response.get('is_error'), reported_cost_usd=response.get('total_cost_usd'),
              hook_kinds=sorted({r['kind'] for r in records}), target_written=target.exists(),
              permission_denial_count=len(response.get('permission_denials', [])),
              reporter_decision='none; neutral JSON only', mode='noninteractive; no human approval dialog tested')
(root / 'evidence/claude-permission-hook-verification.json').write_text(json.dumps(result, indent=2) + '\n')
(root / 'evidence/claude-permission-hooks.json').write_text(json.dumps(records, indent=2) + '\n')
print(json.dumps(result, indent=2))
