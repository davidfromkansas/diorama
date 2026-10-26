#!/usr/bin/env node
// Passes a Claude Code hook event to the kitchen's server when one is running; otherwise does
// nothing. Always quiet and always succeeds: the kitchen only watches, it never changes a session.

import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'
import http from 'node:http'

const stateDir = process.env.DIORAMA_KITCHEN_HOME || path.join(os.homedir(), '.diorama-kitchen')
let port
try { port = JSON.parse(fs.readFileSync(path.join(stateDir, 'server.json'), 'utf8')).port } catch { process.exit(0) }

let input = ''
process.stdin.setEncoding('utf8')
process.stdin.on('data', (chunk) => { input += chunk })
process.stdin.on('end', () => {
  const request = http.request({ host: '127.0.0.1', port, path: '/api/hook', method: 'POST', headers: { 'content-type': 'application/json', host: `127.0.0.1:${port}` }, timeout: 400 },
    (res) => { res.resume(); res.on('end', () => process.exit(0)) })
  request.on('error', () => process.exit(0))
  request.on('timeout', () => { request.destroy(); process.exit(0) })
  request.end(input || '{}')
})
setTimeout(() => process.exit(0), 1500).unref()
