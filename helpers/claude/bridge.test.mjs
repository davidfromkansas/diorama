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
