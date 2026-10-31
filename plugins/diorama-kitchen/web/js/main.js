// The page: builds the kitchen, follows the session's agents from the local server (or a scripted
// demo with ?demo), and draws the floating cards around it: the session and its chefs, the
// selected chef's progress, sound and camera controls.

import * as THREE from 'three'
import { buildKitchen } from './scene/room.js'
import { ChefAssets } from './scene/assets.js'
import { Particles } from './scene/particles.js'
import { Kitchen, seconds, sceneClock } from './scene/kitchen.js'
import { tagContent, Palette } from './ui/tags.js'
import { phrase, fullTitle, modelName } from './core/activity.js'
import { audio } from './audio.js'
import { demoAgents } from './demo.js'
import { vocabulary as V, isOffice, switchScene } from './scene/theme.js'
import { homeView } from './scene/camera.js'

const params = new URLSearchParams(location.search)
const session = params.get('session') ?? ''
const stage = document.getElementById('stage')
const overlay = document.getElementById('overlay')
const loading = document.getElementById('loading')
document.title = V.Place
document.getElementById('loading-text').textContent = `Setting up the ${V.place}…`
for (const who of document.querySelectorAll('#keys .who')) who.textContent = V.person
document.querySelector('link[rel=icon]').href = `data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>${V.icon}</text></svg>`

const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' })
renderer.setPixelRatio(Math.min(2, devicePixelRatio))
renderer.shadowMap.enabled = !params.has('noshadow'); renderer.shadowMap.type = THREE.PCFSoftShadowMap
renderer.outputColorSpace = THREE.SRGBColorSpace
stage.appendChild(renderer.domElement)
const scene = new THREE.Scene()
const camera = new THREE.PerspectiveCamera(homeView.fov, 1, 0.1, 400)
const clock = { value: 0 }

const [built, assets] = await Promise.all([buildKitchen(scene, clock), ChefAssets.load()])
await assets.preloadAll()
const particles = new Particles(scene)
const kitchen = new Kitchen({ renderer, scene, camera, built, assets, particles, overlay, canvas: renderer.domElement })
kitchen.scope = session || 'demo'

function resize() {
  renderer.setSize(stage.clientWidth, stage.clientHeight)
  kitchen.fit()
}
addEventListener('resize', resize); resize()

let last = performance.now()
let tick = () => {}
const step = (delta) => {
  tick()
  clock.value = seconds()
  kitchen.frame(seconds(), delta)
  particles.update(delta)
}
const loop = (time) => {
  const delta = Math.min(0.1, Math.max(0, (time - last) / 1000)); last = time
  step(delta)
  renderer.render(scene, camera)
}
renderer.setAnimationLoop(loop)
loading.remove()
window.__ready = true
window.__kitchen = kitchen
window.__stop = () => renderer.setAnimationLoop(null)
/** Tests: runs the scene `span` seconds ahead without drawing, `dt` at a time, then draws once. */
window.__simulate = (span, dt = 1 / 30) => {
  for (let t = 0; t < span; t += dt) { sceneClock.skip += dt; step(dt) }
  renderer.render(scene, camera)
}
window.__start = () => { last = performance.now(); renderer.setAnimationLoop(loop) }
window.__debug = { scene, renderer, camera, kitchen, THREE }

// MARK: The cards

const el = (tag, className, parent, text) => {
  const e = document.createElement(tag)
  if (className) e.className = className
  if (text != null) e.textContent = text
  parent?.appendChild(e)
  return e
}
const hud = document.getElementById('hud')
const header = el('div', 'hud-header', hud)
el('div', 'brand', header, V.icon)
const heading = el('div', 'hud-heading', header)
const title = el('div', 'hud-title', heading, V.Place)
const subtitle = el('div', 'hud-subtitle', heading, '')
const live = el('div', 'live', header)
const toggle = el('button', 'roster-toggle', header)
const roster = el('div', 'roster hidden', hud)
const summary = el('div', 'summary card', document.body)
let expanded = (() => { try { return localStorage.getItem('kitchenRoster') === 'open' } catch { return false } })()
const showRoster = () => {
  roster.classList.toggle('hidden', !expanded)
  toggle.textContent = `${agents.length} ${agents.length === 1 ? V.person : V.people} ${expanded ? '▴' : '▾'}`
  toggle.title = expanded ? `Hide the ${V.people} list` : `Show the ${V.people} list`
}
toggle.onclick = () => { expanded = !expanded; try { localStorage.setItem('kitchenRoster', expanded ? 'open' : 'closed') } catch {}; showRoster() }

