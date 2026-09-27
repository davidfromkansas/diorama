const MAX_TEXT = 64 * 1024;
function bounded(value, limit = MAX_TEXT) {
  const text = String(value ?? '');
  return text.length <= limit ? text : text.slice(0, limit) + '\n[Output truncated]';
}
function blocks(value, depth = 0) {
  if (typeof value === 'string') return bounded(value);
  if (!Array.isArray(value) || depth > 2) return [];
  return value.slice(0, 100).flatMap(b => {
    if (!b || typeof b !== 'object') return [];
    if (['thinking', 'redacted_thinking', 'signature'].includes(b.type)) return [];
    if (b.type === 'text') return [{ type: 'text', text: bounded(b.text) }];
    if (b.type === 'tool_use') {
      const serialized = JSON.stringify(b.input ?? {});
      return [{ type: b.type, name: bounded(b.name ?? 'Tool', 200), id: b.id,
        input: serialized.length <= MAX_TEXT ? b.input ?? {} : { omitted: 'Inputs exceed preview limit' } }];
    }
    if (b.type === 'tool_result') return [{ type: b.type, tool_use_id: b.tool_use_id,
      is_error: b.is_error === true, content: blocks(b.content, depth + 1) }];
    if (['image', 'document', 'resource', 'resource_link', 'resourceLink'].includes(b.type)) {
      if (JSON.stringify(b).length <= 1024 * 1024) return [b];
      return [{ type: 'preview_limit_exceeded' }];
    }
    return [{ type: bounded(b.type ?? 'unknown', 100) }];
  });
}
export function historyPreview(messages) {
  // This adapter only transforms saved evidence; it never queues SDK input.
  let budget = 8 * 1024 * 1024;
  const rows = [];
  for (const m of messages.slice(-300).reverse()) {
    const content = blocks(m.message?.content);
    const row = { type: m.type, uuid: m.uuid, timestamp: m.timestamp, cwd: m.cwd,
      agentId: m.agentId ?? m.agent_id, isMeta: m.isMeta,
      message: { content: typeof content === 'string' ? [{ type: 'text', text: content }] : content,
        ...(m.message?.usage ? { usage: m.message.usage } : {}) } };
    // Keep provider event metadata; history discovery never submits user input.
    for (const key of ['subtype', 'status', 'duration_ms', 'duration_api_ms', 'usage', 'modelUsage',
      'total_cost_usd', 'rate_limit_info', 'description', 'summary', 'is_error', 'task_id',
      'tool_use_id', 'tool_use_result', 'parent_tool_use_id', 'output_file', 'error', 'errors', 'data', 'attachment',
      'mode', 'totalCostUSD', 'totalAPIDuration', 'totalAPIDurationWithoutRetries', 'totalToolDuration',
      'totalLinesAdded', 'totalLinesRemoved', 'totalDuration', 'startTime', 'hasUnknownModelCost']) {
      if (m[key] !== undefined) {
        const encoded = JSON.stringify(m[key]);
        row[key] = encoded.length <= MAX_TEXT ? m[key] : { omitted: 'Metadata exceeds preview limit' };
      }
    }
    budget -= JSON.stringify(row).length;
    if (budget < 0) break;
    rows.push(row);
  }
  return rows.reverse();
}
