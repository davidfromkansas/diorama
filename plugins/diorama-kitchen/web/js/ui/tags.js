// A chef's tag (the app's ChefTagContent, ChefTagView and ChefProgressView): its name on a folder
// tab, one terminal line of what it is doing now, a segmented progress bar and, selected, a short
// log of recent steps. Laid out by hand like the app's, so the kitchen can place tags before showing them.

import { route } from '../scene/layout.js'
import { phrase, fullTitle } from '../core/activity.js'

/** Codex's tool names, as a person would say them. */
const approvalNames = { exec_command: 'command', shell: 'command', local_shell: 'command', apply_patch: 'edit' }

export const Palette = {
  run: 'rgb(120,191,255)', ok: 'rgb(97,212,148)', wait: 'rgb(245,176,64)', ask: 'rgb(181,140,255)', fail: 'rgb(255,122,107)',
  idle: 'rgb(153,161,166)', star: 'rgb(242,201,77)', ink: 'rgba(18,20,23,0.9)', strip: 'rgb(20,23,26)', paper: 'rgba(255,255,255,0.93)',
  text: 'rgb(237,232,224)', dim: 'rgb(179,184,191)', empty: 'rgba(20,18,15,0.6)',
}

const phases = {
  starting: { symbol: '›', color: Palette.run, spoken: 'starting', priority: 2 },
  working: { symbol: '›', color: Palette.run, spoken: 'working', priority: 2 },
  thinking: { symbol: '…', color: Palette.idle, spoken: 'thinking', priority: 2 },
  waiting: { symbol: '?', color: Palette.wait, spoken: 'waiting for you', priority: 0 },
  approval: { symbol: '!', color: Palette.ask, spoken: 'needs approval', priority: 0 },
  failed: { symbol: '✗', color: Palette.fail, spoken: 'failed', priority: 0 },
  stopped: { symbol: '■', color: Palette.idle, spoken: 'stopped', priority: 4 },
  done: { symbol: '★', color: Palette.star, spoken: 'done', priority: 3 },
  idle: { symbol: '–', color: Palette.idle, spoken: 'idle', priority: 4 },
}
export const needsYou = (phase) => ['waiting', 'approval', 'failed'].includes(phase)
export const running = (phase) => phase === 'starting' || phase === 'working'
export const phasePriority = (phase) => phases[phase]?.priority ?? 5

/** Seconds without a tool call or a note before a working agent reads as thinking. */
export const thinkingAfter = 20
export function silent(agent, now) {
  if (!isWorking(agent)) return false
  const last = Math.max(agent.lastToolAt ?? 0, agent.lastCommentaryAt ?? 0)
  return last > 0 && (now - last) / 1000 >= thinkingAfter
}
export const fresh = (agent) => agent.freshness === 'live' || agent.freshness === 'recentlyObserved'
export const isWorking = (agent) => agent.status === 'working' && fresh(agent)

export function tagPhase(agent, area, now) {
  switch (agent.status) {
    case 'working': {
      const feed = agent.feed ?? []
      if (feed[feed.length - 1]?.kind === 'started') return 'starting'
      return silent(agent, now) ? 'thinking' : 'working'
    }
    case 'waiting': return agent.attentionReason === 'approval' ? 'approval' : 'waiting'
    case 'failed': return 'failed'
    case 'stopped': return 'stopped'
    case 'done': return area === 'serving' ? 'done' : 'idle'
    default: return 'idle'
  }
}

