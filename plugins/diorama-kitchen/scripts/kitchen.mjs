#!/usr/bin/env node
// `/kitchen`: starts the kitchen's local server if it isn't running, points it at this session
// and opens the page in your browser. Prints the address either way.
//
//   node kitchen.mjs open <session-id>    (the command passes the session it was run in)
//   node kitchen.mjs stop

import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'
import http from 'node:http'
import { spawn } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const configDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude')
const portFile = path.join(configDir, 'diorama-kitchen', 'server.json')
const [command = 'open', session] = process.argv.slice(2)

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

if (!session || session.includes('$')) {
  console.log('Could not tell which session this is. Update Claude Code and run /kitchen again.')
  process.exit(0)
}
let state = await running()
// A newer copy of the plugin replaces an older server.
const version = JSON.parse(fs.readFileSync(path.join(root, '.claude-plugin', 'plugin.json'), 'utf8')).version
if (state && state.version !== version) { try { process.kill(state.pid) } catch {} ; await sleep(300); state = null }
state ??= await start()
if (!state) { console.log('The kitchen server could not start. Try: node "' + path.join(root, 'server', 'server.mjs') + '"'); process.exit(0) }
const watched = await request(state.port, 'POST', '/api/watch', { session, transcript: findTranscript(session) })
const url = watched?.body?.url ?? `http://127.0.0.1:${state.port}/?session=${encodeURIComponent(session)}`
const opened = openBrowser(url)
console.log(`Kitchen ${opened ? 'opened' : 'ready'}: ${url}`)
