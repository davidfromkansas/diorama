import test from 'node:test';
import assert from 'node:assert/strict';
import { PassThrough } from 'node:stream';
import { serve, subscriptionAccount } from './bridge.mjs';
const tick = () => new Promise(r => setTimeout(r, 10));

test('subscription gate rejects API credentials', () => {
  assert.equal(subscriptionAccount({ subscriptionType: 'Claude Max', apiProvider: 'firstParty' }), true);
  assert.equal(subscriptionAccount({ subscriptionType: 'Claude Max', apiProvider: 'firstParty', apiKeySource: 'environment' }), false);
  assert.equal(subscriptionAccount({}), false);
});

test('bridge keeps session, controls, approvals, child metadata and usage', async () => {
  const input = new PassThrough(), output = new PassThrough(), events = [], controls = [];
  let options, closed = false, next, messages = [];
  output.on('data', b => events.push(...b.toString().trim().split('\n').map(JSON.parse)));
  const emit = m => { messages.push(m); next?.(); };
  const sdkQuery = args => {
    options = args.options;
    void (async () => { for await (const prompt of args.prompt) {
      assert.equal(prompt.session_id, 'session');
      emit({ type: 'assistant', parent_tool_use_id: 'parent-tool', message: { content: [{ type: 'text', text: 'child only' }] } });
      const decision = await options.canUseTool('Write', { file_path: 'fixture' }, { toolUseID: 'call', signal: new AbortController().signal });
      emit({ type: 'result', is_error: false, result: decision.behavior, usage: { output_tokens: 3 } });
    } })();
    return {
      initializationResult: async () => ({ account: { subscriptionType: 'Claude Max', apiProvider: 'firstParty' }, models: [] }),
      setModel: async m => controls.push(['model', m]), setPermissionMode: async m => controls.push(['mode', m]),
      interrupt: async () => { controls.push(['interrupt']); return { still_queued: [] }; },
      close: () => { closed = true; next?.(); },
      async *[Symbol.asyncIterator]() { while (!closed) { if (!messages.length) await new Promise(r => next = r); if (messages.length) yield messages.shift(); } }
    };
  };
  const server = await serve({ input, output, sdkQuery, argv: ['--session-id', 'session'], env: { ANTHROPIC_API_KEY: 'must-not-leak', DIORAMA_CLAUDE_EXECUTABLE: '/fixture/claude' } });
  const send = e => input.write(JSON.stringify(e) + '\n');
  send({ type: 'control_request', request_id: 'init', request: { subtype: 'initialize' } }); await tick();
  assert.equal(options.sessionId, 'session'); assert.equal(options.env.ANTHROPIC_API_KEY, undefined);
  assert.equal(options.env.CLAUDE_CODE_ENABLE_TODO_TOOLS, '1');
  send({ type: 'user', session_id: 'session', message: { content: 'hello' } }); await tick();
  const request = events.find(e => e.type === 'control_request');
  assert.equal(request.request.tool_use_id, 'call');
  send({ type: 'control_response', response: { request_id: request.request_id, subtype: 'success', response: { behavior: 'deny', message: 'No' } } }); await tick();
  assert.equal(events.find(e => e.type === 'result').result, 'deny');
  assert.equal(events.find(e => e.type === 'assistant').parent_tool_use_id, 'parent-tool');
  for (const request of [{ subtype: 'set_model', model: 'sonnet' }, { subtype: 'set_permission_mode', mode: 'plan' }, { subtype: 'interrupt' }]) send({ type: 'control_request', request_id: request.subtype, request });
  await tick(); assert.deepEqual(controls, [['model', 'sonnet'], ['mode', 'plan'], ['interrupt']]);
  server.close(); input.end(); assert.equal(closed, true);
});

test('initialization refuses API account before accepting prompts', async () => {
  const input = new PassThrough(), output = new PassThrough(), events = [];
  let closed = false;
  output.on('data', b => events.push(JSON.parse(b.toString())));
  const server = await serve({ input, output, argv: [], env: {}, sdkQuery: () => ({ initializationResult: async () => ({ account: { apiKeySource: 'environment' } }), close: () => { closed = true; } }) });
  input.write(JSON.stringify({ type: 'control_request', request_id: 'init', request: { subtype: 'initialize' } }) + '\n');
  await tick(); assert.equal(events[0].response.subtype, 'error'); assert.equal(closed, true);
  server.close(); input.end();
});