/** What the tag shows for an agent now. */
export function tagContent(agent, now = Date.now()) {
  const area = route(agent).area
  const task = fullTitle(agent.task)
  const steps = (agent.feed ?? []).filter((e) => !['started', 'finished', 'interrupted'].includes(e.kind))
  const phase = tagPhase(agent, area, now)
  let line
  switch (phase) {
    case 'starting': line = 'starting…'; break
    case 'working': line = steps[steps.length - 1]?.title ?? phrase(agent); break
    case 'thinking': {
      const last = Math.max(agent.lastToolAt ?? 0, agent.lastCommentaryAt ?? 0)
      line = `thinking · ${last ? Math.max(0, Math.floor((now - last) / 1000)) : 0}s`
      break
    }
    case 'waiting': line = 'waiting for you'; break
    case 'approval': line = agent.latestTool ? `allow ${approvalNames[agent.latestTool] ?? agent.latestTool}?` : 'needs approval'; break
    case 'failed': line = [...steps].reverse().find((s) => s.outcome === 'failed')?.title ?? 'turn failed'; break
    case 'stopped': line = 'stopped'; break
    case 'done': {
      const files = agent.turnWork?.files?.length
      line = files ? `done · ${files} file${files === 1 ? '' : 's'}` : 'done'
      break
    }
    default: line = ''
  }
  line = String(line).replaceAll('\n', ' ')
  let progress = null
  if (agent.planProgress?.kind === 'steps' && phase !== 'idle') progress = { kind: 'steps', done: agent.planProgress.done, total: agent.planProgress.total }
  else if (['starting', 'working', 'thinking'].includes(phase)) progress = { kind: 'sweep' }
  const footer = []
  const start = [...(agent.feed ?? [])].reverse().find((e) => e.kind === 'started')?.time
  if (start && (running(phase) || phase === 'thinking')) {
    const seconds = Math.max(0, Math.floor((now - start) / 1000))
    footer.push(seconds >= 60 ? `${Math.floor(seconds / 60)}m ${seconds % 60}s` : `${seconds}s`)
  }
  const shown = phase === 'working' ? steps.slice(0, -1) : steps
  const short = agent.title || ''
  return {
    name: agent.name, model: agent.modelLabel ?? '', phase, line, progress,
    text: short || agent.name, fullText: task || agent.name,
    stale: !fresh(agent), resting: area === 'break',
    log: shown.slice(-3).map((s) => (s.outcome === 'failed' ? '✗ ' : '✓ ') + s.title),
    footer: footer.join(' · '),
  }
}

export function spoken(content) {
  const parts = [`${content.name}, ${phases[content.phase].spoken}`]
  if (content.line) parts.push(content.line)
  if (content.progress?.kind === 'steps') parts.push(`${content.progress.done} of ${content.progress.total} steps done`)
  if (content.fullText) parts.push(content.fullText)
  return parts.join('. ')
}

// MARK: Measuring

const sans = '-apple-system, BlinkMacSystemFont, "Segoe UI", "Helvetica Neue", Arial, sans-serif'
const mono = 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace'
export const fonts = {
  name: `600 10px ${sans}`, model: `500 9.5px ${sans}`, task: `600 9.5px ${mono}`, line: `400 9.5px ${mono}`, glyph: `700 9.5px ${mono}`, card: `400 9px ${mono}`,
}
const context = document.createElement('canvas').getContext('2d')
const widths = new Map()
export function measure(text, font) {
  const key = font + '\u0000' + text
  if (!widths.has(key)) { context.font = font; widths.set(key, context.measureText(text).width); if (widths.size > 4000) widths.clear() }
  return widths.get(key)
}
const textWidth = (text, font) => Math.ceil(measure(text, font)) + 4

const S = {
  maxText: 140, selectedText: 250, scrollSpeed: 35, edgePause: 1.5, tabHeight: 15, lineHeight: 13, stripPadding: 3, margin: 3, barGap: 3,
  cardLine: 12, cardWidth: 260, barHeight: 6, radius: 6, tickerGap: '   ·   ',
}

const el = (tag, className, parent) => { const e = document.createElement(tag); if (className) e.className = className; parent?.appendChild(e); return e }

// MARK: The tag

