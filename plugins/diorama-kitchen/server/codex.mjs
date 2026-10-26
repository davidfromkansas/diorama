// Codex sessions for the kitchen: reads a Codex rollout (`~/.codex/sessions/…/rollout-…-<id>.jsonl`)
// into the same SessionModel the Claude Code transcripts feed. A port of the app's ActivityParser
// (Codex branch): turns from task events, tools from function calls and their outputs (code-mode
// scripts split into their inner calls), plans from update_plan, and subagents from the rollouts
// whose session_meta names this session as their parent.

import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'
import { KitchenActivity, commandTools } from '../web/js/core/activity.js'

export const codexHome = () => process.env.CODEX_HOME || path.join(os.homedir(), '.codex')
const clip = (value, limit = 1000) => (typeof value === 'string' ? value.slice(0, limit) : value == null ? undefined : String(value).slice(0, limit))

/** Files named by an apply_patch patch (`*** Add File: path`, `*** Update File:`, `*** Delete File:`). */
export function patchFiles(patch) {
  const files = []
  for (const line of String(patch ?? '').split('\n')) {
    for (const prefix of ['*** Add File: ', '*** Update File: ', '*** Delete File: ']) {
      if (!line.startsWith(prefix)) continue
      const file = line.slice(prefix.length).trim()
      if (file && !files.includes(file)) files.push(file)
    }
  }
  return files
}
/** The exit status in Codex shell output: `Process exited with code N` or `"exit_code":N`. */
export function exitCode(output) {
  const match = /Process exited with code (-?\d+)|"exit_code"\s*:\s*(-?\d+)|^Exit code:\s*(-?\d+)/m.exec(String(output ?? ''))
  return match ? Number(match[1] ?? match[2] ?? match[3]) : null
}
const unquote = (literal) => {
  if (literal.startsWith('"')) { try { return JSON.parse(literal) } catch {} }
  return literal.slice(1, -1)
}
/** Every `tools.<name>(` call in a Codex code-mode script, with a command, patch files or URI as detail. */
export function codeModeCalls(script) {
  const tool = /\btools\.([A-Za-z_][A-Za-z0-9_]*)\s*\(/g
  const matches = [...String(script).matchAll(tool)]
  return matches.map((match, index) => {
    const end = index + 1 < matches.length ? matches[index + 1].index : script.length
    const body = script.slice(match.index + match[0].length, end), name = match[1]
    if (name === 'apply_patch') return { tool: name, detail: patchFiles(body.replaceAll('\\n', '\n')).join('\n') }
    if (name === 'write_stdin') { const s = /session_id\s*:\s*(\d+)/.exec(body); return { tool: name, detail: s ? 'session=' + s[1] : null } }
    const command = /\bcmd\s*:\s*("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`[^`]*`)/.exec(body)
    if (command) return { tool: name, detail: KitchenActivity.withoutHeredocs(unquote(command[1])) }
    const uri = /\buri\s*:\s*["'`]([^"'`]+)["'`]/.exec(body)
    return { tool: name, detail: uri ? uri[1] : null }
  })
}
/** The checklist from a code-mode `tools.update_plan({plan:[{step:"…",status:"…"}]})` call. */
export function codeModePlan(script) {
  const start = String(script).indexOf('tools.update_plan(')
  if (start < 0) return null
  const steps = [...script.slice(start).matchAll(/step\s*:\s*"((?:[^"\\]|\\.)*)"\s*,\s*status\s*:\s*"(\w+)"/g)]
    .map((m) => { let step = m[1]; try { step = JSON.parse('"' + m[1] + '"') } catch {} return { step, status: m[2] } })
  return steps.length ? steps : null
}
const parseJSON = (text) => { try { return JSON.parse(text) } catch { return null } }
const textOf = (content) => typeof content === 'string' ? content : (Array.isArray(content) ? content.map((c) => c?.text ?? '').filter(Boolean).join('\n') : '')
/** Codex wraps context (environment, instructions) in tags inside user messages: keep the request. */
function requestText(text) {
  return String(text ?? '').replace(/<(environment_context|user_instructions|user_shell_command|turn_aborted|subagent_notification)>[\s\S]*?<\/\1>/g, '')
    .replace(/^# AGENTS\.md instructions[\s\S]*?<\/INSTRUCTIONS>/m, '').trim()
}
const plan = (steps) => ({ plan: steps.map((s) => ({ step: String(s.step ?? s.content ?? ''), status: String(s.status ?? 'pending') })) })

/** Reads one rollout record into `model`; `agentId` is null for the session's own rollout. */
export function codexRecord(model, r, agentId = null) {
  const p = r?.payload
  if (!p || typeof p !== 'object') return
  const log = model.agent(agentId)
  const time = Date.parse(r.timestamp) || Date.now()
  const turn = p.turn_id ?? log.codexTurn ?? ''
  if (p.turn_id) log.codexTurn = p.turn_id
  const add = (fields) => { log.add(model.event({ time, source: 'transcript', ...fields })); model.version++ }
  const scope = agentId ?? 'main'
  if (r.type === 'session_meta') {
    if (p.cwd && !model.cwd) model.cwd = p.cwd
    if (agentId) {
      const spawn = (p.source?.subagent ?? p.source?.subAgent)?.thread_spawn
      const nickname = p.agent_nickname ?? spawn?.agent_nickname
      if (nickname && !log.description) log.description = String(nickname)
      log.agentType ??= p.agent_role ?? spawn?.agent_role ?? null
    }
    return
  }
  if (r.type === 'turn_context') { if (p.model) log.model = p.model; if (p.cwd && !model.cwd) model.cwd = p.cwd; return }
  if (r.type === 'event_msg') {
    switch (p.type) {
      case 'task_started': add({ id: `${scope}:${turn}:started`, kind: 'started', detail: '' }); break
      case 'task_complete': add({ id: `${scope}:${turn}:finished`, kind: 'finished' }); break
      case 'turn_aborted': add({ id: `${scope}:${turn}:interrupted`, kind: 'interrupted' }); break
      case 'user_message': {
        const text = requestText(p.message)
        if (!text) break
        log.prompts += 1
        log.firstPrompt ??= text.slice(0, 2000); log.latestPrompt = text.slice(0, 2000)
        if (agentId && !log.prompt) { log.prompt = text; model.matchLaunch(log) }
        break
      }
      case 'exec_approval_request': case 'apply_patch_approval_request':
        add({ id: `approval:${p.call_id ?? time}`, kind: 'approval', call: p.call_id, tool: p.type === 'apply_patch_approval_request' ? 'apply_patch' : 'exec_command',
          detail: clip(Array.isArray(p.command) ? p.command.join(' ') : p.command ?? p.reason) })
        break
      case 'request_user_input': add({ id: `input:${p.call_id ?? time}`, kind: 'input', call: p.call_id, detail: clip(p.questions?.[0]?.question) }); break
      case 'exec_command_end':
        if (p.call_id) add({ id: 'end:' + p.call_id, kind: p.exit_code ? 'toolFailed' : 'toolFinished', call: p.call_id })
        break
      case 'item_started': case 'item_completed': item(p.item, p.type === 'item_completed'); break
    }
    return
  }
  if (r.type !== 'response_item') return
  const call = p.call_id
  if (p.type === 'message' && p.role === 'assistant') {
    const text = textOf(p.content)
    if (text) add({ id: `${scope}:${p.id ?? time}:commentary`, kind: 'commentary', detail: clip(text) })
    return
  }
  if (p.type === 'web_search_call') {
    add({ id: 'start:' + (p.id ?? time), kind: 'toolStarted', call: p.id, tool: 'web_search', detail: clip(p.action?.query ?? p.action?.url) })
    if (p.id) add({ id: 'end:' + p.id, kind: 'toolFinished', call: p.id })
    return
  }
  if (p.type === 'function_call' || p.type === 'custom_tool_call' || p.type === 'local_shell_call') {
    const name = p.name ?? (p.type === 'local_shell_call' ? 'local_shell' : '')
    const started = (id, tool, detail, input) => {
      add({ id: 'start:' + id, kind: 'toolStarted', call: id, tool, detail: clip(detail), input, state: tool === 'request_user_input' ? 'input' : 'working' })
      if (!agentId && tool === 'spawn_agent' && input) model.launches.push({ description: input.agent_nickname ?? input.description, prompt: input.message ?? input.prompt, subagentType: input.agent_role, time })
    }
    if (name === 'apply_patch' && typeof p.input === 'string') return started(call, 'apply_patch', patchFiles(p.input).join('\n'))
    // Code-mode calls wrap real tools in JavaScript, often several per script: each becomes its own call.
    if (typeof p.input === 'string') {
      const inner = codeModeCalls(p.input)
      if (inner.length) {
        const steps = codeModePlan(p.input)
        inner.forEach((call_, index) => {
          const last = index === inner.length - 1
          const id = last ? call : `${call}#${index}`
          started(id, call_.tool, call_.detail, call_.tool === 'update_plan' && steps ? plan(steps) : undefined)
          if (!last && !commandTools.has(call_.tool.toLowerCase())) add({ id: 'end:' + id, kind: 'toolFinished', call: id })
        })
        return
      }
    }
    const args = typeof p.arguments === 'string' ? parseJSON(p.arguments) : p.arguments ?? p.action ?? null
    if (name === 'update_plan' && Array.isArray(args?.plan)) return started(call, 'update_plan', args.explanation ?? '', plan(args.plan))
    const polled = name === 'write_stdin' && args?.session_id != null ? 'session=' + args.session_id : null
    let command = args?.command ?? args?.cmd
    if (Array.isArray(command)) command = command.length === 3 && /^(ba|z)?sh$/.test(command[0]) && command[1].startsWith('-') ? command[2] : command.join(' ')
    const detail = polled ?? (typeof command === 'string' ? KitchenActivity.withoutHeredocs(command) : null) ?? args?.file_path ?? args?.path ?? args?.query ?? args?.message ?? args?.description
    return started(call, name, detail, name === 'spawn_agent' ? args : undefined)
  }
  if (p.type === 'function_call_output' || p.type === 'custom_tool_call_output') {
    const finish = (output, id) => add({ id: 'end:' + id, kind: (exitCode(output) ?? 0) !== 0 || /^(rejected|aborted)/i.test(String(output).trim()) ? 'toolFailed' : 'toolFinished', call: id })
    const parts = Array.isArray(p.output) ? p.output.map((c) => c?.text).filter((t) => typeof t === 'string') : null
    if (parts && parts.length > 2 && parts[0].startsWith('Script ')) {
      const results = parts.slice(1)
      results.forEach((text, index) => finish(text, index === results.length - 1 ? call : `${call}#${index}`))
      return
    }
    const output = typeof p.output === 'string' ? p.output : parts?.join('\n') ?? JSON.stringify(p.output ?? '')
    return finish(output, call)
  }

  // App-server style items (newer rollouts): the same calls, keyed by the item id.
  function item(it, completed) {
    if (!it?.id) return
    const type = String(it.type ?? '')
    if (type === 'agentMessage' || type === 'AgentMessage') { if (completed && it.text) add({ id: `${scope}:${it.id}:commentary`, kind: 'commentary', detail: clip(it.text) }); return }
    if (['userMessage', 'UserMessage', 'reasoning', 'Reasoning', 'plan', 'Plan', 'contextCompaction'].includes(type)) return
    const tools = { commandExecution: 'exec_command', fileChange: 'apply_patch', webSearch: 'web_search', imageView: 'view_image' }
    const tool = tools[type] ?? (type === 'mcpToolCall' ? `mcp__${it.server ?? 'mcp'}__${it.tool ?? 'tool'}` : type === 'collabAgentToolCall' || type === 'collabToolCall' ? 'spawn_agent' : type)
    const detail = type === 'commandExecution' ? KitchenActivity.withoutHeredocs(String(it.command ?? ''))
      : type === 'fileChange' ? (it.changes ?? []).map((c) => c.path).filter(Boolean).join('\n')
      : it.query ?? it.path ?? it.prompt ?? ''
    add({ id: 'start:' + it.id, kind: 'toolStarted', call: it.id, tool, detail: clip(detail) })
    if (completed) {
      const failed = ['failed', 'declined', 'Failed', 'Declined'].includes(it.status) || (it.exitCode != null && it.exitCode !== 0)
      add({ id: 'end:' + it.id, kind: failed ? 'toolFailed' : 'toolFinished', call: it.id })
    }
  }
}

