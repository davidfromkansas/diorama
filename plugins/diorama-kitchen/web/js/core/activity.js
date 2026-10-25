// What an agent's tool calls mean in the kitchen: a port of DioramaCore's KitchenActivity,
// TurnWork and AgentActivityFeed, plus the app's LiveResources, PantryCarry items and sidebar
// phrases. Shared by the local server (which builds agents) and the page.

export const basename = (path) => {
  const trimmed = String(path).replace(/\/+$/, '')
  const index = trimmed.lastIndexOf('/')
  return index < 0 ? trimmed : trimmed.slice(index + 1)
}

const researchTools = new Set(['read', 'grep', 'glob', 'websearch', 'webfetch', 'web__run', 'web.search', 'toolsearch', 'view_image', 'imageview'])
const planningTools = new Set(['todowrite', 'taskcreate', 'taskupdate', 'enterplanmode', 'exitplanmode', 'update_plan', 'plan'])
const editingTools = new Set(['edit', 'write', 'multiedit', 'notebookedit', 'filechange', 'apply_patch'])
export const commandTools = new Set(['bash', 'commandexecution', 'shell', 'local_shell', 'exec_command', 'write_stdin'])
const readOnlyCommands = new Set(['cat', 'sed', 'head', 'tail', 'grep', 'egrep', 'rg', 'ag', 'ls', 'find', 'fd', 'tree', 'wc', 'nl',
  'file', 'stat', 'du', 'less', 'more', 'pwd', 'jq', 'echo', 'printf', 'which', 'awk', 'sort', 'uniq', 'cut', 'diff', 'realpath', 'basename', 'dirname'])
const readOnlyGit = new Set(['log', 'show', 'diff', 'status', 'blame', 'grep', 'ls-files', 'rev-parse', 'branch', 'remote', 'describe'])
const resourceTools = new Set(['skill', 'mcptoolcall', 'listmcpresources', 'readmcpresource', 'listmcpresourcestool', 'readmcpresourcetool',
  'listmcpresourcetemplates', 'listmcpresourcetemplatestool'])
