#!/usr/bin/env python3
"""Local reporter + isolated Claude hook probe; never reads normal provider settings."""
import json, os, pathlib, subprocess, tempfile, time

root = pathlib.Path(__file__).resolve().parents[1]
reporter = root / '.build/debug/DioramaReporter'
result = {}
with tempfile.TemporaryDirectory(prefix='diorama-hook-probe-') as temp:
    base = pathlib.Path(temp)
    store = base / 'activity'
    command = [str(reporter), '--diorama-reporter-v1', 'claude', str(store)]
    payload = {'session_id':'designated-reporter-probe', 'hook_event_name':'PreToolUse', 'tool_name':'Bash',
               'tool_input':{'command':'echo designated-probe', 'secret':'OMIT_THIS'}, 'prompt':'OMIT_THIS'}
    started = time.monotonic()
    p = subprocess.run(command, input=json.dumps(payload), text=True, capture_output=True, timeout=2)
    records = [json.loads(f.read_text()) for f in store.glob('*.json')]
    result['reporter'] = {'exit_code':p.returncode, 'neutral_output':p.stdout.strip()=='{}', 'elapsed_ms':round((time.monotonic()-started)*1000),
                          'records':len(records), 'private_fields_omitted':'OMIT_THIS' not in json.dumps(records), 'gui_required':False}
    assert p.returncode == 0 and p.stdout.strip() == '{}' and len(records)==1 and result['reporter']['private_fields_omitted']
    failure = subprocess.run(command, input='not json', text=True, capture_output=True, timeout=2)
    result['malformed_input_fail_open'] = failure.returncode == 0 and failure.stdout.strip() == '{}'
    # Installed Claude 1.0.108 schema explicitly includes these lifecycle events.
    import shlex
    config = base / 'claude'; config.mkdir()
    hook = {'type':'command', 'command':shlex.join(command), 'timeout':1}
    settings = {'hooks': {event:[{'matcher':'', 'hooks':[hook]}] for event in ['SessionStart','UserPromptSubmit','Stop','SessionEnd']}}
    (config/'settings.json').write_text(json.dumps(settings))
    env = {k:v for k,v in os.environ.items() if not any(word in k.upper() for word in ['TOKEN','API_KEY','AUTH'])}
    env.update(HOME=str(base), CLAUDE_CONFIG_DIR=str(config), ANTHROPIC_API_KEY='diorama-invalid-test-key',
               ANTHROPIC_BASE_URL='http://127.0.0.1:1', DISABLE_TELEMETRY='1', DISABLE_ERROR_REPORTING='1',
               CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC='1', CI='1')
    try:
        cli = subprocess.run(['/usr/local/bin/claude','-p','Designated Diorama hook probe.'], env=env, cwd=temp,
                             capture_output=True, text=True, timeout=12)
        result['claude_isolated'] = {'exit_code':cli.returncode, 'model_execution':'unavailable: intentionally disconnected isolated configuration'}
    except subprocess.TimeoutExpired:
        result['claude_isolated'] = {'timed_out':True, 'model_execution':'unavailable: intentionally disconnected isolated configuration'}
    records = [json.loads(f.read_text()) for f in store.glob('*.json')]
    result['claude_isolated']['hook_kinds_observed'] = sorted(set(r['kind'] for r in records if r['sessionID']!='designated-reporter-probe'))
    result['claude_isolated']['normal_settings_modified'] = False
out = root/'evidence/activity-reporter.json'
out.write_text(json.dumps(result, indent=2)+'\n')
print(out.read_text())
