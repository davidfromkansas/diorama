// Hermes sessions for the kitchen: the Hermes plugin (`hermes_bridge.py`) posts its hook events
// here, and they feed the same SessionModel the Claude Code and Codex transcripts do. Hermes names
// its tools differently, so each is given the kitchen name for the same kind of work (terminal →
// Bash, patch → Edit, todo_list → TodoWrite, delegate_task → Agent…). A subagent reports under its
// own session id; it joins its parent's kitchen once its subagent_start has been seen.

const clip = (value, limit = 1000) => (typeof value === 'string' ? value.slice(0, limit) : value == null ? undefined : String(value).slice(0, limit))

/** Hermes tool → the kitchen's name for the same work. Tools not listed keep their own name. */
const toolNames = {
  terminal: 'Bash', process_manage: 'Bash', read_terminal: 'Bash', close_terminal: 'Bash', execute_code: 'Bash',
  read_file: 'Read', search_files: 'Grep', session_search: 'Grep', web_search: 'WebSearch', x_search: 'WebSearch', web_extract: 'WebFetch',
  write_file: 'Write', patch: 'Edit', todo_list: 'TodoWrite', todo: 'TodoWrite', delegate_task: 'Agent', clarify: 'AskUserQuestion',
  skill_view: 'Skill', skills_list: 'Skill', skill_manage: 'Skill', vision_analyze: 'view_image', video_analyze: 'view_image',
}
export const kitchenTool = (name) => toolNames[name] ?? name ?? ''

/** What the tool is working on, for its tag and its step in the feed. */
function detailOf(tool, args) {
  if (!args || typeof args !== 'object') return undefined
  if (tool === 'execute_code') return clip(`python - <<'PY'\n${args.code ?? ''}\nPY`)
  if (tool === 'delegate_task') return clip(args.goal ?? (Array.isArray(args.tasks) ? args.tasks.map((t) => t?.goal).filter(Boolean).join('; ') : undefined))
  if (tool === 'clarify') return clip(args.question ?? args.questions?.[0]?.question ?? args.questions?.[0])
  return clip(args.command ?? args.path ?? args.file_path ?? args.pattern ?? args.query ?? args.url ?? args.urls?.[0] ?? args.name ?? args.skill ?? args.goal ?? args.description)
}
/** The checklist a todo_list call writes, in TodoWrite's shape. */
function todoInput(args) {
  const items = Array.isArray(args?.todos) ? args.todos : null
  return items ? { todos: items.map((t) => ({ content: String(t?.content ?? ''), status: t?.status === 'cancelled' ? 'completed' : String(t?.status ?? 'pending') })) } : undefined
}

// MARK: Which kitchen an event belongs to

/** child session id → { root, agent }; a compacted or reset session's new id → its first id. */
const children = new Map()
const aliases = new Map()
/** Events from a subagent that arrived before its subagent_start (kept briefly). */
const early = new Map()
/** Aliases learned since the server last asked (a page may already be following the old id). */
let learned = []
export const takeAliases = () => { const list = learned; learned = []; return list }
const alias = (from, to) => {
  if (!from || !to || from === to || aliases.has(from) || hermesOwner(to).session === from) return
  aliases.set(from, to)
  learned.push([from, to])
}

/** The kitchen session an id belongs to (following compactions/resets) and the agent in it. */
export function hermesOwner(id) {
  let session = String(id ?? '')
  for (let i = 0; i < 8 && aliases.has(session); i++) session = aliases.get(session)
  const child = children.get(session)
  return child ? { session: child.root, agent: child.agent } : { session, agent: null }
}

/**
 * Reads one event into the kitchen. `model(id)` returns the SessionModel for a kitchen session id
 * (creating it); `adopt(id)` may name an open, still-empty kitchen a new session should fill.
 * Returns the kitchen session ids it changed.
 */
