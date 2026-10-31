// Kitchen foley (the app's KitchenSound and KitchenAudio): what each chef clip sounds like, pinned
// to points in the clip, played on a small pool of voices panned to where the chef stands.

import { isOffice } from './scene/theme.js'

const sounds = {
  step: [5, 0.18], chop: [3, 0.35], clink: [3, 0.3], tap: [3, 0.35], page: [3, 0.6], pot: [3, 0.18], grab: [2, 1], plate: [3, 0.6],
  cloche: [2, 0.45], clatter: [2, 0.4], gong: [2, 0.75], error: [1, 0.3], cheer: [1, 0.3], ding: [1, 0.35], chair: [3, 0.6],
}
// The office plays its own takes on some of these (typing, a terminal blip, a desk bell…), the kitchen's otherwise.
const officeSounds = new Set(['chop', 'ding', 'gong', 'plate', 'pot', 'tap'])
const folder = (name) => isOffice && officeSounds.has(name) ? 'OfficeSounds' : 'KitchenSounds'
const steps = [[0.05, 'step'], [0.55, 'step']]
const cues = {
  walk: steps, carry_walk: steps, run: steps,
  working_chop: [['impact', 'chop'], ['impact_2', 'chop']],
  testing_dish: [['taste', 'clink']], sit_sip: [['sip', 'clink']],
  planning_recipe: [['tap', 'tap']], researching_book: [[0.15, 'page']], read_ticket: [[0.2, 'page']],
  waiting_tool: [[0.05, 'pot']], pickup: [['attach', 'grab']], putdown: [['release', 'plate']], present_review: [['release', 'plate']],
  cover_dish: [['release', 'cloche']], cancel_cleanup: [['release', 'clatter']], strike_gong: [['impact', 'gong']],
  error_react: [[0, 'error']], celebrate_done: [[0.1, 'cheer']], arrive_wave: [[0, 'ding']], sit_down: [[0.6, 'chair']], stand_up: [[0.1, 'chair']],
}

/** Sounds whose cue falls in (`from`, `to`], in clip fractions (a loop's `to` may run past 1 as it wraps). */
export function crossed(clip, markers, from, to) {
  const list = cues[clip]
  if (!list || !(to > from)) return []
  const result = []
  for (const [at, sound] of list) {
    const point = typeof at === 'string' ? markers?.[at] : at
    if (point == null) continue
    if ((point > from && point <= to) || (point + 1 > from && point + 1 <= to)) result.push(sound)
  }
  return result
}

class KitchenAudio {
  constructor() {
    this.context = null; this.buffers = new Map(); this.lastPlayed = new Map(); this.lastVariant = new Map(); this.busy = 0
    this.enabled = (() => { try { return localStorage.getItem('kitchenSounds') !== 'off' } catch { return true } })()
  }
  /** Browsers start audio only after a gesture: the first click or key unlocks it. */
  unlock() {
    if (!this.context) {
      const Context = window.AudioContext || window.webkitAudioContext
      if (!Context) return
      this.context = new Context()
      this.master = this.context.createGain(); this.master.gain.value = 0.8; this.master.connect(this.context.destination)
      for (const name of Object.keys(sounds)) this.variants(name)
    }
    if (this.context.state === 'suspended') this.context.resume()
  }
  get ready() { return !!this.context && this.context.state === 'running' }
  setEnabled(on) {
    this.enabled = on
    try { localStorage.setItem('kitchenSounds', on ? 'on' : 'off') } catch {}
  }
  variants(name) {
    if (!this.buffers.has(name)) {
      const [count] = sounds[name]
      this.buffers.set(name, Promise.all(Array.from({ length: count }, (_, i) =>
        fetch(`/assets/${folder(name)}/${name}-${i}.mp3`).then((r) => r.arrayBuffer()).then((data) => this.context.decodeAudioData(data)).catch(() => null)))
        .then((list) => list.filter(Boolean)))
    }
    return this.buffers.get(name)
  }
  /** `pan` runs -1 (left) … 1 (right); `level` scales the sound's own volume. */
  async play(name, pan = 0, level = 1) {
    if (!this.enabled || !this.ready || !sounds[name]) return
    const now = performance.now() / 1000
    if (now - (this.lastPlayed.get(name) ?? 0) < (name === 'step' ? 0.05 : 0.03) || this.busy >= 10) return
    this.lastPlayed.set(name, now)
    const options = await this.variants(name)
    if (!options.length) return
    let pick = Math.floor(Math.random() * options.length)
    if (options.length > 1 && pick === this.lastVariant.get(name)) pick = (pick + 1) % options.length
    this.lastVariant.set(name, pick)
    const source = this.context.createBufferSource()
    source.buffer = options[pick]
    source.playbackRate.value = 0.93 + Math.random() * 0.14
    const gain = this.context.createGain(); gain.gain.value = sounds[name][1] * Math.max(0, Math.min(1, level))
    const panner = this.context.createStereoPanner(); panner.pan.value = Math.max(-1, Math.min(1, pan)) * 0.7
    source.connect(gain).connect(panner).connect(this.master)
    this.busy += 1
    source.onended = () => { this.busy -= 1 }
    source.start()
  }
}

export const audio = new KitchenAudio()
