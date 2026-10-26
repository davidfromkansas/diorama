// What a Claude Code session's agents are doing, from its transcripts and its hooks: a port of the
// app's ActivityParser (Claude branch), its activity summary and the agent fields the kitchen reads.
// The main agent and each subagent keep their own events; hooks and transcripts describe the same
// tool calls by the same ids, so whichever arrives first wins and the other merges into it.

import { KitchenActivity, TurnWork, feedEntries, modelName } from '../web/js/core/activity.js'

const bank = ('Milo Iris Otto Ada Felix Nora Leo Luna Theo Cleo Hugo Esme Finn Vera Arlo Ruby Remy Alba Nico Wren Axel Cora Ezra Faye Enzo Ivy ' +
  'Luca Mira Owen Opal Rory Sage Eli June Kai Lena Max Nina Orin Pia Quinn Rose Seth Tess Uri Veda Will Xena Yara Zane Atlas Basil Cedar Delta ' +
  'Echo Flora Glen Hazel Indigo Juno Koda Lark Maple Nova Olive Poppy Reed Sora Toby Uma Vale Willa Yuki Zora').split(' ')
const interruptions = new Set(['[Request interrupted by user]', '[Request interrupted by user for tool use]'])
const planningInputs = new Set(['TodoWrite', 'TaskCreate', 'TaskUpdate'])
const agentTools = new Set(['Agent', 'Task'])
const eventLimit = 4000, feedSent = 40
/** A main agent quiet this long is last known; a subagent stays "recently observed" this long after stopping. */
export const staleAfter = 30 * 60 * 1000, recentFor = 30 * 1000

const clip = (value, limit = 1000) => (typeof value === 'string' ? value.slice(0, limit) : value == null ? undefined : String(value).slice(0, limit))
const words = new Set(['i', 'we', 'you', 'can', 'could', 'would', 'please', 'want', 'like', 'to', 'a', 'an', 'the', 'for', 'me', 'this', 'that', 'it', 'and',
  'of', 'my', 'our', 'in', 'on', 'with', 'where', 'which', 'so', 'be', 'is', 'are', 'some', 'into', "let's", 'lets', 'go', 'ahead', 'help', 'just', 'also',
  'then', 'there', 'here', 'shows', 'show', 'using', 'use', 'by', 'at', 'from', 'as'])
