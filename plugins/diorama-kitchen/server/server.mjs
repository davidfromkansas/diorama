#!/usr/bin/env node
// The kitchen's local server: serves the page and its models on 127.0.0.1, follows the sessions
// you open with /kitchen or `diorama-kitchen` (Claude Code transcripts and hook events, or Codex
// rollouts, with their subagents') and streams each session's agents to its page. It stops by itself once no page has
// been open for a while.

import http from 'node:http'
import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'
import { fileURLToPath } from 'node:url'
import { SessionModel } from './model.mjs'
import { codexRecord, findRollout, recentRollouts, rolloutMeta } from './codex.mjs'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const configDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude')
const stateDir = process.env.DIORAMA_KITCHEN_HOME || path.join(os.homedir(), '.diorama-kitchen')
const portFile = path.join(stateDir, 'server.json')
const preferredPort = Number(process.env.KITCHEN_PORT) || 47811
const idleLimit = (Number(process.env.KITCHEN_IDLE_MINUTES) || 10) * 60 * 1000
const version = JSON.parse(fs.readFileSync(path.join(root, '.claude-plugin', 'plugin.json'), 'utf8')).version
const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.json': 'application/json', '.glb': 'model/gltf-binary', '.jpg': 'image/jpeg', '.png': 'image/png', '.mp3': 'audio/mpeg', '.obj': 'text/plain', '.mtl': 'text/plain', '.svg': 'image/svg+xml' }

// MARK: Sessions

/** Every session seen (by its hooks or a /kitchen), with the transcripts being followed. */
const sessions = new Map()
const maxSessions = 24

function session(id, provider = 'claude') {
  if (!sessions.has(id)) {
    if (sessions.size >= maxSessions) {
      const oldest = [...sessions.values()].filter((s) => !s.clients.size).sort((a, b) => a.touched - b.touched)[0]
      if (oldest) { clearInterval(oldest.timer); sessions.delete(oldest.model.sessionId) }
    }
    sessions.set(id, { provider, model: new SessionModel(id, provider), clients: new Set(), files: new Map(), transcript: null, timer: null, touched: Date.now(), sent: -1, pending: null,
      children: new Map(), checked: new Set(), scanned: 0 })
  }
  const entry = sessions.get(id)
  entry.touched = Date.now()
  return entry
}

/** Finds a session's transcript under the projects folder. */
function findTranscript(id) {
  const projects = path.join(configDir, 'projects')
  try {
    for (const folder of fs.readdirSync(projects)) {
      const file = path.join(projects, folder, id + '.jsonl')
      if (fs.existsSync(file)) return file
    }
  } catch {}
  return null
}

const locate = (entry) => entry.provider === 'codex' ? findRollout(entry.model.sessionId) : findTranscript(entry.model.sessionId)

function watch(entry, transcript) {
  entry.transcript = transcript && fs.existsSync(transcript) ? transcript : entry.transcript ?? locate(entry)
  if (entry.timer) return
  poll(entry, true)
  entry.timer = setInterval(() => poll(entry, false), 400)
}

