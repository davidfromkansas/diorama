#!/usr/bin/env node
// Opens the kitchen for a Claude Code, Codex or Hermes session: starts the local server if it
// isn't running, points it at the session and opens the page in your browser. Prints the address.
//
//   diorama-kitchen                      the newest Claude Code or Codex session in this folder
//   diorama-kitchen --claude | --codex   the newest session of that tool in this folder
//   diorama-kitchen --hermes             the Hermes session that last started a turn
//   diorama-kitchen stop                 stops the kitchen's server
//   kitchen.mjs open <session-id>        a Claude Code session (what /kitchen runs)
//   kitchen.mjs open --codex <id>        a Codex session (or --hermes for a Hermes one)

import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'
import http from 'node:http'
import { spawn } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { recentRollouts, rolloutMeta, findRollout } from '../server/codex.mjs'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const configDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude')
const stateDir = process.env.DIORAMA_KITCHEN_HOME || path.join(os.homedir(), '.diorama-kitchen')
const portFile = path.join(stateDir, 'server.json')
const args = process.argv.slice(2)
const flag = (name) => { const i = args.indexOf(name); if (i >= 0) args.splice(i, 1); return i >= 0 }
const codex = flag('--codex'), claude = flag('--claude'), hermes = flag('--hermes')
const [command = 'latest', given] = args

function request(port, method, route, body) {
  return new Promise((resolve) => {
    const req = http.request({ host: '127.0.0.1', port, path: route, method, timeout: 1500, headers: { 'content-type': 'application/json' } }, (res) => {
      let text = ''
      res.setEncoding('utf8'); res.on('data', (c) => { text += c })
      res.on('end', () => { try { resolve({ status: res.statusCode, body: JSON.parse(text) }) } catch { resolve(null) } })
    })
    req.on('error', () => resolve(null)); req.on('timeout', () => { req.destroy(); resolve(null) })
    req.end(body ? JSON.stringify(body) : undefined)
  })
}
const readPort = () => { try { return JSON.parse(fs.readFileSync(portFile, 'utf8')) } catch { return null } }
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

async function running() {
  const state = readPort()
  if (!state) return null
  const health = await request(state.port, 'GET', '/api/health')
  return health?.body?.ok ? { ...state, version: health.body.version } : null
}

async function start() {
  const child = spawn(process.execPath, [path.join(root, 'server', 'server.mjs')], { detached: true, stdio: 'ignore', env: process.env })
  child.unref()
  for (let i = 0; i < 50; i++) {
    await sleep(100)
    const state = await running()
    if (state) return state
  }
  return null
}

const mtime = (file) => { try { return fs.statSync(file).mtimeMs } catch { return 0 } }

function findTranscript(id) {
  try {
    const projects = path.join(configDir, 'projects')
    for (const folder of fs.readdirSync(projects)) {
      const file = path.join(projects, folder, id + '.jsonl')
      if (fs.existsSync(file)) return file
    }
  } catch {}
  return null
}

/** The newest Claude Code session started in `cwd` (Claude Code names its folder after the path). */
function latestClaude(cwd) {
  const folder = path.join(configDir, 'projects', cwd.replace(/[^a-zA-Z0-9]/g, '-'))
  let best = null
  try {
    for (const name of fs.readdirSync(folder)) {
      if (!name.endsWith('.jsonl')) continue
      const file = path.join(folder, name), time = mtime(file)
      if (!best || time > best.time) best = { provider: 'claude', id: name.slice(0, -6), file, time }
    }
  } catch {}
  return best
}
/** The newest Codex session (not a subagent's) whose folder is `cwd`. */
function latestCodex(cwd) {
  for (const file of recentRollouts(14)) {
    const meta = rolloutMeta(file)
    if (meta?.id && !meta.subagent && !meta.review && path.resolve(meta.cwd || '/') === cwd) return { provider: 'codex', id: meta.id, file, time: mtime(file) }
  }
  return null
}
/** The Hermes session that last started a turn (the Hermes plugin notes it; Hermes doesn't say which folder). */
function latestHermes() {
  try {
    const { session, time } = JSON.parse(fs.readFileSync(path.join(stateDir, 'hermes-latest.json'), 'utf8'))
    return session ? { provider: 'hermes', id: String(session), file: null, time: Number(time) || 0 } : null
  } catch { return null }
}