export class ChefTag {
  constructor(parent) {
    this.root = el('div', 'tag', parent)
    this.root.setAttribute('role', 'button')
    this.body = el('div', 'tag-body', this.root)
    this.glow = el('div', 'tag-glow', this.body)
    this.ring = el('div', 'tag-ring', this.body)
    this.pill = el('div', 'tag-pill', this.body)
    this.nameBox = el('div', 'tag-name', this.pill)
    this.dot = el('div', 'tag-dot', this.nameBox)
    this.nameLabel = el('div', 'tag-label', this.nameBox)
    this.modelLabel = el('div', 'tag-model', this.nameBox)
    this.termBox = el('div', 'tag-term', this.pill)
    this.joint = el('div', 'tag-joint', this.pill)
    this.taskLabel = el('div', 'tag-task', this.termBox)
    this.glyphBox = el('div', 'tag-glyph', this.termBox)
    this.clip = el('div', 'tag-clip', this.termBox)
    this.lineLabel = el('div', 'tag-line', this.clip)
    this.caret = el('div', 'tag-caret', this.termBox)
    this.bar = new ProgressBar(this.body)
    this.card = el('div', 'tag-card', this.body)
    this.cardLines = []; this.cardRows = []
    this.content = null; this.mode = 'full'; this.selected = false; this.hovered = false; this.reducedMotion = false
    this.hidden = true; this.root.style.display = 'none'
    this.frame = { x: 0, y: 0, w: 0, h: 0 }
    this.lastReaction = 0
  }

  shape(mode = this.mode, selected = this.selected, hovered = this.hovered) {
    mode = this.effective(mode, selected, hovered)
    const c = this.content
    const task = mode !== 'nameOnly' && !!c?.text
    const line = mode === 'full' && !!c?.line
    const s = { mode, selected, task, line, term: task || line, card: selected && mode === 'full' && !!c?.log.length, bar: mode !== 'nameOnly' && !!c?.progress }
    s.strip = S.stripPadding * 2 + S.lineHeight * ((task ? 1 : 0) + (line ? 1 : 0)) + 1
    return s
  }
  effective(mode, selected, hovered) {
    if (!this.content?.text && !this.content?.line) return 'nameOnly'
    return this.content?.phase === 'idle' && !selected && !hovered ? 'compact' : mode
  }
  get modelWidth() { return this.content?.model ? 5 + Math.ceil(measure(this.content.model, fonts.model)) : 0 }
  get nameWidth() { return 6 + 6 + 4 + Math.ceil(measure(this.content?.name ?? '', fonts.name)) + this.modelWidth + 7 }
  get lineWidth() { return textWidth(this.content?.line ?? '', fonts.line) }
  textRoom(shape) { return shape.selected ? S.selectedText : S.maxText }
  termWidth(shape) {
    if (!shape.term) return 0
    let line = 0
    if (shape.line) {
      line = 8 + 4 + Math.min(this.textRoom(shape), this.lineWidth)
      if (running(this.content.phase)) line += 2 + 5
    }
    const task = shape.task ? Math.min(this.textRoom(shape) + 50, textWidth(this.content.text, fonts.task)) : 0
    return 5 + Math.max(line, task) + 6
  }
  cardSize(shape) {
    if (!shape.card) return { w: 0, h: 0 }
    const widest = Math.max(0, ...this.cardLines.map((l) => textWidth(l, fonts.card)))
    return { w: Math.min(S.cardWidth, widest) + 14, h: this.cardLines.length * S.cardLine + 10 }
  }
  pillWidth(shape) { return Math.max(this.nameWidth, this.termWidth(shape), this.cardSize(shape).w) }
  /** The whole tag's size, margins included, as it is or as it would be in another mode. */
  size(mode, selected, hovered) {
    const shape = this.shape(mode, selected, hovered), card = this.cardSize(shape)
    let height = S.tabHeight + (shape.term ? shape.strip : 0) + (shape.bar ? S.barGap + S.barHeight : 0)
    if (card.h > 0) height += card.h + 3
    return { w: this.pillWidth(shape) + S.margin * 2, h: height + S.margin * 2 }
  }