const testRunner = /^(?:(?:npx|bunx|pnpx|uv\s+run|poetry\s+run|pipenv\s+run|bundle\s+exec|time|nice)\s+)*(?:(?:npm|pnpm|yarn|bun)\s+(?:run\s+)?test|vitest|jest|pytest|py\.test|python\d*(?:\.\d+)?\s+-m\s+(?:pytest|unittest|tox|nox)|tox|nox|go\s+test|cargo\s+test|swift\s+test|xcodebuild\s+(?:\S+\s+)*test|playwright\s+test|rspec|phpunit|ctest|mvn\s+test|gradle\w*\s+test|deno\s+test|dotnet\s+test|mix\s+test|rake\s+test|make\s+(?:\S+\s+)*test\S*|node\s+--test|node\s+\S*test\S*\.[mc]?[jt]s)\b/
const heredoc = /<<-?\s*['"]?([A-Za-z_][A-Za-z0-9_]*)['"]?/
const redirectTarget = /(?<![0-9&<>])>>?\s*([^\s;&|<>]+)/g
const scriptAssignment = /\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*['"]([^'"\n]+\.[A-Za-z0-9]+)['"]/g
const pathAssignment = /\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*Path\(\s*['"]([^'"\n]+)['"]\s*\)/g
const pathWrite = /\b([A-Za-z_][A-Za-z0-9_]*)\.write_(?:text|bytes)\(/g
const scriptWrite = /(?:open\(\s*(?:['"]([^'"\n]+)['"]|([A-Za-z_][A-Za-z0-9_]*))\s*,\s*['"][wax])|(?:Path\(\s*['"]([^'"\n]+)['"]\s*\)\.write_(?:text|bytes))|(?:writeFile(?:Sync)?\(\s*(?:['"]([^'"\n]+)['"]|([A-Za-z_][A-Za-z0-9_]*)))/g

export const KitchenActivity = {
  /** planning, researching, editing, commands, testing, checking, resources or other. */
  classify(tool, detail = '') {
    const name = String(tool || '').trim().toLowerCase()
    detail = String(detail || '')
    if (commandTools.has(name)) return this.classifyCommand(detail)
    if (this.isVisualCheck(name)) return 'checking'
    if (researchTools.has(name) && this.isSkillFile(detail)) return 'resources'
    if (researchTools.has(name) && ['.png', '.jpg', '.jpeg', '.webp'].some((ext) => detail.toLowerCase().endsWith(ext))) return 'checking'
    if (this.isResource(name)) return 'resources'
    if (researchTools.has(name)) return 'researching'
    if (planningTools.has(name)) return 'planning'
    if (editingTools.has(name)) return 'editing'
    return 'other'
  },
  isEditingTool(tool) { return editingTools.has(String(tool || '').toLowerCase()) },
  isEditing(tool, detail) {
    return this.isEditingTool(tool) || (commandTools.has(String(tool || '').toLowerCase()) && this.writtenFiles(detail).length > 0)
  },
  writtenFiles(command) {
    const full = this.shellScript(command)
    const script = this.withoutHeredocs(full)
    const files = []
    const add = (raw) => {
      const path = String(raw).replace(/^['"]+|['"]+$/g, '').trim()
      if (!path || path.startsWith('&') || path.startsWith('-') || path === '/dev/null' || path.startsWith('/dev/') || files.includes(path)) return
      const scratch = ['/tmp/', '/private/tmp/', '/var/folders/', '$TMPDIR'].some((p) => path.startsWith(p)) || ['.log', '.pid'].some((s) => path.endsWith(s))
      if (!scratch) files.push(path)
    }
    for (const match of script.matchAll(redirectTarget)) add(match[1])
    for (const segment of segments(script)) {
      const words = dropAssignments(segment.split(/\s+/).filter(Boolean))
      if (!words.length) continue
      const program = basename(words[0])
      const args = words.slice(1)
      switch (program) {
        case 'tee': case 'touch': args.filter((a) => !a.startsWith('-')).forEach(add); break
        case 'cp': case 'mv': case 'install': if (args.filter((a) => !a.startsWith('-')).length >= 2) add(args[args.length - 1]); break
        case 'sed': case 'gsed': if (args.some((a) => a.startsWith('-i')) && args.length) add(args[args.length - 1]); break
        case 'curl': case 'wget':
          args.forEach((arg, index) => {
            if (['-o', '--output', '-O', '--output-document'].includes(arg) && index + 1 < args.length && !(program === 'curl' && arg === '-O')) add(args[index + 1])
          })
          break
      }
    }
    for (const body of heredocBodies(full)) {
      const names = {}
      for (const match of [...body.matchAll(scriptAssignment), ...body.matchAll(pathAssignment)]) names[match[1]] = match[2]
      for (const match of body.matchAll(scriptWrite)) {
        for (let group = 1; group < match.length; group++) {
          if (match[group] === undefined) continue
          add([2, 5].includes(group) ? names[match[group]] ?? '' : match[group])
        }
      }
      for (const match of body.matchAll(pathWrite)) add(names[match[1]] ?? '')
    }
    return files
  },
  withoutHeredocs(script) {
    const kept = []
    let delimiter = null
    for (const line of String(script || '').split('\n')) {
      if (delimiter !== null) { if (line.trim() === delimiter) delimiter = null; continue }
      kept.push(line)
      const match = line.match(heredoc)
      if (match) delimiter = match[1]
    }
    return kept.join('\n')
  },
  isVisualCheck(tool) {
    const name = String(tool).toLowerCase()
    return name === 'computer_use' || ['browser', 'chrome', 'playwright', 'puppeteer', 'computer-use', 'computer_use', 'screenshot'].some((w) => name.includes(w))
  },
  isResource(tool) {
    const name = String(tool).toLowerCase()
    return name.startsWith('mcp__') || resourceTools.has(name.replaceAll('_', ''))
  },
  isSkillFile(text) { return String(text).includes('SKILL.md') },
  pluginSkillName(text) {
    const skill = this.skillName(text)
    const index = String(text).indexOf('/plugins/cache/')
    if (!skill || index < 0) return null
    const parts = text.slice(index + '/plugins/cache/'.length).split('/').filter(Boolean)
    return parts.length > 2 ? parts[1] + ':' + skill : null
  },
  skillName(text) {
    const index = String(text).indexOf('/SKILL.md')
    if (index < 0) return null
    const folder = text.slice(0, index).split(/[/ '"]/).filter(Boolean).pop()
    return folder ?? null
  },
  classifyCommand(command) {
    const script = this.withoutHeredocs(this.shellScript(command))
    if (isTestCommand(script)) return 'testing'
    if (this.writtenFiles(command).length) return 'editing'
    const words = commandWords(script)
    if (words.some((w) => ['cat', 'head', 'tail', 'sed', 'less', 'more', 'bat', 'nl'].includes(basename(w[0])) && w.some((x) => x.includes('SKILL.md')))) return 'resources'
    if (words.some((w) => ['curl', 'wget', 'http'].includes(basename(w[0])) && w.some((x) => x.includes('localhost') || x.includes('127.0.0.1') || x.includes('0.0.0.0')))) return 'checking'
    if (script.includes('--headless') || script.includes('--screenshot') || words.some((w) => basename(w[0]) === 'screencapture')) return 'checking'
    if (!words.length) return 'commands'
    if (/(?<![0-9&])>/.test(script)) return 'commands'
    const reads = words.every((w) => {
      const program = basename(w[0])
      if (w.length === 2 && ['--version', '-v', '-V', 'version'].includes(w[1])) return true
      if (program === 'sed' && w.some((x) => x.startsWith('-i'))) return false
      if (program === 'git') return w.length > 1 && readOnlyGit.has(w[1])
      return readOnlyCommands.has(program)
    })
    return reads ? 'researching' : 'commands'
  },
  shellScript(command) {
    let text = String(command || '').trim()
    if (text.startsWith('[')) {
      try { const parts = JSON.parse(text); if (Array.isArray(parts) && parts.every((p) => typeof p === 'string')) text = parts.join(' ') } catch {}
    }
    const wrapper = text.match(/^(?:\/\S*\/)?(?:ba|z)?sh\s+-l?c\s+/)
    if (wrapper) {
      text = text.slice(wrapper[0].length).trim()
      const first = text[0]
      if ((first === '"' || first === "'") && text.length >= 2 && text[text.length - 1] === first) text = text.slice(1, -1)
    }
    return text
  },
  /** The kinds of work a command does, step by step, in the order it runs them. */
  stations(command) {
    const order = []
    for (const segment of segments(this.withoutHeredocs(this.shellScript(command)))) {
      if (!segment.trim()) continue
      const kind = this.classifyCommand(segment)
      if (!['testing', 'commands', 'checking', 'editing'].includes(kind) || order[order.length - 1] === kind) continue
      order.push(kind)
    }
    return order
  },
}

function dropAssignments(words) {
  let index = 0
  while (index < words.length && words[index].includes('=') && !words[index].startsWith('-')) index++
  return words.slice(index)
}

export function commandWords(script) {
  return segments(script).map((segment) => {
    const words = dropAssignments(segment.split(/\s+/).filter(Boolean))
    while (words.length && ['do', 'then', 'else', 'elif', 'if', 'while', 'until', '!', '{', '('].includes(words[0])) words.shift()
    if (!words.length || ['for', 'done', 'fi', 'esac', 'case', '}', ')', '[', '[[', 'test', 'true', 'false', 'cd'].includes(words[0])) return null
    return words
  }).filter(Boolean)
}

function isTestCommand(script) {
  return commandWords(script).some((words) => {
    const head = [basename(words[0]), ...words.slice(1, 8)].join(' ')
    return testRunner.test(head)
  })
}

export function segments(script) {
  const result = []
  let current = '', quote = null
  const chars = [...String(script)]
  for (let i = 0; i < chars.length; i++) {
    const c = chars[i]
    if (quote) { current += c; if (c === quote) quote = null; continue }
    if (c === '"' || c === "'") { quote = c; current += c; continue }
    if (c === ';' || c === '|' || c === '&' || c === '\n') {
      if ((c === '|' || c === '&') && chars[i + 1] === c) i++
      result.push(current); current = ''; continue
    }
    current += c
  }
  result.push(current)
  return result.map((s) => s.trim()).filter(Boolean)
}

function heredocBodies(script) {
  const bodies = []
  let current = [], delimiter = null
  for (const line of String(script).split('\n')) {
    if (delimiter !== null) {
      if (line.trim() === delimiter) { bodies.push(current.join('\n')); current = []; delimiter = null } else current.push(line)
      continue
    }
    const match = line.match(heredoc)
    if (match) delimiter = match[1]
  }
  return bodies
}

/** What an agent has done in its current turn: files edited, commands, tests and resources. */
export class TurnWork {
  constructor() {
    this.files = []; this.commands = 0; this.failedCommands = 0; this.tests = []; this.resources = []
    this.calls = new Map()
  }
  static session(detail) {
    const field = String(detail).split(' ').find((f) => f.startsWith('session='))
    return field ? field.slice(8) : null
  }
  started(tool, detail, call) {
    const lower = String(tool).toLowerCase()
    if (lower === 'write_stdin') { if (call) this.calls.set(call, { kind: 'poll' }); return }
    const written = commandTools.has(lower) ? KitchenActivity.writtenFiles(detail) : []
    for (const path of written) this.addFile(path)
    if (written.length && KitchenActivity.classify(tool, detail) !== 'testing') {
      if (call) this.calls.set(call, { kind: 'command' })
      this.commands += 1
      return
    }
    if (KitchenActivity.isEditingTool(tool)) {
      for (const path of String(detail).split('\n').map((p) => p.trim()).filter(Boolean)) this.addFile(path)
      return
    }
    switch (KitchenActivity.classify(tool, detail)) {
      case 'testing':
        this.tests.push({ command: KitchenActivity.shellScript(detail), outcome: 'running' })
        if (call) this.calls.set(call, { kind: 'test', index: this.tests.length - 1 })
        break
      case 'commands':
        this.commands += 1
        if (call) this.calls.set(call, { kind: 'command' })
        break
      case 'resources': {
        const skill = lower === 'skill' ? String(detail).trim() : ''
        this.resources.push(KitchenActivity.pluginSkillName(detail) ?? KitchenActivity.skillName(detail) ?? (String(detail).startsWith('skill://') ? detail : skill || tool))
        break
      }
    }
  }
  finished(call, failed) {
    if (!call || !this.calls.has(call)) return
    const kind = this.calls.get(call)
    this.calls.delete(call)
    if (kind.kind === 'command' && failed) this.failedCommands += 1
    if (kind.kind === 'test') this.tests[kind.index].outcome = failed ? 'failed' : 'passed'
  }
  addFile(path) {
    if (this.files.some((f) => f === path || f.endsWith('/' + path))) return
    const index = this.files.findIndex((f) => path.endsWith('/' + f))
    if (index >= 0) { this.files[index] = path; return }
    this.files.push(path)
  }
  settle() { for (const test of this.tests) if (test.outcome === 'running') test.outcome = 'unknown' }
  /** The current turn's work from an activity stream (oldest first). */
  static from(events) {
    let start = 0
    events.forEach((e, i) => { if (e.kind === 'started') start = i + 1 })
    const work = new TurnWork()
    for (const event of events.slice(start)) {
      if (event.kind === 'toolStarted') work.started(event.tool ?? '', event.detail ?? '', event.callID)
      else if (event.kind === 'toolFinished' || event.kind === 'toolFailed') work.finished(event.callID, event.kind === 'toolFailed')
      else if (['finished', 'interrupted', 'failed'].includes(event.kind)) work.settle()
    }
    return work
  }
  toJSON() {
    return { files: this.files, commands: this.commands, failedCommands: this.failedCommands, tests: this.tests, resources: this.resources }
  }
}

const plumbing = new Set(['js', 'js_reset', 'wait', 'sleep', 'exec'])
const feedLimit = 200

/** A short activity feed (oldest first): turn markers, merged reads, edits, commands and tests. */
export function feedEntries(events) {
  const result = []
  const open = new Map()
  const append = (entry) => {
    result.push(entry)
    if (result.length > feedLimit) {
      const drop = result.length - feedLimit
      result.splice(0, drop)
      for (const [key, value] of open) { if (value >= drop) open.set(key, value - drop); else open.delete(key) }
    }
  }
  const marker = (kind, id, time) => {
    const title = { started: 'Started a turn', finished: 'Turn finished', failed: 'Turn failed' }[kind] ?? 'Turn interrupted'
    if (result[result.length - 1]?.kind === kind) return
    append({ id, kind, title, detail: '', outcome: kind === 'failed' ? 'failed' : null, time })
    if (kind !== 'started') open.clear()
  }
  const name = (path) => basename(String(path).trim())
  const list = (items) => items.length <= 2 ? items.join(', ') : items.slice(0, 2).join(', ') + ` +${items.length - 2}`
  const toolName = (tool) => tool.startsWith('mcp__') ? tool.slice(5).replaceAll('__', ' ').replaceAll('_', ' ') : (tool || 'a tool')
  const isPath = (word) => {
    word = word.replace(/^['"`;]+|['"`;]+$/g, '')
    if (word.startsWith('-') || word.includes('://') || /[*?$|<>(){}[\]=,]/.test(word)) return false
    const last = basename(word)
    return (word.includes('/') && last !== '') || (last.includes('.') && last[0] !== '.' && last[last.length - 1] !== '.')
  }
  const brief = (line) => line.split(' ').map((word) => {
    if (!word.includes('/') || !isPath(word)) return word
    const trimmed = word.replace(/^['"`;]+|['"`;]+$/g, '')
    const short = basename(trimmed)
    return word.replace(trimmed, short || trimmed)
  }).join(' ')
  const clip60 = (line) => line.length > 60 ? line.slice(0, 59) + '…' : line
  const firstLine = (script) => script.split('\n').find(() => true) ?? script
  const ownLine = (tool, detail) => {
    const lower = tool.toLowerCase()
    if (['view_image', 'imageview'].includes(lower)) return 'Viewed ' + (detail ? name(detail) : 'an image')
    if (!commandTools.has(lower)) return null
    const script = KitchenActivity.shellScript(detail)
    const words = commandWords(script)[0] ?? script.split(' ')
    const first = words[0]
    if (!first) return null
    if (['ls', 'find', 'fd', 'tree', 'pwd', 'cat', 'head', 'tail', 'less', 'more', 'nl'].includes(first) || (first === 'rg' && words.includes('--files'))) return null
    if (words.slice(1).some(isPath)) return null
    return 'Ran ' + clip60(brief(firstLine(script)))
  }
  const subject = (tool, detail) => {
    const lower = tool.toLowerCase()
    if (['read', 'view_image', 'imageview'].includes(lower) && detail) return name(detail)
    if (commandTools.has(lower)) {
      const script = KitchenActivity.shellScript(detail)
      const words = commandWords(script)[0] ?? script.split(' ')
      const first = words[0]
      if (first && (['ls', 'find', 'fd', 'tree', 'pwd'].includes(first) || (first === 'rg' && words.includes('--files')))) return 'project files'
      if (first && ['cat', 'head', 'tail', 'less', 'more', 'nl'].includes(first)) {
        const file = [...words].reverse().find((w) => !w.startsWith('-') && w !== first)
        if (file) return name(file)
      }
      const file = [...words.slice(1)].reverse().find(isPath)
      if (file) return name(file)
      const line = brief(firstLine(script))
      return line.length > 40 ? line.slice(0, 39) + '…' : line
    }
    if (lower.includes('search') || lower.includes('fetch')) return detail ? detail.slice(0, 40) : 'the web'
    return detail ? name(detail) : toolName(tool)
  }
  const resourceName = (tool, detail) => {
    if (tool.toLowerCase() === 'skill') return detail || 'a skill'
    const skill = KitchenActivity.skillName(detail)
    if (skill) return 'the ' + skill + ' skill'
    return toolName(tool)
  }
  const started = (id, tool, detail, call, time) => {
    const lower = tool.toLowerCase()
    if (lower === 'write_stdin' || plumbing.has(lower)) return
    const written = commandTools.has(lower) ? KitchenActivity.writtenFiles(detail) : []
    const alsoTests = written.length > 0 && KitchenActivity.classify(tool, detail) === 'testing'
    if (KitchenActivity.isEditingTool(tool) || written.length) {
      const files = (written.length ? written : detail.split('\n')).map(name).filter(Boolean)
      const last = result[result.length - 1]
      if (last?.kind === 'editing' && last.detail === files.join('\n')) return
      append({ id, kind: 'editing', title: 'Edited ' + list(files.length ? files : ['a file']), detail: files.join('\n'), outcome: 'done', time })
      if (!alsoTests) return
      const script = KitchenActivity.withoutHeredocs(KitchenActivity.shellScript(detail))
      const line = script.split('\n').filter(Boolean).pop() ?? script
      append({ id: id + ':test', kind: 'test', title: 'Tested · ' + (line.length > 60 ? line.slice(0, 59) + '…' : line), detail: script, outcome: 'running', time })
      if (call) open.set(call, result.length - 1)
      return
    }
    if (['view_image', 'imageview'].includes(lower)) {
      append({ id, kind: 'research', title: 'Viewed ' + (detail ? name(detail) : 'an image'), detail: '', outcome: 'done', time })
      return
    }
    const activity = KitchenActivity.classify(tool, detail)
    switch (activity) {
      case 'researching': {
        const own = ownLine(tool, detail)
        if (own) { append({ id, kind: 'research', title: own, detail: '', outcome: 'done', time }); return }
        const item = subject(tool, detail)
        const last = result[result.length - 1]
        if (last?.kind === 'research' && last.title.startsWith('Looked at ')) {
          const items = last.detail.split('\n').filter(Boolean)
          if (!items.includes(item)) items.push(item)
          last.detail = items.join('\n'); last.title = 'Looked at ' + list(items)
          return
        }
        append({ id, kind: 'research', title: 'Looked at ' + item, detail: item, outcome: 'done', time })
        break
      }
      case 'checking': {
        const what = detail ? detail.slice(0, 60) : toolName(tool)
        const last = result[result.length - 1]
        if (last?.kind === 'test' && last.detail === what) return
        append({ id, kind: 'test', title: 'Checked · ' + what, detail: what, outcome: null, time })
        break
      }
      case 'resources': {
        const item = resourceName(tool, detail)
        const last = result[result.length - 1]
        if (last?.kind === 'resource' && last.detail === item) return
        append({ id, kind: 'resource', title: 'Fetched ' + item, detail: item, outcome: 'done', time })
        break
      }
      case 'planning':
        if (result[result.length - 1]?.kind === 'planning') return
        append({ id, kind: 'planning', title: 'Updated the plan', detail: '', outcome: 'done', time })
        break
      case 'testing': case 'commands': {
        const script = KitchenActivity.shellScript(detail)
        const line = brief(firstLine(script))
        append({ id, kind: activity === 'testing' ? 'test' : 'command', title: (activity === 'testing' ? 'Tested · ' : 'Ran ') + clip60(line), detail: script, outcome: 'running', time })
        if (call) open.set(call, result.length - 1)
        break
      }
      default: {
        const label = toolName(tool)
        const last = result[result.length - 1]
        if (last?.kind === 'tool' && last.title === 'Used ' + label) return
        append({ id, kind: 'tool', title: 'Used ' + label, detail, outcome: 'done', time })
      }
    }
  }
  const finished = (call, failed, time) => {
    if (!call || !open.has(call)) return
    const index = open.get(call)
    open.delete(call)
    const entry = result[index]
    if (!entry) return
    entry.outcome = failed ? 'failed' : 'done'
    if (time && entry.time) entry.duration = Math.max(0, (time - entry.time) / 1000)
  }
  for (const event of events) {
    switch (event.kind) {
      case 'started': marker('started', event.id, event.time); break
      case 'finished': marker('finished', event.id, event.time); break
      case 'interrupted': marker('interrupted', event.id, event.time); break
      case 'failed': marker('failed', event.id, event.time); break
      case 'toolStarted': started(event.id, event.tool ?? '', event.detail ?? '', event.callID, event.time); break
      case 'toolFinished': case 'toolFailed': finished(event.callID, event.kind === 'toolFailed', event.time); break
    }
  }
  return result
}

/** The resource a tool call uses: an MCP server, a plugin's server or a skill. */
export function liveResource(tool, detail) {
  tool = String(tool || ''); detail = String(detail || '')
  const skill = KitchenActivity.skillName(detail)
  if (skill) return { id: 'skill:' + skill, name: skill, kind: 'skill' }
  if (detail.startsWith('skill://')) {
    const parts = detail.slice(8).split('/').filter(Boolean)
    const last = parts[parts.length - 1]
    if (!last) return null
    const plugin = parts.length > 1 && parts[0].startsWith('plugin') ? parts[0] : null
    return { id: 'skill:' + last, name: last, kind: 'skill', plugin }
  }
  if (tool.toLowerCase() === 'skill') {
    const name = detail.trim().split(/\s+/)[0] ?? ''
    return name ? { id: 'skill:' + name, name, kind: 'skill' } : null
  }
  if (isBrowsing(tool)) return null
  if (!tool.startsWith('mcp__')) return null
  const parts = tool.slice(5).split('__')
  let server = parts[0]
  if (!server) return null
  if (parts.length > 1 && isBrowsing(parts[1])) return null
  if (server.length >= 32 && (server.match(/-/g) ?? []).length >= 4) return null
  let plugin = null
  if (server.startsWith('plugin_')) {
    const rest = server.slice(7)
    const cut = rest.indexOf('_')
    plugin = cut < 0 ? rest : rest.slice(0, cut)
    server = cut < 0 ? rest : rest.slice(cut + 1)
  }
  if (server.startsWith('claude_ai_')) server = server.slice(10)
  return { id: 'server:' + server.toLowerCase(), name: titleCase(server), kind: 'server', plugin }
}
const isBrowsing = (tool) => ['listmcpresources', 'listmcpresourcetemplates', 'readmcpresource', 'listmcpresourcestool', 'readmcpresourcetool', 'listmcpresourcetemplatestool']
  .includes(String(tool).toLowerCase().replaceAll('_', ''))
export const titleCase = (raw) => String(raw).replaceAll('_', ' ').replaceAll('-', ' ').split(' ').filter(Boolean).map((w) => w[0].toUpperCase() + w.slice(1)).join(' ')

function pluginFolder(text) {
  const index = String(text).indexOf('/plugins/cache/')
  if (index < 0) return null
  const parts = text.slice(index + 15).split('/').filter(Boolean)
  return parts.length > 2 ? parts[1] : null
}

/** What a chef fetches from the pantry for a tool call (a jar, a crate, an appliance). */
export function pantryItemFor(tool, detail) {
  if (KitchenActivity.isSkillFile(detail)) {
    const plugin = pluginFolder(detail)
    if (plugin) return { kind: 'plugin', name: titleCase(plugin) }
  }
  const resource = liveResource(tool, detail)
  if (!resource) return null
  if (resource.kind === 'skill') {
    if (resource.plugin) return { kind: 'plugin', name: resource.plugin.startsWith('plugin_') ? resource.name : resource.plugin }
    const colon = resource.name.indexOf(':')
    if (colon > 0) return { kind: 'plugin', name: titleCase(resource.name.slice(0, colon)) }
    return { kind: 'skill', name: resource.name }
  }
  if (resource.plugin) return { kind: 'plugin', name: titleCase(resource.plugin) }
  return { kind: 'connector', name: resource.name }
}

/** The pantry item an agent is fetching: its current call's, else the turn's latest resource. */
export function pantryItem(agent) {
  const item = pantryItemFor(agent.latestTool, agent.latestToolDetail)
  if (item) return item
  for (const entry of [...(agent.turnWork?.resources ?? [])].reverse()) {
    if (!entry) continue
    const found = entry.startsWith('skill://') ? pantryItemFor('read_mcp_resource', entry)
      : entry.startsWith('mcp__') || isBrowsing(entry) ? pantryItemFor(entry, '')
      : entry.toLowerCase() === 'skill' ? null : pantryItemFor('Skill', entry)
    if (found) return found
  }
  return null
}

/** What a chef leaving prep carries on its plate: the plan step it's starting, else what it's doing. */
export function planItem(agent) {
  const steps = agent.plan?.checklist ?? []
  const active = steps.find((s) => ['in_progress', 'inprogress', 'in progress', 'running'].includes(String(s.status).toLowerCase()))
    ?? steps.find((s) => String(s.status).toLowerCase() === 'pending')
  const step = active?.title?.trim()
  if (step) return { kind: 'plan', name: step }
  const doing = phrase(agent).trim()
  if (doing && doing !== 'Working…') return { kind: 'plan', name: doing }
  const task = compactTitle(agent.task).trim()
  return { kind: 'plan', name: task || 'Prep' }
}

/** A few words for what an agent is doing now ("Editing Foo.swift…"). */
export function phrase(agent) {
  const tool = agent.latestTool ?? '', detail = agent.latestToolDetail ?? ''
  if (!tool) return 'Working…'
  const firstLine = detail.split('\n')[0] ?? ''
  const file = !firstLine.includes(' ') && (firstLine.startsWith('/') || firstLine.includes('.')) ? basename(firstLine) : ''
  const script = KitchenActivity.withoutHeredocs(KitchenActivity.shellScript(detail)).toLowerCase()
  switch (KitchenActivity.classify(tool, detail)) {
    case 'planning': return 'Planning next steps…'
    case 'editing': {
      const written = commandTools.has(tool.toLowerCase()) ? KitchenActivity.writtenFiles(detail)[0] : null
      const name = written ? basename(written) : file || null
      return name ? `Editing ${name}…` : 'Editing files…'
    }
    case 'researching':
      if (tool.toLowerCase().includes('web')) return 'Researching online…'
      if (['grep', 'rg ', 'find ', 'search', 'glob'].some((w) => script.includes(w) || tool.toLowerCase().includes(w))) return 'Searching the code…'
      return file ? `Reading ${file}…` : 'Reading the project…'
    case 'testing': return 'Running tests…'
    case 'checking': return 'Checking the result…'
    case 'resources': {
      const name = KitchenActivity.skillName(detail) ?? (tool.startsWith('mcp__') ? tool.split('_').filter(Boolean)[1] ?? null : null)
      return name ? `Using ${name}…` : 'Fetching a skill…'
    }
    case 'commands':
      if (script.includes('install')) return 'Installing packages…'
      if (script.includes('build')) return 'Building…'
      if (script.includes('lint')) return 'Linting…'
      if (script.includes('server') || script.includes(' dev')) return 'Starting a server…'
      if (tool.toLowerCase() === 'write_stdin') return 'Waiting for output…'
      return 'Running a command…'
    default:
      if (['sleep', 'wait'].includes(tool.toLowerCase())) return 'Waiting…'
      return 'Working…'
  }
}

/** "claude-opus-5-5" → "Claude Opus 5.5". */
export function modelName(model) {
  let id = String(model ?? '').trim()
  if (!id || id === '<synthetic>') return 'Claude'
  if (id.startsWith('claude/')) id = id.slice(7)
  id = id.replace(/\[.*\]$/, '')
  const parts = id.split('-').filter(Boolean)
  if (parts.length && /^\d{8}$/.test(parts[parts.length - 1])) parts.pop()
  if (!parts.length) return 'Claude'
  const words = []
  for (let i = 0; i < parts.length; i++) {
    const part = parts[i]
    if (/^\d+$/.test(part) && i + 1 < parts.length && /^\d{1,2}$/.test(parts[i + 1])) { words.push(part + '.' + parts[i + 1]); i++; continue }
    words.push(part.toLowerCase() === 'gpt' ? 'GPT' : part[0].toUpperCase() + part.slice(1))
  }
  if (words[0] !== 'Claude') words.unshift('Claude')
  return words.join(' ')
}

export function fullTitle(text) {
  const clean = String(text ?? '').split('<diorama_')[0]
  return clean.replace(/[*_`#>]/g, '').split(/\s+/).filter(Boolean).join(' ')
}
export function compactTitle(text) {
  const words = fullTitle(text).split(' ').filter(Boolean)
  return words.slice(0, 6).join(' ') + (words.length > 6 ? '…' : '')
}