/** A four-word label from a request (the app's TaskLabel.fallback). */
export function fallbackLabel(task) {
  return String(task ?? '').split(/[\s,;:!?()"]+/).map((w) => w.replace(/^[.']+|[.']+$/g, ''))
    .filter((w) => w && !/^\d+$/.test(w) && !words.has(w.toLowerCase())).slice(0, 4).map((w) => (/^[a-z]/.test(w) ? w[0].toUpperCase() + w.slice(1) : w)).join(' ')
}
/** A user message's own words: system reminders and command wrappers taken out. */
function promptText(content) {
  const text = typeof content === 'string' ? content : (content ?? []).filter((b) => b.type === 'text').map((b) => b.text).join('\n')
  return text.replace(/<system-reminder>[\s\S]*?<\/system-reminder>/g, '').replace(/<command-message>[\s\S]*?<\/command-message>/g, '')
    .replace(/<command-name>([\s\S]*?)<\/command-name>/g, '$1').replace(/<command-args>([\s\S]*?)<\/command-args>/g, ' $1')
    .replace(/<local-command-stdout>[\s\S]*?<\/local-command-stdout>/g, '').replace(/<[a-z-]+>|<\/[a-z-]+>/g, '').trim()
}

class AgentLog {
  constructor(id, isMain) {
    this.id = id; this.isMain = isMain
    this.events = new Map()
    this.name = null; this.agentType = null; this.description = null; this.prompt = null; this.firstPrompt = null; this.latestPrompt = null; this.prompts = 0
    this.model = null; this.startedAt = null; this.stoppedAt = null; this.transcript = null; this.sorted = null
  }
  add(event) {
    if (this.events.has(event.id)) {
      const known = this.events.get(event.id)
      // A hook and the transcript saw the same call: fill in what's missing. Hooks run a moment late,
      // so the transcript's time wins (a call denied at once can otherwise seem to end before it began).
      for (const key of ['tool', 'detail', 'input', 'state']) if (known[key] == null && event[key] != null) known[key] = event[key]
      if (known.hook && !event.hook) { known.time = event.time; known.hook = false; known.source = event.source; this.sorted = null }
      return
    }
    this.events.set(event.id, event)
    this.sorted = null
    if (this.startedAt == null || event.time < this.startedAt) this.startedAt = event.time
    if (this.events.size > eventLimit * 1.25) {
      const keep = this.list().slice(-eventLimit)
      this.events = new Map(keep.map((e) => [e.id, e]))
      this.sorted = null
    }
  }
  list() {
    if (!this.sorted) {
      let all = [...this.events.values()].sort((a, b) => a.time - b.time || a.seq - b.seq)
      // A prompt seen by its hook and in the transcript is one turn.
      all = all.filter((e, i) => !(e.kind === 'started' && e.hook && all.some((o) => o !== e && o.kind === 'started' && !o.hook && Math.abs(o.time - e.time) < 8000)))
      this.sorted = all
    }
    return this.sorted
  }
}

let sequence = 0
const event = (fields) => ({ seq: sequence++, ...fields, callID: fields.call })

export class SessionModel {
  constructor(sessionId) {
    this.sessionId = sessionId
    this.agents = new Map([['main', new AgentLog('main', true)]])
    this.agents.get('main').name = bank[0]
    this.aiTitle = null; this.cwd = null; this.ended = false; this.version = 0
    this.launches = []   // { description, prompt, subagentType, time } from the main agent's Agent calls
    this.taskIDs = 0
  }

  agent(id) {
    if (!id) return this.agents.get('main')
    if (!this.agents.has(id)) {
      const log = new AgentLog(id, false)
      log.name = bank[(this.agents.size) % bank.length] + (this.agents.size >= bank.length ? ' ' + (Math.floor(this.agents.size / bank.length) + 1) : '')
      this.agents.set(id, log)
    }
    return this.agents.get(id)
  }

  // MARK: Transcripts

  /** One transcript record; `agentId` is null for the main transcript. */
  record(r, agentId = null) {
    if (!r || typeof r !== 'object') return
    if (r.type === 'ai-title' && r.aiTitle && !agentId) { this.aiTitle = r.aiTitle; this.version++; return }
    if (r.cwd && !this.cwd) this.cwd = r.cwd
    const message = r.message
    if (!message || (r.type !== 'user' && r.type !== 'assistant')) return
    if (!agentId && r.isSidechain) return
    const log = this.agent(agentId)
    const time = Date.parse(r.timestamp) || Date.now()
    const uuid = r.uuid ?? `${agentId ?? 'main'}-${time}-${sequence}`
    const blocks = Array.isArray(message.content) ? message.content : []
    const sole = typeof message.content === 'string' ? message.content : blocks.length === 1 && blocks[0].type === 'text' ? blocks[0].text : null
    const add = (fields) => { log.add(event({ time, source: 'transcript', ...fields })); this.version++ }
    if (r.type === 'assistant' && message.model && message.model !== '<synthetic>') log.model = message.model
    if (r.type === 'user' && sole != null && interruptions.has(sole.trim())) { add({ id: uuid + ':interrupted', kind: 'interrupted' }); return }
    const system = r.isMeta === true || r.queueTranscriptOnly === true
    if (r.type === 'user' && !system && !blocks.some((b) => b.type === 'tool_result') && (typeof message.content === 'string' || blocks.some((b) => b.type === 'text'))) {
      const raw = typeof message.content === 'string' ? message.content : blocks.filter((b) => b.type === 'text').map((b) => b.text).join('\n')
      // A subagent's report or a finished background task wakes the agent: a turn, not a request.
      const notice = !!r.origin?.kind || /^\s*<task-notification>/.test(raw)
      const command = /<command-name>/.test(raw)
      const text = notice ? '' : promptText(message.content)
      if (text || notice) {
        if (text && !command) {
          log.prompts += 1
          if (!log.firstPrompt) log.firstPrompt = text.slice(0, 2000)
          log.latestPrompt = text.slice(0, 2000)
        }
        if (text && command) log.command ??= text.slice(0, 200)
        if (agentId && !log.prompt && text) { log.prompt = text; this.matchLaunch(log) }
        add({ id: uuid + ':started', kind: 'started', detail: clip(notice ? 'Background task finished' : text, 300) })
      }
    }
    blocks.forEach((block, index) => {
      if (block.type === 'tool_use') {
        const input = block.input ?? {}
        const detail = clip(input.command ?? input.file_path ?? input.skill ?? input.pattern ?? input.url ?? input.query ?? input.description)
        add({ id: 'start:' + block.id, kind: 'toolStarted', call: block.id, tool: block.name, detail, input: planningInputs.has(block.name) ? input : undefined,
          state: block.name === 'AskUserQuestion' ? 'input' : 'working' })
        if (!agentId && agentTools.has(block.name)) {
          this.launches.push({ description: input.description, prompt: input.prompt, subagentType: input.subagent_type, time })
          for (const other of this.agents.values()) if (!other.isMain && !other.description) this.matchLaunch(other)
        }
      } else if (block.type === 'tool_result') {
        add({ id: 'end:' + block.tool_use_id, kind: block.is_error ? 'toolFailed' : 'toolFinished', call: block.tool_use_id })
      } else if (block.type === 'text' && r.type === 'assistant' && block.text) {
        add({ id: `${uuid}:${index}`, kind: 'commentary', detail: clip(block.text) })
      }
    })
    if (r.type === 'assistant' && message.stop_reason === 'end_turn') add({ id: uuid + ':finished', kind: 'finished' })
  }

  /** What Claude Code notes about a subagent beside its transcript (its type and the task it was given). */
  agentMeta(agentId, meta) {
    const log = this.agent(agentId)
    if (meta?.description && !log.description) { log.description = String(meta.description); this.version++ }
    if (meta?.agentType && !log.agentType) { log.agentType = String(meta.agentType); this.version++ }
  }

  /** A subagent's task, from the main agent's call that started it (its prompt is the subagent's first message). */
  matchLaunch(log) {
    if (!log.prompt) return
    const launch = this.launches.find((l) => l.prompt && (l.prompt === log.prompt || l.prompt.trim() === log.prompt.trim()))
    if (launch) { log.description = launch.description ?? null; log.agentType ??= launch.subagentType ?? null; this.version++ }
  }

  // MARK: Hooks

  hook(r) {
    const name = r.hook_event_name
    if (!name) return
    const now = Date.now()
    const log = this.agent(r.agent_id || null)
    const call = clip(r.tool_use_id, 200)
    const input = r.tool_input && typeof r.tool_input === 'object' ? r.tool_input : null
    const detail = clip(r.error ?? input?.command ?? input?.file_path ?? input?.skill ?? input?.pattern ?? input?.url ?? input?.description)
    const add = (fields) => { log.add(event({ time: now, source: 'hook', hook: true, ...fields, id: fields.id ?? `hook:${now}:${sequence}` })); this.version++ }
    if (r.cwd && !this.cwd) this.cwd = r.cwd
    switch (name) {
      case 'UserPromptSubmit': {
        const text = promptText(r.prompt ?? '')
        if (text && !/^\//.test(text)) { log.prompts += 1; log.firstPrompt ??= text.slice(0, 2000); log.latestPrompt = text.slice(0, 2000) }
        add({ kind: 'started', detail: clip(text, 300) })
        break
      }
      case 'PreToolUse':
        add({ id: call ? 'start:' + call : undefined, kind: 'toolStarted', call, tool: r.tool_name, detail, input: planningInputs.has(r.tool_name) ? input : undefined,
          state: r.tool_name === 'AskUserQuestion' ? 'input' : 'working' })
        if (!r.agent_id && agentTools.has(r.tool_name) && input) {
          this.launches.push({ description: input.description, prompt: input.prompt, subagentType: input.subagent_type, time: now })
        }
        break
      case 'PostToolUse': add({ id: call ? 'end:' + call : undefined, kind: 'toolFinished', call }); break
      case 'PostToolUseFailure': add({ id: call ? 'end:' + call : undefined, kind: 'toolFailed', call, detail }); break
      case 'PermissionRequest': {
        const question = r.tool_name === 'AskUserQuestion'
        add({ kind: question ? 'input' : 'approval', call, tool: r.tool_name, detail })
        break
      }
      case 'Notification':
        if (r.notification_type === 'permission_prompt') add({ kind: 'approval', detail: clip(r.message) })
        else if (r.notification_type === 'idle_prompt') add({ kind: 'idle' })
        else if (r.notification_type === 'elicitation_dialog' || r.notification_type === 'elicitation_url_dialog') add({ kind: 'input', detail: clip(r.message) })
        break
      case 'Stop': add({ kind: 'stopping' }); break
      case 'StopFailure': add({ kind: 'failed', detail: clip(r.error ?? r.message) }); break
      case 'SubagentStart': {
        const sub = this.agent(r.agent_id)
        sub.agentType ??= r.agent_type ?? null
        sub.add(event({ time: now, source: 'hook', hook: true, id: 'agent-start:' + r.agent_id, kind: 'agentStarted' }))
        this.version++
        break
      }
      case 'SubagentStop': {
        const sub = this.agent(r.agent_id)
        sub.agentType ??= r.agent_type ?? null
        if (r.agent_transcript_path) sub.transcript = r.agent_transcript_path
        sub.stoppedAt = now
        sub.add(event({ time: now, source: 'hook', hook: true, id: 'agent-stop:' + r.agent_id, kind: 'agentStopped' }))
        this.version++
        break
      }
      case 'SessionEnd': this.ended = true; add({ kind: 'sessionEnded' }); break
      case 'SessionStart': this.ended = false; break
    }
  }

  // MARK: Agents

  /** The kitchen's view of every agent now. */
  snapshot(now = Date.now()) {
    const main = this.agents.get('main')
    const mainView = this.view(main, now)
    const agents = [mainView]
    for (const log of this.agents.values()) {
      if (log.isMain || !log.events.size) continue
      agents.push(this.view(log, now, mainView))
    }
    return {
      session: {
        id: this.sessionId, title: this.aiTitle ?? fallbackLabel(main.firstPrompt) ?? 'Claude Code', task: main.firstPrompt ?? '',
        project: this.cwd ? this.cwd.split(/[\\/]/).filter(Boolean).pop() : '', cwd: this.cwd, model: main.model, ended: this.ended,
      },
      agents,
    }
  }

  view(log, now, main = null) {
    const events = log.list()
    // A hook can arrive after the transcript already shows the call's outcome (a prompt answered or denied).
    const ended = new Set(events.filter((e) => e.call && (e.kind === 'toolFinished' || e.kind === 'toolFailed')).map((e) => e.call))
    const open = new Set()
    let status = 'ready', reason = null, turn = 0, pending = null, lastText = '', lastEvent = null, stopped = null
    let latestTool = '', latestDetail = '', lastToolAt = null, lastCommentaryAt = null, turnStartIndex = 0, turnStartedAt = null
    events.forEach((e, index) => {
      lastEvent = e
      switch (e.kind) {
        case 'started':
          turn += 1; status = 'working'; pending = null; lastText = ''; latestTool = ''; latestDetail = ''; turnStartIndex = index; turnStartedAt = e.time
          break
        case 'agentStarted':
          if (status === 'ready') { status = 'working'; turn = Math.max(turn, 1) }
          break
        case 'toolStarted':
          if (e.call && !ended.has(e.call)) open.add(e.call)
          if (status !== 'working' && status !== 'waiting') { status = 'working'; turn = Math.max(turn, 1) }
          if (pending && pending.call !== e.call) pending = null
          latestTool = e.tool ?? ''; latestDetail = e.detail ?? ''; lastToolAt = e.time
          if (e.state === 'input') pending = { call: e.call, reason: 'input' }
          if (!pending && status === 'waiting') status = 'working'
          break
        case 'toolFinished': case 'toolFailed':
          open.delete(e.call)
          lastToolAt = e.time
          if (pending && (!pending.call || pending.call === e.call)) pending = null
          if (!pending && status === 'waiting') status = 'working'
          break
        case 'commentary':
          lastText = e.detail ?? ''; lastCommentaryAt = e.time
          if (pending && !pending.call) pending = null
          break
        case 'approval': case 'input':
          // Claude follows its question UI with a generic permission notification: keep the question.
          if (e.kind === 'approval' && !e.call && pending?.reason === 'input') break
          if (e.call ? ended.has(e.call) : !open.size) break
          pending = { call: e.call ?? pending?.call ?? null, reason: e.kind }
          if (e.tool) latestTool = e.tool
          if (status !== 'working' && status !== 'waiting') status = 'working'
          break
        case 'finished': case 'stopping':
          status = 'done'; pending = null
          break
        case 'idle':
          if (status === 'working') status = 'done'
          break
        case 'agentStopped':
          if (status !== 'failed' && status !== 'stopped') status = 'done'
          pending = null; stopped = e.time
          break
        case 'interrupted': status = 'stopped'; pending = null; break
        case 'failed': status = 'failed'; pending = null; break
      }
    })
    const turnEvents = events.slice(turnStartIndex)
    const turnHasEdits = turnEvents.some((e) => e.kind === 'toolStarted' && KitchenActivity.isEditing(e.tool, e.detail))
    if (pending) { status = 'waiting'; reason = pending.reason }
    else if (status === 'done' && log.isMain && lastText.trim().endsWith('?') && !turnHasEdits) { status = 'waiting'; reason = 'input' }
    // A subagent cut off with its parent (an interrupt, a closed session) stops where it was.
    if (!log.isMain && main && (status === 'working' || status === 'waiting') && ['stopped', 'failed'].includes(main.status) && (lastEvent?.time ?? 0) <= (main.meaningfulUpdatedAt ?? 0)) {
      status = 'stopped'; reason = null; stopped = main.meaningfulUpdatedAt
    }
    const last = lastEvent?.time ?? now
    let freshness
    if (log.isMain) freshness = this.ended || now - last > staleAfter ? 'lastKnown' : 'live'
    else if (status === 'working' || status === 'waiting') freshness = this.ended || now - last > staleAfter ? 'lastKnown' : 'live'
    else freshness = now - (stopped ?? last) < recentFor && !this.ended ? 'recentlyObserved' : 'lastKnown'
    const plan = this.plan(events, turn)
    const checklist = plan?.checklist ?? []
    const planProgress = checklist.length > 1 && !plan.tasksPreviousTurn ? { kind: 'steps', done: plan.completedTaskCount, total: checklist.length } : null
    const feed = feedEntries(events).slice(-feedSent)
    const task = log.isMain ? (log.firstPrompt ?? log.command ?? '') : (log.description ?? log.prompt ?? log.firstPrompt ?? '')
    const title = log.isMain ? (this.aiTitle ?? fallbackLabel(task)) : (log.description ?? fallbackLabel(task))
    const model = log.model ?? (log.isMain ? null : this.agents.get('main').model)
    return {
      id: log.id, name: log.name, isMain: log.isMain, agentType: log.isMain ? null : log.agentType,
      status, attentionReason: status === 'waiting' ? (reason === 'approval' ? 'approval' : reason === 'input' ? 'input' : 'other') : null, freshness,
      latestTool, latestToolDetail: latestDetail, turnHasEdits, turnWork: TurnWork.from(events).toJSON(), feed,
      lastToolAt, lastCommentaryAt, turnStartedAt, plan, planProgress,
      completionKey: `claude:${this.sessionId}:${turn}` + (log.isMain ? '' : `:agent:${log.id}`),
      meaningfulEventID: lastEvent?.id ?? null, meaningfulUpdatedAt: lastEvent?.time ?? null, observedAt: now, startedAt: log.startedAt,
      latestRequest: log.isMain && log.prompts > 1 ? log.latestPrompt : null,
      task, title, model, modelLabel: model ? modelName(model).replace(/^Claude /, '') : '',
    }
  }

  /** The agent's checklist: its latest TodoWrite, or the tasks it created and updated. */
  plan(events, currentTurn) {
    let todo = null, todoTurn = 0, tasks = null, tasksTurn = 0, turn = 0, next = 0
    for (const e of events) {
      if (e.kind === 'started') turn += 1
      if (e.kind !== 'toolStarted' || !e.input) continue
      if (e.tool === 'TodoWrite' && Array.isArray(e.input.todos)) {
        todo = e.input.todos.map((t) => ({ title: String(t.content ?? t.activeForm ?? ''), status: String(t.status ?? 'pending') }))
        todoTurn = Math.max(turn, 1)
      } else if (e.tool === 'TaskCreate') {
        tasks ??= new Map()
        next += 1
        tasks.set(String(next), { title: String(e.input.subject ?? e.input.title ?? e.input.description ?? 'Task'), status: 'pending' })
        tasksTurn = Math.max(turn, 1)
      } else if (e.tool === 'TaskUpdate' && tasks) {
        const task = tasks.get(String(e.input.taskId ?? e.input.id ?? ''))
        if (!task) continue
        if (e.input.status === 'deleted') tasks.delete(String(e.input.taskId ?? e.input.id))
        else { if (e.input.status) task.status = String(e.input.status); if (e.input.subject) task.title = String(e.input.subject) }
        tasksTurn = Math.max(turn, 1)
      }
    }
    const useTasks = tasks && (!todo || tasksTurn >= todoTurn)
    const checklist = useTasks ? [...tasks.values()] : todo
    if (!checklist?.length) return null
    const planTurn = useTasks ? tasksTurn : todoTurn
    return { checklist, tasksPreviousTurn: planTurn < currentTurn, completedTaskCount: checklist.filter((s) => s.status === 'completed').length }
  }
}