  update(content, reducedMotion) {
    const before = this.content
    if (before && JSON.stringify(before) === JSON.stringify(content) && reducedMotion === this.reducedMotion) return
    const lineChanged = content.line !== before?.line || reducedMotion !== this.reducedMotion
    const restyle = content.phase !== before?.phase || reducedMotion !== this.reducedMotion || JSON.stringify(content.progress) !== JSON.stringify(before?.progress)
    this.content = content; this.reducedMotion = reducedMotion
    this.nameLabel.textContent = content.name
    this.modelLabel.textContent = content.model
    this.taskLabel.textContent = content.text
    this.lineLabel.textContent = content.line
    this.glyphBox.textContent = phases[content.phase].symbol
    const cardChanged = this.setCardLines([...content.log].reverse().concat(content.footer ? [content.footer] : []))
    const described = spoken(content)
    this.root.setAttribute('aria-label', described); this.root.title = content.fullText ? `${content.name} · ${content.fullText}` : content.name
    const p = content.phase
    this.bar.update(content.progress, p === 'idle' || p === 'thinking' || p === 'stopped' ? Palette.ok : running(p) ? Palette.ok : phases[p].color, running(p) && !reducedMotion)
    this.layout()
    if (lineChanged || cardChanged) this.restartMarquee()
    if (restyle) this.restartMotion()
  }

  present(mode, selected, hovered) {
    mode = this.effective(mode, selected, hovered)
    if (mode === this.mode && selected === this.selected && hovered === this.hovered) return
    this.mode = mode; this.selected = selected; this.hovered = hovered
    this.layout(); this.restartMotion(); this.restartMarquee()
  }
  get modeAlpha() { return this.mode === 'compact' && !needsYou(this.content?.phase) && this.content?.phase !== 'idle' ? 0.5 : 1 }
  get tagAlpha() { return this.content?.stale && !this.selected ? Math.min(0.6, this.modeAlpha) : this.modeAlpha }

  setHidden(hidden) {
    if (hidden === this.hidden) return
    this.hidden = hidden
    this.root.style.display = hidden ? 'none' : ''
    if (!hidden) { this.restartMotion(); this.restartMarquee() }
  }
  place(frame) {
    this.frame = frame
    this.root.style.transform = `translate(${Math.round(frame.x)}px, ${Math.round(frame.y)}px)`
    this.root.style.width = frame.w + 'px'; this.root.style.height = frame.h + 'px'
  }