import { historyPreview } from './history-format.mjs';
test('saved history accepts string or block content and excludes reasoning', () => {
  const rows = historyPreview([{ type: 'user', message: { content: 'assignment' } }, { type: 'assistant', message: { content: [{ type: 'thinking', thinking: 'private' }, { type: 'text', text: 'answer' }] } }]);
  assert.equal(rows[0].message.content[0].text, 'assignment');
  assert.deepEqual(rows[1].message.content, [{ type: 'text', text: 'answer' }]);
});

test('capability discovery reads SDK state without sending prompts and preserves partial results', async () => {
  const input = new PassThrough(), output = new PassThrough(), events = [];
  let prompts = 0, closed = false, wake;
  output.on('data', b => events.push(...b.toString().trim().split('\n').map(JSON.parse)));
  const server = await serve({ input, output, argv: [], env: {}, sdkQuery: args => {
    void (async () => { for await (const prompt of args.prompt) prompts++; })();
    return {
      initializationResult: async () => ({ account: { subscriptionType: 'max', apiProvider: 'firstParty' } }),
      supportedCommands: async () => [{ name: 'draw', description: 'Draws' }, { name: 'help', builtin: true }],
      mcpServerStatus: async () => { throw Error('Server unavailable'); },
      close: () => { closed = true; wake?.(); },
      async *[Symbol.asyncIterator]() {
        yield { type: 'system', subtype: 'init', skills: ['draw'], plugins: [{ name: 'art', path: '/art' }] };
        while (!closed) await new Promise(r => wake = r);
      }
    };
  } });
  input.write(JSON.stringify({ type: 'control_request', request_id: 'init', request: { subtype: 'initialize' } }) + '\n');
  await tick();
  input.write(JSON.stringify({ type: 'control_request', request_id: 'discover', request: { subtype: 'capability_discovery' } }) + '\n');
  await tick();
  const result = events.find(e => e.response?.request_id === 'discover').response.response;
  assert.equal(prompts, 0); assert.equal(result.commands[0].name, 'draw');
  assert.deepEqual(result.skills, ['draw']); assert.equal(result.plugins[0].name, 'art');
  assert.match(result.errors.servers, /Server unavailable/); assert.deepEqual(result.servers, []);
  server.close(); input.end();
});

test('saved history preserves correlated tool evidence and rich results without reasoning', () => {
  const rows = historyPreview([
    { type: 'assistant', uuid: 'call', message: { content: [{ type: 'tool_use', name: 'Artifact', id: 'tool-1', input: { action: 'quickstart' } }] } },
    { type: 'user', uuid: 'result', message: { content: [{ type: 'tool_result', tool_use_id: 'tool-1', content: [{ type: 'text', text: 'guidance' }, { type: 'thinking', thinking: 'secret' }, { type: 'resource_link', uri: 'https://example.com/output', name: 'Output' }] }] } }
  ]);
  assert.equal(rows[0].message.content[0].input.action, 'quickstart');
  assert.equal(rows[1].message.content[0].tool_use_id, 'tool-1');
  assert.equal(rows[1].message.content[0].content.length, 2);
  assert.equal(JSON.stringify(rows).includes('secret'), false);
});

test('history retains Claude event metadata and message usage without sending input', () => {
  const rows = historyPreview([
    { type: 'result', uuid: 'result', usage: { input_tokens: 10, cache_read_input_tokens: 40 }, total_cost_usd: 0.01 },
    { type: 'progress', uuid: 'progress', data: { type: 'bash_progress', output: 'building' } },
    { type: 'assistant', uuid: 'message', message: { usage: { output_tokens: 3 }, content: [{ type: 'text', text: 'done' }] } }
  ]);
  assert.equal(rows[0].usage.cache_read_input_tokens, 40);
  assert.equal(rows[0].total_cost_usd, 0.01);
  assert.equal(rows[1].data.type, 'bash_progress');
  assert.equal(rows[2].message.usage.output_tokens, 3);
});

test('history retains cumulative saved cost-state and mode without reinterpreting them', () => {
  const rows = historyPreview([
    { type: 'mode', mode: 'normal' },
    { type: 'cost-state', totalCostUSD: 0.25, totalDuration: 7100, hasUnknownModelCost: true,
      modelUsage: { fixture: { inputTokens: 2, cacheReadInputTokens: 100 } } }
  ]);
  assert.equal(rows[0].mode, 'normal');
  assert.equal(rows[1].totalCostUSD, 0.25);
  assert.equal(rows[1].modelUsage.fixture.cacheReadInputTokens, 100);
  assert.equal(rows[1].hasUnknownModelCost, true);
  assert.equal(rows[1].usage, undefined);
});
