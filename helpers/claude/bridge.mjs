// Private protocol v1: preserve the CLI envelope at the Swift boundary. No credentials cross it.
import { query } from '@anthropic-ai/claude-agent-sdk';
import { createInterface } from 'node:readline';
import { randomUUID } from 'node:crypto';

export function subscriptionAccount(account = {}) {
  return (!account.apiKeySource || account.apiKeySource === 'none') &&
    account.apiProvider === 'firstParty' &&
    ['max', 'pro', 'team', 'enterprise'].includes((account.subscriptionType ?? '').toLowerCase().replace(/^claude /, ''));
}

export async function serve({ sdkQuery = query, input = process.stdin, output = process.stdout, argv = process.argv.slice(2), env = process.env } = {}) {
  const value = name => { const i = argv.indexOf(name); return i < 0 ? undefined : argv[i + 1]; };
  const sessionId = value('--session-id'), resume = value('--resume'), append = value('--append-system-prompt');
  const queue = [], approvals = new Map();
  let wake, closed = false, q, ready = false;
  const emit = event => { if (!closed) output.write(JSON.stringify(event) + '\n'); };
  async function* prompts() {
    while (!closed) {
      if (!queue.length) await new Promise(resolve => { wake = resolve; });
      if (closed) return;
      if (queue.length) yield queue.shift();
    }
  }
  const close = () => {
    if (closed) return;
    closed = true; wake?.();
    for (const pending of approvals.values()) pending.resolve({ behavior: 'deny', message: 'Diorama disconnected.' });
    approvals.clear(); q?.close();
  };
  const clean = { ...env, CLAUDE_CODE_ENABLE_TODO_TOOLS: '1' };
  for (const key of ['ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN', 'CLAUDE_CODE_OAUTH_TOKEN', 'ANTHROPIC_BASE_URL', 'CLAUDE_CODE_USE_BEDROCK', 'CLAUDE_CODE_USE_VERTEX', 'CLAUDE_CODE_USE_FOUNDRY']) delete clean[key];
  const options = {
    cwd: process.cwd(), pathToClaudeCodeExecutable: env.DIORAMA_CLAUDE_EXECUTABLE,
    env: clean, includePartialMessages: true, permissionMode: 'default', allowDangerouslySkipPermissions: true,
    settingSources: ['user', 'project', 'local'],
    ...(resume ? { resume } : { sessionId }),
    ...(append ? { systemPrompt: { type: 'preset', preset: 'claude_code', append } } : {}),
    canUseTool: (tool_name, args, context) => new Promise(resolve => {
      const request_id = randomUUID();
      const finish = response => { approvals.delete(request_id); context.signal?.removeEventListener('abort', abort); resolve(response); };
      const abort = () => finish({ behavior: 'deny', message: 'Action interrupted.' });
      if (context.signal?.aborted) { abort(); return; }
      context.signal?.addEventListener('abort', abort, { once: true });
      approvals.set(request_id, { resolve: finish });
      emit({ type: 'control_request', request_id, request: { subtype: 'can_use_tool', tool_name, input: args, tool_use_id: context.toolUseID } });
    })
  };
  const lines = createInterface({ input, crlfDelay: Infinity });
  let controls = Promise.resolve();
  async function control(event) {
    const r = event.request ?? {};
    try {
      let response = {};
      switch (r.subtype) {
        case 'initialize':
          if (q) throw Error('Already initialized');
          q = sdkQuery({ prompt: prompts(), options });
          response = await q.initializationResult();
          if (!subscriptionAccount(response.account)) throw Error('Claude subscription authentication required. No prompt was sent.');
          ready = true;
          // Consume continuously, including while waiting on approvals and subsequent user input.
          void (async () => { try { for await (const message of q) emit(message); } catch (error) {
            emit({ type: 'result', subtype: 'error_during_execution', is_error: true, errors: [String(error)] }); close();
          } })();
          break;
        case 'set_model': if (!ready) throw Error('Not initialized'); await q.setModel(r.model); break;
        case 'set_permission_mode': if (!ready) throw Error('Not initialized'); await q.setPermissionMode(r.mode); break;
        case 'interrupt': if (!ready) throw Error('Not initialized'); response = await q.interrupt() ?? {}; break;
        default: throw Error('Unsupported helper control: ' + r.subtype);
      }
      emit({ type: 'control_response', response: { subtype: 'success', request_id: event.request_id, response } });
    } catch (error) {
      emit({ type: 'control_response', response: { subtype: 'error', request_id: event.request_id, error: String(error) } });
      if (r.subtype === 'initialize') close();
    }
  }
  lines.on('line', line => {
    try {
      if (Buffer.byteLength(line) > 32 * 1024 * 1024) throw Error('Input exceeded helper limit');
      const event = JSON.parse(line);
      if (event.type === 'control_request') controls = controls.then(() => control(event));
      else if (event.type === 'control_response') {
        const r = event.response;
        approvals.get(r.request_id)?.resolve(r.subtype === 'error' ? { behavior: 'deny', message: r.error } : r.response);
      } else if (event.type === 'user') {
        if (!ready) throw Error('Cannot send before subscription initialization');
        queue.push(event); wake?.();
      }
    } catch (error) { emit({ type: 'result', subtype: 'error_during_execution', is_error: true, errors: [String(error)] }); close(); }
  });
  lines.once('close', close);
  return { close };
}