  layout() {
    const c = this.content
    if (!c) return
    const shape = this.shape(), m = S.margin, width = this.pillWidth(shape), r = S.radius
    const box = (e, x, y, w, h) => { e.style.left = x + 'px'; e.style.top = y + 'px'; e.style.width = Math.max(0, w) + 'px'; e.style.height = Math.max(0, h) + 'px' }
    const show = (e, on) => { e.style.display = on ? '' : 'none' }
    this.root.style.opacity = this.tagAlpha
    const color = phases[c.phase].color, attention = needsYou(c.phase)
    const accent = attention ? color : Palette.run
    const pillHeight = S.tabHeight + (shape.term ? shape.strip : 0)
    box(this.pill, m, m, width, pillHeight)
    this.nameBox.style.background = this.selected ? accent : Palette.paper
    this.nameLabel.style.color = this.selected ? 'rgba(15,15,15,1)' : 'rgb(26,26,26)'
    box(this.nameBox, 0, 0, this.nameWidth, S.tabHeight + (shape.term ? r : 0))
    show(this.joint, shape.term); box(this.joint, 0, S.tabHeight, r, r)
    box(this.dot, 6, (S.tabHeight - 6) / 2, 6, 6)
    this.dot.style.background = c.stale ? 'transparent' : color
    this.dot.style.boxShadow = c.stale ? `inset 0 0 0 1.5px ${color}` : 'none'
    const nameText = Math.ceil(measure(c.name, fonts.name)) + 4
    box(this.nameLabel, 16, 1, nameText, S.tabHeight - 2)
    show(this.modelLabel, !!c.model); box(this.modelLabel, 16 + nameText + 1, 1.5, this.modelWidth, S.tabHeight - 2)
    show(this.termBox, shape.term); box(this.termBox, 0, S.tabHeight, width, shape.strip)
    show(this.taskLabel, shape.task); box(this.taskLabel, 4, S.stripPadding, width - 10, S.lineHeight + 2)
    const lineY = S.stripPadding + (shape.task ? S.lineHeight : 0)
    const outline = shape.term ? { x: m, y: m + S.tabHeight, w: width, h: shape.strip } : { x: m, y: m, w: this.nameWidth, h: S.tabHeight }
    box(this.ring, outline.x - 1.5, outline.y - 1.5, outline.w + 3, outline.h + 3); box(this.glow, outline.x - 1.5, outline.y - 1.5, outline.w + 3, outline.h + 3)
    show(this.glyphBox, shape.line); box(this.glyphBox, 5, lineY - 2, 8, S.lineHeight + 4)
    this.glyphBox.style.color = color
    show(this.clip, shape.line)
    let clipRight = 0
    if (shape.line) {
      const x = 13
      const room = width - x - 4 - (running(c.phase) ? 7 : 0) - 6
      const visible = Math.min(Math.max(this.textRoom(shape), room), this.lineWidth)
      box(this.clip, x + 4, lineY, visible + 1, S.lineHeight + 2)
      this.lineLabel.style.width = this.lineWidth + 2 + 'px'
      clipRight = x + 4 + visible + 1
    }
    const caret = shape.line && running(c.phase)
    show(this.caret, caret); if (caret) box(this.caret, clipRight + 1, lineY + 2, 5, 10)
    const ringColor = attention ? color : this.selected ? accent : this.hovered ? 'rgba(255,255,255,0.75)' : null
    const thin = this.hovered && !this.selected && !attention
    show(this.ring, !!ringColor)
    this.ring.style.borderColor = ringColor ?? 'transparent'; this.ring.style.borderWidth = (thin ? 1 : 1.5) + 'px'
    this.nameBox.style.boxShadow = ringColor ? `inset 0 0 0 ${thin ? 1 : 1.5}px ${ringColor}` : 'none'
    show(this.glow, attention && !this.reducedMotion); this.glow.style.borderColor = color
    show(this.bar.root, shape.bar)
    if (shape.bar) box(this.bar.root, m, m + pillHeight + S.barGap, width, S.barHeight)
    const card = this.cardSize(shape)
    show(this.card, card.h > 0)
    if (card.h > 0) {
      box(this.card, m, (shape.bar ? m + pillHeight + S.barGap + S.barHeight : m + pillHeight) + 3, width, card.h)
      this.cardRows.forEach((row, i) => {
        show(row.clip, i < this.cardLines.length)
        box(row.clip, 7, 5 + i * S.cardLine, width - 14, S.cardLine)
      })
    }
    this.bar.layout(width)
  }

  setCardLines(lines) {
    if (JSON.stringify(lines) === JSON.stringify(this.cardLines)) return false
    this.cardLines = lines
    while (this.cardRows.length < lines.length) {
      const clip = el('div', 'tag-row', this.card), label = el('div', 'tag-row-text', clip)
      this.cardRows.push({ clip, label })
    }
    this.cardRows.forEach((row, i) => { row.label.textContent = lines[i] ?? '' })
    return true
  }

  /** Long lines scroll to the end and back, pausing at each end; the log's lines run as tickers. */
  restartMarquee() {
    if (this.hidden) return
    this.marquee?.cancel(); this.marquee = null
    const overflow = this.lineWidth - (this.clip.style.display === 'none' ? this.textRoom(this.shape()) : parseFloat(this.clip.style.width) - 1)
    if (overflow > 1 && !this.reducedMotion) {
      const travel = overflow / S.scrollSpeed, pause = S.edgePause, total = pause * 2 + travel * 2
      this.marquee = this.lineLabel.animate([
        { transform: 'translateX(0)', offset: 0 }, { transform: 'translateX(0)', offset: pause / total },
        { transform: `translateX(${-overflow}px)`, offset: (pause + travel) / total }, { transform: `translateX(${-overflow}px)`, offset: (pause * 2 + travel) / total },
        { transform: 'translateX(0)', offset: 1 },
      ], { duration: total * 1000, iterations: Infinity })
    }
    this.cardRows.forEach((row, i) => {
      row.ticker?.cancel(); row.ticker = null
      const text = this.cardLines[i] ?? ''
      const room = this.card.style.display === 'none' ? Infinity : parseFloat(row.clip.style.width)
      const fits = measure(text, fonts.card) + 4 <= room
      row.label.textContent = fits || this.reducedMotion ? text : text + S.tickerGap + text
      if (fits || this.reducedMotion) return
      const pass = measure(text + S.tickerGap, fonts.card)
      row.ticker = row.label.animate([{ transform: 'translateX(0)' }, { transform: `translateX(${-pass}px)` }],
        { duration: pass / S.scrollSpeed * 1000, iterations: Infinity, easing: 'linear' })
    })
  }