const controls = document.getElementById('controls')
const resetButton = el('button', 'control hidden', controls, 'Reset view')
resetButton.title = `Go back to the whole ${V.place} (R)`
resetButton.onclick = () => kitchen.resetCamera()
kitchen.onCameraMoved = (away) => resetButton.classList.toggle('hidden', !away)
const sceneButton = el('button', 'control', controls, isOffice ? '🍳' : '🏢')
sceneButton.title = isOffice ? 'Switch to the kitchen' : 'Switch to the office'
sceneButton.onclick = () => switchScene(isOffice ? 'kitchen' : 'office')
const soundButton = el('button', 'control', controls)
const showSound = () => { soundButton.textContent = audio.enabled ? '🔊' : '🔈'; soundButton.title = audio.enabled ? `Mute ${V.place} sounds` : `Play ${V.place} sounds` }
soundButton.onclick = () => { audio.unlock(); audio.setEnabled(!audio.enabled); showSound() }
showSound()
const helpButton = el('button', 'control', controls, '?')
helpButton.title = `Scroll to zoom · Arrow keys to move · Q/W rotate · R reset · A hide tags · Click a ${V.person} to follow it`
const hint = el('div', 'hint', document.body, `Click anywhere to turn on ${V.place} sounds`)
addEventListener('pointerdown', () => { audio.unlock(); hint.remove() }, { once: true })
addEventListener('keydown', () => { audio.unlock(); hint.remove() }, { once: true })
helpButton.onclick = () => {
  const keys = document.getElementById('keys')
  keys.classList.toggle('hidden')
}

const panel = document.getElementById('panel')
let opened = null
kitchen.onOpen = (id) => { opened = id; drawPanel() }
kitchen.onSelect = (id) => { if (!id) opened = null; else if (opened) opened = id; drawPanel(); drawRoster() }
const live1 = document.getElementById('announcer')
kitchen.onAnnounce = (text) => { live1.textContent = text }

let agents = [], sessionInfo = {}, connection = 'connecting'

function statusDot(agent) {
  const content = tagContent(agent)
  const colors = { starting: Palette.run, working: Palette.run, thinking: Palette.idle, waiting: Palette.wait, approval: Palette.ask, failed: Palette.fail, stopped: Palette.idle, done: Palette.star, idle: Palette.idle }
  return { color: colors[content.phase], content }
}

function drawHUD() {
  title.textContent = fullTitle(sessionInfo.title) || V.Place
  title.title = fullTitle(sessionInfo.task ?? sessionInfo.title ?? '')
  subtitle.textContent = [sessionInfo.project, sessionInfo.model ? modelName(sessionInfo.model) : null].filter(Boolean).join(' · ')
  live.className = 'live ' + connection
  live.title = { live: 'Live: following this session', connecting: 'Connecting…', ended: 'This session has ended', offline: 'Lost the connection: retrying…', demo: 'Demo' }[connection] ?? ''
  const counts = { working: 0, you: 0, done: 0 }
  for (const a of agents) {
    const phase = tagContent(a).phase
    if (['starting', 'working', 'thinking'].includes(phase)) counts.working++
    else if (['waiting', 'approval', 'failed'].includes(phase)) counts.you++
    else if (phase === 'done') counts.done++
  }
  summary.replaceChildren()
  const item = (count, label, color) => {
    const part = el('span', 'summary-item' + (count ? '' : ' zero'), summary)
    const dot = el('span', 'dot', part); dot.style.background = color
    el('b', '', part, String(count)); el('span', '', part, label)
  }
  item(counts.working, 'working', Palette.run); item(counts.you, 'need you', Palette.wait); item(counts.done, 'done', Palette.star)
  showRoster()
  drawRoster()
}