function openBrowser(url) {
  if (process.env.KITCHEN_NO_OPEN) return false
  const [cmd, args] = process.platform === 'darwin' ? ['open', [url]] : process.platform === 'win32' ? ['cmd', ['/c', 'start', '', url]] : ['xdg-open', [url]]
  try {
    const child = spawn(cmd, args, { detached: true, stdio: 'ignore' })
    child.on('error', () => {})
    child.unref()
    return true
  } catch { return false }
}

if (command === 'stop') {
  const state = await running()
  if (state) { try { process.kill(state.pid) } catch {} ; console.log('Kitchen server stopped.') } else console.log('The kitchen server is not running.')
  process.exit(0)
}
if (['help', '-h', '--help'].includes(command)) {
  console.log('Usage: diorama-kitchen [--claude | --codex]   open the newest session in this folder\n       diorama-kitchen --hermes               open the latest Hermes session\n       diorama-kitchen stop                   stop the kitchen server')
  process.exit(0)
}

let target
if (command === 'open') {
  if (!given || given.includes('$')) {
    console.log('Could not tell which session this is. Update Claude Code and run /kitchen again, or run diorama-kitchen in your project folder.')
    process.exit(0)
  }
  target = codex ? { provider: 'codex', id: given, file: findRollout(given) } : hermes ? { provider: 'hermes', id: given, file: null }
    : { provider: 'claude', id: given, file: findTranscript(given) }
} else {
  const cwd = path.resolve(process.cwd())
  const found = hermes ? [] : [!codex && latestClaude(cwd), !claude && latestCodex(cwd)].filter(Boolean).sort((a, b) => b.time - a.time)
  // Hermes sessions have no folder to match: used when asked for, or when this folder has no other session.
  target = found[0] ?? (hermes || (!codex && !claude) ? latestHermes() : null)
  if (!target) {
    const tools = hermes ? 'Hermes' : codex ? 'Codex' : claude ? 'Claude Code' : 'Claude Code, Codex or Hermes'
    console.log(hermes ? 'No Hermes session yet. Send a message in Hermes (with the Diorama Kitchen plugin on), then run diorama-kitchen --hermes again.'
      : `No ${tools} session found for ${cwd}. Start one in this folder, then run diorama-kitchen here again.`)
    process.exit(1)
  }
}

let state = await running()
// A newer copy of the plugin replaces an older server.
const version = JSON.parse(fs.readFileSync(path.join(root, '.claude-plugin', 'plugin.json'), 'utf8')).version
if (state && state.version !== version) { try { process.kill(state.pid) } catch {} ; await sleep(300); state = null }
state ??= await start()
if (!state) { console.log('The kitchen server could not start. Try: node "' + path.join(root, 'server', 'server.mjs') + '"'); process.exit(1) }
const watched = await request(state.port, 'POST', '/api/watch', { session: target.id, provider: target.provider, transcript: target.file })
const url = watched?.body?.url ?? `http://127.0.0.1:${state.port}/?session=${encodeURIComponent(target.id)}` + (target.provider === 'claude' ? '' : `&provider=${target.provider}`)
const opened = openBrowser(url)
const label = command === 'open' ? '' : ` (${{ codex: 'Codex', hermes: 'Hermes' }[target.provider] ?? 'Claude Code'} session ${target.id.slice(0, 8)})`
console.log(`Kitchen ${opened ? 'opened' : 'ready'}${label}: ${url}`)