  /** Working bobs with a breathing dot and blinking cursor, needing you pulses, a failure shakes now and then. */
  restartMotion() {
    for (const e of [this.body, this.dot, this.caret, this.glow, this.glyphBox]) e.getAnimations().forEach((a) => { if (a !== this.jolt) a.cancel() })
    const phase = this.content?.phase
    if (!phase || this.reducedMotion || this.hidden) return
    const quiet = this.mode === 'compact' && !needsYou(phase)
    const loop = (e, frames, seconds, extra = {}) => e.animate(frames, { duration: seconds * 1000, iterations: Infinity, easing: 'ease-in-out', ...extra })
    if (running(phase) && !quiet) {
      loop(this.body, [{ transform: 'translateY(0)' }, { transform: 'translateY(-2px)' }, { transform: 'translateY(0)' }], 2.6)
      loop(this.caret, [{ opacity: 1 }, { opacity: 1, offset: 0.5 }, { opacity: 0, offset: 0.5 }, { opacity: 0 }], 1, { easing: 'linear' })
    }
    if (phase === 'thinking' && !quiet) loop(this.body, [{ transform: 'translateY(0)' }, { transform: 'translateY(-2px)' }, { transform: 'translateY(0)' }], 4.2)
    if ((running(phase) || phase === 'thinking' || needsYou(phase)) && !quiet) loop(this.dot, [{ opacity: 1 }, { opacity: 0.35 }, { opacity: 1 }], 1.4)
    if (needsYou(phase)) {
      loop(this.glow, [{ opacity: 0.7, borderWidth: '1.5px', inset: '0' }, { opacity: 0, borderWidth: '6px', offset: 0.5 }, { opacity: 0, borderWidth: '6px' }], 1.6)
    }
    if (phase === 'failed') {
      const x = (v, offset) => ({ transform: `translateX(${v}px)`, offset })
      loop(this.body, [x(0, 0), x(0, 0.84), x(-3, 0.86), x(3, 0.89), x(-2, 0.92), x(2, 0.95), x(0, 1)], 4, { easing: 'linear' })
    }
  }

  /** A brief pop or shake for a moment (a step done, a test failed). */
  react(moments, now = Date.now()) {
    if (!moments.length || now - this.lastReaction < 1000) return
    this.lastReaction = now
    const first = [...moments].sort((a, b) => emoteOrder.indexOf(a) - emoteOrder.indexOf(b))[0]
    this.announce?.(`${this.content?.name ?? ''} ${emoteSpoken[first]}`)
    if (this.reducedMotion || this.hidden) return
    if (['angry', 'wrench', 'alert'].includes(first)) {
      this.jolt = this.root.animate([0, -3, 3, -2, 2, 0].map((v) => ({ translate: `${v}px 0` })), { duration: 400 })
    } else {
      this.glyphBox.animate([{ transform: 'scale(1)' }, { transform: 'scale(1.5)' }, { transform: 'scale(0.9)' }, { transform: 'scale(1)' }], { duration: 450 })
    }
  }
  remove() { this.root.remove() }
}

// MARK: Progress