export function hermesEvent(r, model, adopt = () => null) {
  if (!r || typeof r !== 'object' || !r.event) return []
  const changed = new Set()
  const time = Number(r.time) || Date.now()
  if (r.event === 'post_compaction' && r.old_session_id && r.session_id) { alias(String(r.session_id), String(r.old_session_id)); return [] }
  if (r.event === 'on_session_reset' && r.old_session_id && r.new_session_id) { alias(String(r.new_session_id), String(r.old_session_id)); return [] }
  // A chat's kitchen is named by its session key (what /kitchen sees before the first message, and
  // steady across compactions); the agent's session id joins it on the chat's first turn.
  if ((r.event === 'pre_llm_call' || r.event === 'on_session_start') && !r.parent_session_id && r.session_id && !aliases.has(String(r.session_id))) {
    const id = String(r.session_id)
    alias(id, r.session_key ? String(r.session_key) : adopt(id))
  }
  if (r.event === 'subagent_start' && r.child_session_id) {
    const parent = hermesOwner(r.session_id)
    const id = String(r.child_session_id)
    children.set(id, { root: parent.session, agent: id })
    const m = model(parent.session)
    const log = m.agent(id)
    log.description ??= clip(r.child_goal, 300) ?? null
    log.agentType ??= r.child_role ?? null
    log.prompt ??= r.child_goal ?? null
    log.add(m.event({ time, source: 'hook', id: 'agent-start:' + id, kind: 'agentStarted' }))
    m.version++
    changed.add(parent.session)
    for (const waiting of early.get(id) ?? []) for (const s of hermesEvent(waiting, model)) changed.add(s)
    early.delete(id)
    return [...changed]
  }
  if (r.event === 'subagent_stop' && r.child_session_id) {
    const owner = hermesOwner(r.child_session_id)
    if (!owner.agent) return []
    const m = model(owner.session)
    const log = m.agent(owner.agent)
    log.stoppedAt = time
    if (/fail|error/i.test(String(r.child_status ?? ''))) log.add(m.event({ time, source: 'hook', id: 'agent-failed:' + owner.agent, kind: 'failed', detail: clip(r.child_summary) }))
    log.add(m.event({ time, source: 'hook', id: 'agent-stop:' + owner.agent, kind: 'agentStopped' }))
    m.version++
    return [owner.session]
  }
  // A subagent's own events can beat its subagent_start: hold them until it arrives.
  if (r.parent_session_id && !children.has(String(r.session_id)) && r.event === 'pre_llm_call') {
    const list = early.get(String(r.session_id)) ?? []
    if (list.length < 200) list.push(r)
    early.set(String(r.session_id), list)
    setTimeout(() => { if (early.has(String(r.session_id))) { early.delete(String(r.session_id)) } }, 30000).unref?.()
    return []
  }
  const owner = hermesOwner(r.session_id)
  if (!owner.session) return []
  const m = model(owner.session)
  const log = m.agent(owner.agent)
  const add = (fields) => { log.add(m.event({ time, source: 'hook', ...fields, id: fields.id ?? `hermes:${r.id}` })); m.version++ }
  const call = r.tool_call_id ? String(r.tool_call_id) : null
  switch (r.event) {
    case 'on_session_start': if (r.model) log.model = r.model; m.ended = false; break
    case 'pre_llm_call': {
      if (r.model) log.model = r.model
      const text = String(r.user_message ?? '').trim()
      if (text && !/^\//.test(text)) {
        log.prompts += 1
        log.firstPrompt ??= text.slice(0, 2000)
        log.latestPrompt = text.slice(0, 2000)
        if (owner.agent && !log.prompt) log.prompt = text
      }
      add({ id: `hermes:${r.turn_id || r.id}:started`, kind: 'started', detail: clip(text, 300) })
      break
    }
    case 'on_interim_message': if (r.text) add({ kind: 'commentary', detail: clip(r.text) }); break
    case 'pre_tool_call': {
      const tool = kitchenTool(r.tool_name)
      const input = tool === 'TodoWrite' ? todoInput(r.args) : undefined
      add({ id: call ? 'start:' + call : undefined, kind: 'toolStarted', call, tool, detail: detailOf(r.tool_name, r.args), input, state: tool === 'AskUserQuestion' ? 'input' : 'working' })
      if (!owner.agent && tool === 'Agent' && r.args) m.launches.push({ description: clip(r.args.goal, 300), prompt: r.args.goal, subagentType: r.args.role ?? null, time })
      break
    }
    case 'post_tool_call': {
      const failed = (r.status && r.status !== 'ok') || (r.exit_code != null && r.exit_code !== 0)
      add({ id: call ? 'end:' + call : undefined, kind: failed ? 'toolFailed' : 'toolFinished', call, detail: failed ? clip(r.error_message) : undefined })
      break
    }
    case 'post_llm_call':
      if (r.assistant_response) add({ id: `hermes:${r.turn_id || r.id}:reply`, kind: 'commentary', detail: clip(r.assistant_response) })
      add({ id: `hermes:${r.turn_id || r.id}:finished`, kind: 'finished' })
      break
    case 'on_session_end':
      // Fires after every turn with its outcome (post_llm_call already marked a finished turn); the
      // CLI's exit sends a reduced shape with only a reason, which ends the session.
      if (r.interrupted) add({ id: `hermes:${r.turn_id || r.id}:interrupted`, kind: 'interrupted' })
      else if (r.failed) add({ id: `hermes:${r.turn_id || r.id}:failed`, kind: 'failed', detail: clip(r.turn_exit_reason) })
      else if (r.completed) add({ id: `hermes:${r.turn_id || r.id}:finished`, kind: 'finished' })
      else if (r.completed == null && r.failed == null && r.interrupted == null && r.reason) { m.ended = true; add({ kind: 'sessionEnded' }) }
      break
    case 'on_human_input_request':
      add({ id: `hermes:input:${r.request_id || r.id}`, kind: r.kind === 'approval' ? 'approval' : 'input', detail: clip(r.prompt) })
      break
  }
  return [owner.session]
}