// MARK: Finding rollouts

/** Rollout files in the date folders from `days` ago through today (newest first). */
export function recentRollouts(days = 2) {
  const root = path.join(codexHome(), 'sessions'), files = []
  for (let i = 0; i <= days; i++) {
    const d = new Date(Date.now() - i * 86400000)
    const folder = path.join(root, String(d.getFullYear()), String(d.getMonth() + 1).padStart(2, '0'), String(d.getDate()).padStart(2, '0'))
    try { for (const name of fs.readdirSync(folder)) if (/^rollout-.*\.jsonl$/.test(name)) files.push(path.join(folder, name)) } catch {}
  }
  return files.map((file) => ({ file, mtime: mtime(file) })).sort((a, b) => b.mtime - a.mtime).map((f) => f.file)
}
const mtime = (file) => { try { return fs.statSync(file).mtimeMs } catch { return 0 } }

/** The rollout for a Codex session id, searching recent days first, then everything. */
export function findRollout(id) {
  const match = (name) => name.endsWith(id + '.jsonl') && name.startsWith('rollout-')
  const recent = recentRollouts(3).find((f) => match(path.basename(f)))
  if (recent) return recent
  const walk = (folder, depth) => {
    let entries = []
    try { entries = fs.readdirSync(folder, { withFileTypes: true }) } catch { return null }
    for (const e of entries) {
      const full = path.join(folder, e.name)
      if (e.isDirectory() && depth < 4) { const found = walk(full, depth + 1); if (found) return found }
      else if (e.isFile() && match(e.name)) return full
    }
    return null
  }
  return walk(path.join(codexHome(), 'sessions'), 0)
}

/** A rollout's opening session_meta: { id, cwd, parent, subagent }. */
export function rolloutMeta(file) {
  let fd
  try {
    fd = fs.openSync(file, 'r')
    const buffer = Buffer.alloc(256 * 1024)
    const length = fs.readSync(fd, buffer, 0, buffer.length, 0)
    for (const line of buffer.toString('utf8', 0, length).split('\n').slice(0, 5)) {
      const r = parseJSON(line)
      if (r?.type !== 'session_meta') continue
      const p = r.payload ?? {}
      const sub = p.source?.subagent ?? p.source?.subAgent
      return { id: p.id ?? p.session_id, cwd: p.cwd ?? '', parent: sub?.thread_spawn?.parent_thread_id ?? p.parent_thread_id ?? null, subagent: !!sub || p.thread_source === 'subagent', review: p.thread_source === 'guardian_review' }
    }
  } catch {} finally { if (fd != null) fs.closeSync(fd) }
  return null
}