function drawRoster() {
  roster.replaceChildren()
  const order = [...agents].sort((a, b) => (b.isMain ? 1 : 0) - (a.isMain ? 1 : 0) || (b.startedAt ?? 0) - (a.startedAt ?? 0))
  for (const agent of order.slice(0, 12)) {
    const { color, content } = statusDot(agent)
    const row = el('button', 'roster-row' + (kitchen.selectedID === agent.id ? ' selected' : ''), roster)
    const dot = el('span', 'dot', row); dot.style.background = content.stale ? 'transparent' : color; dot.style.boxShadow = `inset 0 0 0 1.5px ${color}`
    const text = el('span', 'roster-text', row)
    el('span', 'roster-name', text, agent.name + (agent.isMain ? '' : ` · ${agent.agentType ?? 'subagent'}`))
    el('span', 'roster-line', text, content.line || content.text)
    row.onclick = () => { audio.unlock(); if (kitchen.selectedID === agent.id) { opened = agent.id; drawPanel() } else kitchen.setSelection(agent.id) }
  }
  if (agents.length > 12) el('div', 'roster-more', roster, `+${agents.length - 12} more`)
}

function drawPanel() {
  const agent = agents.find((a) => a.id === opened)
  panel.classList.toggle('hidden', !agent)
  if (!agent) return
  panel.replaceChildren()
  const { color, content } = statusDot(agent)
  const top = el('div', 'panel-top', panel)
  const dot = el('span', 'dot', top); dot.style.background = color
  const names = el('div', 'panel-names', top)
  el('div', 'panel-name', names, agent.name)
  el('div', 'panel-model', names, [modelName(agent.model), agent.isMain ? 'Main agent' : agent.agentType ?? 'Subagent'].filter(Boolean).join(' · '))
  const close = el('button', 'panel-close', top, '×'); close.title = 'Close'
  close.onclick = () => { opened = null; drawPanel() }
  el('div', 'panel-task', panel, content.fullText)
  el('div', 'panel-line', panel, content.line || phrase(agent)).style.color = color
  const plan = agent.plan?.checklist ?? []
  if (plan.length) {
    el('div', 'panel-section', panel, agent.plan.tasksPreviousTurn ? 'Plan (last turn)' : 'Plan')
    const list = el('ul', 'panel-plan', panel)
    for (const step of plan) {
      const s = String(step.status).toLowerCase()
      const mark = s === 'completed' ? '✓' : ['in_progress', 'inprogress', 'running'].includes(s) ? '›' : '○'
      const item = el('li', 'plan-' + (mark === '✓' ? 'done' : mark === '›' ? 'now' : 'todo'), list)
      el('span', 'plan-mark', item, mark); el('span', '', item, step.title)
    }
  }
  const work = agent.turnWork ?? {}
  if (work.files?.length) {
    el('div', 'panel-section', panel, `Files this turn (${work.files.length})`)
    const files = el('div', 'panel-files', panel)
    for (const file of work.files.slice(-8)) el('div', 'panel-file', files, file.split('/').pop()).title = file
  }
  const feed = (agent.feed ?? []).filter((e) => !['started', 'finished', 'interrupted'].includes(e.kind)).slice(-14).reverse()
  if (feed.length) {
    el('div', 'panel-section', panel, 'Recent steps')
    const list = el('div', 'panel-feed', panel)
    for (const entry of feed) {
      const row = el('div', 'feed-row ' + (entry.outcome ?? ''), list)
      el('span', 'feed-mark', row, entry.outcome === 'failed' ? '✗' : entry.outcome === 'running' ? '›' : '✓')
      el('span', 'feed-title', row, entry.title).title = entry.detail ?? entry.title
    }
  }
}

function show(next) {
  agents = next
  kitchen.apply(agents)
  drawHUD()
  if (opened) drawPanel()
}

// MARK: Following the session

if (params.has('demo') || !session) {
  connection = 'demo'
  sessionInfo = { title: V.demo, project: 'No session: showing a demo' }
  tick = demoAgents(show, params.get('demo'), seconds)
} else {
  const connect = () => {
    const source = new EventSource(`/api/stream?session=${encodeURIComponent(session)}`)
    source.onopen = () => { connection = 'live'; drawHUD() }
    source.onmessage = (event) => {
      const data = JSON.parse(event.data)
      sessionInfo = data.session ?? sessionInfo
      if (data.session?.ended) connection = 'ended'
      else connection = 'live'
      show(data.agents ?? [])
    }
    source.onerror = () => { connection = 'offline'; drawHUD() }
  }
  connect()
  // Tags count up between updates.
  setInterval(drawHUD, 5000)
}
drawHUD()
