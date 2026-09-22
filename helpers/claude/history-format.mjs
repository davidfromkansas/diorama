export function historyPreview(messages) {
  return messages.slice(-300).map(m => {
    const content = typeof m.message?.content === 'string' ? [{ type: 'text', text: m.message.content }] : (Array.isArray(m.message?.content) ? m.message.content : []);
    return { type: m.type, uuid: m.uuid, message: { content: content.flatMap(b => {
      if (b.type === 'text') return [{ type: 'text', text: String(b.text ?? '').slice(0, 8000) }];
      if (b.type === 'tool_use') return [{ type: 'tool_use', name: String(b.name ?? 'Tool'), id: b.id }];
      if (b.type === 'tool_result') return [{ type: 'tool_result', tool_use_id: b.tool_use_id, is_error: b.is_error === true }];
      return []; // Never copy thinking or encrypted reasoning into the UI.
    }) } };
  });
}