/** Reads what each transcript gained since the last look: the main one, then any subagent's. */
function poll(entry, first) {
  if (!entry.transcript) entry.transcript = locate(entry)
  if (!entry.transcript) return
  if (entry.provider === 'codex') return pollCodex(entry, first)
  const files = [[entry.transcript, null]]
  const folder = path.join(entry.transcript.replace(/\.jsonl$/, ''), 'subagents')
  for (const file of listAgents(folder)) files.push([file, path.basename(file, '.jsonl').replace(/^agent-/, '')])
  // History first in start order, so subagents take names in the order they started.
  if (first) files.sort((a, b) => (a[1] == null ? -1 : b[1] == null ? 1 : birth(a[0]) - birth(b[0])))
  for (const [file, agent] of files) {
    if (agent && !entry.files.has(file)) {
      try { entry.model.agentMeta(agent, JSON.parse(fs.readFileSync(file.replace(/\.jsonl$/, '.meta.json'), 'utf8'))) } catch {}
    }
    tail(entry, file, agent)
  }
  push(entry)
}
/** A Codex session's rollout, then its subagents' (rollouts whose session_meta names a parent we follow). */
function pollCodex(entry, first) {
  if (first || Date.now() - entry.scanned > 2000) {
    entry.scanned = Date.now()
    const ids = new Set([entry.model.sessionId, ...entry.children.values()])
    let found = true
    // Repeat so a subagent's own subagents (listed before it) are found in the same pass.
    while (found) {
      found = false
      for (const file of recentRollouts(1)) {
        if (file === entry.transcript || entry.children.has(file) || entry.checked.has(file)) continue
        const meta = rolloutMeta(file)
        if (!meta) continue
        if (meta.parent && ids.has(meta.parent) && !meta.review) { entry.children.set(file, meta.id); ids.add(meta.id); found = true }
        else if (meta.id) entry.checked.add(file)
      }
    }
  }
  const files = [[entry.transcript, null], ...[...entry.children].sort((a, b) => birth(a[0]) - birth(b[0]))]
  for (const [file, agent] of files) tail(entry, file, agent)
  push(entry)
}
function birth(file) { try { const s = fs.statSync(file); return s.birthtimeMs || s.ctimeMs } catch { return 0 } }
function listAgents(folder, depth = 0) {
  let result = []
  try {
    for (const item of fs.readdirSync(folder, { withFileTypes: true })) {
      const full = path.join(folder, item.name)
      if (item.isDirectory() && depth < 3) result = result.concat(listAgents(full, depth + 1))
      else if (item.isFile() && /^agent-.*\.jsonl$/.test(item.name)) result.push(full)
    }
  } catch {}
  return result
}

function tail(entry, file, agent) {
  let stat
  try { stat = fs.statSync(file) } catch { return }
  let cursor = entry.files.get(file)
  if (!cursor || stat.size < cursor.offset || stat.ino !== cursor.ino) { cursor = { offset: 0, ino: stat.ino, rest: '' }; entry.files.set(file, cursor) }
  if (stat.size === cursor.offset) return
  const fd = fs.openSync(file, 'r')
  try {
    const length = Math.min(stat.size - cursor.offset, 64 * 1024 * 1024)
    const buffer = Buffer.alloc(length)
    fs.readSync(fd, buffer, 0, length, cursor.offset)
    cursor.offset += length
    const text = cursor.rest + buffer.toString('utf8')
    const lines = text.split('\n')
    cursor.rest = lines.pop() ?? ''
    for (const line of lines) {
      if (!line.trim()) continue
      let record
      try { record = JSON.parse(line) } catch { continue }
      if (entry.provider === 'codex') codexRecord(entry.model, record, agent)
      else entry.model.record(record, agent ?? record.agentId ?? null)
    }
  } finally { fs.closeSync(fd) }
}

// MARK: Streaming

function send(entry, client) {
  const data = JSON.stringify(entry.model.snapshot())
  client.write(`data: ${data}\n\n`)
}
/** Sends a session's agents to its pages when they changed (at most every 150 ms). */
function push(entry, force = false) {
  if (!entry.clients.size) return
  if (!force && entry.model.version === entry.sent) return
  if (entry.pending) return
  entry.pending = setTimeout(() => {
    entry.pending = null
    entry.sent = entry.model.version
    for (const client of entry.clients) send(entry, client)
  }, 150)
}
// Freshness moves on with the clock (a finished subagent heads for the break room): resend now and then.
setInterval(() => { for (const entry of sessions.values()) push(entry, true) }, 5000)

// MARK: HTTP

let lastClient = Date.now()
const clientCount = () => [...sessions.values()].reduce((n, s) => n + s.clients.size, 0)