export class ProgressBar {
  constructor(parent) {
    this.root = el('div', 'tag-bar', parent)
    this.segments = []; this.sweep = el('div', 'tag-sweep'); this.progress = undefined; this.color = Palette.ok; this.live = false; this.width = 0
  }
  update(progress, color, live) {
    if (JSON.stringify(progress) === JSON.stringify(this.progress) && color === this.color && live === this.live) return
    this.progress = progress; this.color = color; this.live = live
    let fills = []
    if (progress?.kind === 'steps') fills = Array.from({ length: progress.total }, (_, i) => (i < progress.done ? color : Palette.empty))
    else if (progress?.kind === 'sweep') fills = [Palette.empty]
    while (this.segments.length > fills.length) this.segments.pop().remove()
    while (this.segments.length < fills.length) this.segments.push(el('div', 'tag-segment', this.root))
    this.segments.forEach((s, i) => { s.style.background = fills[i]; s.getAnimations().forEach((a) => a.cancel()) })
    if (progress?.kind === 'sweep') this.root.appendChild(this.sweep); else this.sweep.remove()
    this.sweep.style.background = color
    this.root.setAttribute('aria-label', progress?.kind === 'steps' ? `${progress.done} of ${progress.total} steps done` : progress ? 'Working' : '')
    this.layout(this.width, true)
  }
  layout(width, force = false) {
    if (width === this.width && !force) return
    this.width = width
    const gap = 2, count = Math.max(1, this.segments.length), w = (width - gap * (count - 1)) / count
    this.segments.forEach((s, i) => { s.style.left = i * (w + gap) + 'px'; s.style.width = Math.max(0, w) + 'px' })
    this.sweep.style.width = width * 0.35 + 'px'
    this.animate()
  }
  /** The newest filled block glows while work goes on; the sweep moves across. */
  animate() {
    this.sweepAnimation?.cancel(); this.sweepAnimation = null
    if (!this.live) return
    if (this.sweep.parentNode) {
      this.sweepAnimation = this.sweep.animate([{ transform: `translateX(${-this.width * 0.35}px)` }, { transform: `translateX(${this.width}px)` }],
        { duration: 1600, iterations: Infinity, easing: 'ease-in-out' })
    } else if (this.progress?.kind === 'steps' && this.progress.done > 0 && this.progress.done <= this.segments.length) {
      const segment = this.segments[this.progress.done - 1]
      if (!segment.getAnimations().length) segment.animate([{ opacity: 1 }, { opacity: 0.55 }, { opacity: 1 }], { duration: 1400, iterations: Infinity })
    }
  }
}

// MARK: Moments

export const emoteOrder = ['alert', 'question', 'wrench', 'angry', 'star', 'check', 'note', 'idea', 'plus', 'thinking']
const emoteSpoken = { alert: 'needs you', question: 'has a question', angry: 'hit a failure', wrench: 'needs a fix', star: 'has a dish ready',
  check: 'tests passed', note: 'finished a step', idea: 'made a plan', plus: 'fetched from the pantry', thinking: 'is thinking' }

/** What changed between two looks at an agent that deserves a reaction (the app's ChefMoment). */
export function detectMoments(previous, current) {
  if (!previous) return []
  const moments = []
  const attention = (a) => a.status === 'waiting' || a.status === 'failed'
  if (attention(current) && (!attention(previous) || current.attentionReason !== previous.attentionReason)) {
    moments.push(current.status === 'waiting' && current.attentionReason === 'input' ? 'question' : 'alert')
  }
  if (current.status === 'done' && previous.status !== 'done') moments.push('star')
  const before = previous.turnWork ?? {}, after = current.turnWork ?? {}
  const count = (work, outcome) => (work.tests ?? []).filter((t) => t.outcome === outcome).length
  if (count(after, 'failed') > count(before, 'failed') || (after.failedCommands ?? 0) > (before.failedCommands ?? 0)) moments.push('angry')
  if (count(after, 'passed') > count(before, 'passed')) moments.push('check')
  const kept = (plan) => (plan && plan.checklist?.length > 1 && !plan.tasksPreviousTurn ? plan : null)
  const now = kept(current.plan)
  if (now) {
    const then = kept(previous.plan)
    if (then) { if (now.completedTaskCount > then.completedTaskCount) moments.push('note') } else moments.push('idea')
  }
  if ((after.resources ?? []).length > (before.resources ?? []).length) moments.push('plus')
  return moments
}