function body(req, limit = 4 * 1024 * 1024) {
  return new Promise((resolve, reject) => {
    let size = 0; const chunks = []
    req.on('data', (c) => { size += c.length; if (size > limit) { reject(new Error('too large')); req.destroy() } else chunks.push(c) })
    req.on('end', () => { try { resolve(JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}')) } catch (e) { reject(e) } })
    req.on('error', reject)
  })
}
function json(res, status, value) { res.writeHead(status, { 'content-type': 'application/json' }); res.end(JSON.stringify(value)) }

function serveFile(res, file) {
  fs.stat(file, (error, stat) => {
    if (error || !stat.isFile()) { res.writeHead(404); res.end('Not found'); return }
    res.writeHead(200, { 'content-type': types[path.extname(file)] ?? 'application/octet-stream', 'content-length': stat.size, 'cache-control': 'no-cache' })
    fs.createReadStream(file).pipe(res)
  })
}

const server = http.createServer(async (req, res) => {
  // Only this machine, by name: a page elsewhere can't reach in through a renamed host.
  const host = (req.headers.host ?? '').replace(/:\d+$/, '')
  if (!['127.0.0.1', 'localhost', '[::1]'].includes(host)) { res.writeHead(403); res.end(); return }
  const url = new URL(req.url, 'http://localhost')
  const route = url.pathname
  try {
    if (route === '/api/health') return json(res, 200, { ok: true, version, pid: process.pid })
    if (route === '/api/hook' && req.method === 'POST') {
      const input = await body(req)
      if (input.session_id) { const entry = session(String(input.session_id)); entry.model.hook(input); if (input.transcript_path && !entry.transcript) entry.transcript = input.transcript_path; push(entry) }
      return json(res, 200, { ok: true })
    }
    if (route === '/api/watch' && req.method === 'POST') {
      const input = await body(req)
      if (!input.session) return json(res, 400, { error: 'session required' })
      const provider = input.provider === 'codex' ? 'codex' : 'claude'
      const entry = session(String(input.session), provider)
      watch(entry, input.transcript)
      const query = `?session=${encodeURIComponent(input.session)}` + (provider === 'codex' ? '&provider=codex' : '')
      return json(res, 200, { ok: true, url: `http://127.0.0.1:${server.address().port}/${query}`, transcript: entry.transcript })
    }
    if (route === '/api/state') {
      const id = url.searchParams.get('session')
      if (!id || !sessions.has(id)) return json(res, 404, { error: 'unknown session' })
      return json(res, 200, sessions.get(id).model.snapshot())
    }
    if (route === '/api/stream') {
      const id = url.searchParams.get('session')
      if (!id) { res.writeHead(400); res.end(); return }
      const entry = session(id, url.searchParams.get('provider') === 'codex' ? 'codex' : 'claude')
      watch(entry, null)
      res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-cache', connection: 'keep-alive' })
      res.write('retry: 1500\n\n')
      entry.clients.add(res)
      send(entry, res)
      const ping = setInterval(() => res.write(': ping\n\n'), 20000)
      req.on('close', () => { clearInterval(ping); entry.clients.delete(res); lastClient = Date.now() })
      return
    }
    if (route.startsWith('/assets/')) {
      const file = path.normalize(path.join(root, decodeURIComponent(route)))
      if (!file.startsWith(path.join(root, 'assets') + path.sep)) { res.writeHead(403); res.end(); return }
      return serveFile(res, file)
    }
    const file = path.normalize(path.join(root, 'web', route === '/' ? 'index.html' : decodeURIComponent(route)))
    if (!file.startsWith(path.join(root, 'web') + path.sep)) { res.writeHead(403); res.end(); return }
    return serveFile(res, file)
  } catch (error) {
    json(res, 500, { error: String(error?.message ?? error) })
  }
})

function writePortFile() {
  fs.mkdirSync(stateDir, { recursive: true })
  fs.writeFileSync(portFile, JSON.stringify({ port: server.address().port, pid: process.pid, version }))
}
function removePortFile() {
  try { if (JSON.parse(fs.readFileSync(portFile, 'utf8')).pid === process.pid) fs.unlinkSync(portFile) } catch {}
}
function stop() { removePortFile(); process.exit(0) }
process.on('SIGINT', stop); process.on('SIGTERM', stop); process.on('exit', removePortFile)

// Nobody watching for a while: shut down (the next /kitchen starts it again).
setInterval(() => { if (!clientCount() && Date.now() - lastClient > idleLimit) stop() }, 30000)

server.on('error', (error) => {
  if (error.code === 'EADDRINUSE' && server.listenPort !== 0) { server.listenPort = 0; server.listen(0, '127.0.0.1') }
  else { console.error(error); process.exit(1) }
})
server.on('listening', () => { writePortFile(); console.log(`Kitchen at http://127.0.0.1:${server.address().port}`) })
server.listenPort = preferredPort
server.listen(preferredPort, '127.0.0.1')
