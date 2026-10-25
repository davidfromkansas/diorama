// Engine-independent chef behaviour, ported from the app's ChefDirector: navigation, clip
// sequencing, marker-synchronised prop hand-offs and interruption reconciliation. The avatar
// renders whatever this decides.

import { dist, wrap } from './layout.js'

export const locomotionClips = new Set(['walk', 'run', 'carry_walk'])
const machineGestures = new Set(['use_vending', 'brew_espresso'])
const walkSpeed = 0.75, runSpeed = 1.55, turnRate = 9, acceleration = 6
const fadeTime = 0.22, urgentFade = 0.12, locomotionFade = 0.15

const sameStation = (a, b) => a === b || (!!a && !!b && a.id === b.id && a.area === b.area && a.facing === b.facing &&
  a.stand[0] === b.stand[0] && a.stand[1] === b.stand[1])

export class ChefDirector {
  /** `clips`: the manifest's clips (duration, loop, markers, nominal_speed); `unit`: world units per chef unit. */
  constructor(clips, unit, navigation) {
    this.clips = clips; this.unit = unit; this.navigation = navigation
    this.reducedMotion = false
    this.onEvent = null
    this.position = [0, 0]; this.heading = 0; this.speed = 0
    this.clip = { name: 'idle_available', loop: true, token: 0, fade: 0, timeScale: 1 }
    this.clipTime = 0
    this.intent = null
    this.station = null
    this.held = new Set()
    this.carriesJar = false
    this.placedPlate = null
    this.strolls = false
    this.gongStrikes = 0
    this.steps = []; this.path = []; this.pathGoal = null
    this.fired = new Set(); this.played = new Set(); this.token = 0
  }

  get settled() {
    if (this.steps.length === 1 && this.steps[0].type === 'loop') return this.speed === 0
    return this.steps.length === 0
  }

  place(point, heading = 0) {
    this.position = [point[0], point[1]]; this.heading = heading; this.speed = 0; this.path = []; this.pathGoal = null
  }

  /** Set down somewhere by hand: no longer at any station, and it walks back to its work. */
  putDown(point) {
    this.place(point, this.heading)
    this.station = null; this.placedPlate = null
    if (this.intent) this.setIntent({ ...this.intent, prelude: null }, true)
  }

  setIntent(requested, force = false) {
    if (!force && this.intent?.key === requested.key) return
    const next = { ...requested, oneShot: requested.oneShot ? { ...requested.oneShot } : null }
    if (next.oneShot) {
      if (this.played.has(next.oneShot.id)) { next.oneShot.restored = true; next.pickup = null }
      this.played.add(next.oneShot.id)
    }
    this.interrupt(next)
    this.intent = next
    if (next.urgent && !next.station) { this.speed = 0; this.path = []; this.pathGoal = null }
    const plan = []
    if (!this.reducedMotion) {
      const seated = this.clip.name.startsWith('sit_')
      if (seated && next.station && !sameStation(next.station, this.station)) plan.push({ type: 'once', clip: 'stand_up', markers: {} })
      if (next.prelude) plan.push({ type: 'once', clip: next.prelude, markers: {} })
    }
    const target = next.station
    if (target) {
      const carry = !!next.pickup || (this.held.has('plate') && next.oneShot?.clip === 'present_review') || this.carriesJar
      if (next.strike && next.oneShot && !next.oneShot.restored && !this.reducedMotion) {
        const strike = next.strike
        plan.push({ type: 'goto', station: strike, carry: false }, { type: 'face', yaw: strike.facing, carry: false }, { type: 'grab', prop: 'mallet' },
          { type: 'once', clip: 'strike_gong', markers: { impact: () => { this.gongStrikes += 1 } } }, { type: 'release', prop: 'mallet' })
      }
      if (next.pickup && !this.held.has('plate')) {
        const pickup = next.pickup
        plan.push({ type: 'goto', station: pickup, carry: false }, { type: 'face', yaw: pickup.facing, carry: false },
          { type: 'once', clip: 'pickup', markers: { attach: () => this.held.add('plate') } })
      }
      if (!sameStation(this.station, target) || dist(this.position, target.stand) > 0.05 * this.unit) plan.push({ type: 'goto', station: target, carry })
      plan.push({ type: 'face', yaw: target.facing, carry })
      const fromMachine = next.oneShot ? machineGestures.has(next.oneShot.clip) && !next.oneShot.restored && !this.reducedMotion : false
      if (next.hand && !fromMachine) plan.push({ type: 'grab', prop: next.hand })
    }
    const shot = next.oneShot
    if (shot && !shot.restored && !this.reducedMotion) {
      plan.push(this.oneShotStep(shot.clip, next.station))
      if (machineGestures.has(shot.clip) && next.hand) plan.push({ type: 'grab', prop: next.hand })
    } else if (shot) {
      this.applyOutcome(next)
    }
    plan.push({ type: 'loop', clip: next.loop })
    this.steps = plan
    this.startStep(next.urgent ? urgentFade : fadeTime)
  }

  interrupt(next) {
    const first = this.steps[0]
    if (first?.type === 'once') first.interrupted?.()
    const keep = new Set()
    if (next.hand) keep.add(next.hand)
    if (next.pickup) keep.add('plate')
    if (next.oneShot?.clip === 'cancel_cleanup' && !next.oneShot.restored && !this.reducedMotion) for (const p of this.held) keep.add(p)
    for (const p of [...this.held]) if (!keep.has(p)) this.held.delete(p)
    if (this.placedPlate && !sameStation(next.station, this.placedPlate)) this.placedPlate = null
    if (this.station && !sameStation(next.station, this.station)) this.station = null
    this.path = []; this.pathGoal = null
  }

  oneShotStep(name, target) {
    if (name === 'present_review') {
      const release = () => {
        if (!this.held.has('plate')) return
        this.held.delete('plate')
        this.placedPlate = target && dist(this.position, target.stand) < 0.1 * this.unit ? target : null
      }
      return { type: 'once', clip: name, markers: { release }, interrupted: release }
    }
    if (name === 'cancel_cleanup') {
      const release = () => this.held.clear()
      return { type: 'once', clip: name, markers: { release }, interrupted: release }
    }
    return { type: 'once', clip: name, markers: {} }
  }

  applyOutcome(next) {
    if (next.oneShot?.clip === 'present_review') { this.held.delete('plate'); this.placedPlate = next.station }
    else if (next.oneShot?.clip === 'cancel_cleanup') this.held.clear()
  }

  play(name, fade, restart = false, timeScale = 1) {
    if (this.clip.name === name && !restart) { this.clip.timeScale = timeScale; return }
    this.token += 1
    this.clip = { name, loop: this.clips[name]?.loop ?? true, token: this.token, fade, timeScale }
    this.clipTime = 0; this.fired = new Set()
  }

  startStep(fade) {
    const step = this.steps[0]
    if (!step) return
    if (step.type === 'once') this.play(step.clip, fade, true)
    else if (step.type === 'loop') this.play(step.clip, fade)
    else if (step.type === 'goto' || step.type === 'face') {
      this.play(step.carry ? 'carry_idle' : locomotionClips.has(this.clip.name) ? 'idle_available' : this.clip.name, fade)
    }
  }

  advance() { this.steps.shift(); this.startStep(fadeTime) }

  update(delta) {
    let dt = Math.max(0, delta)
    const meta = this.clips[this.clip.name], previous = this.clipTime
    this.clipTime += dt * this.clip.timeScale
    if (meta && meta.loop && meta.duration > 0 && !this.reducedMotion && this.onEvent) {
      const u0 = previous / meta.duration, u1 = this.clipTime / meta.duration, base = Math.floor(u0)
      for (const [name, at] of Object.entries(meta.markers || {})) for (const k of [base, base + 1]) if (k + at > u0 && k + at <= u1) this.onEvent(name, this.clip.name)
    }
    let budget = 8
    while (budget > 0 && this.steps.length) {
      budget -= 1
      const step = this.steps[0]
      if (step.type === 'goto') {
        if (!this.move(step.station, step.carry, dt)) break
        this.station = step.station
        this.advance(); dt = 0
      } else if (step.type === 'face') {
        if (!this.turn(step.yaw, dt)) break
        this.advance()
      } else if (step.type === 'grab') { this.held.add(step.prop); this.advance() }
      else if (step.type === 'release') { this.held.delete(step.prop); this.advance() }
      else if (step.type === 'once') {
        const m = this.clips[step.clip]
        const u = m ? this.clipTime / Math.max(m.duration, 0.0001) : 1
        for (const [marker, at] of Object.entries(m?.markers || {})) {
          if (u >= at && !this.fired.has(marker)) { this.fired.add(marker); step.markers[marker]?.() }
        }
        if (u < 1) break
        this.advance()
      } else break
    }
    const now = this.clips[this.clip.name]
    if (now && now.loop && now.duration > 0 && this.clipTime > now.duration) this.clipTime %= now.duration
  }

  move(target, carry, dt) {
    if (!this.pathGoal || this.pathGoal[0] !== target.stand[0] || this.pathGoal[1] !== target.stand[1]) {
      this.pathGoal = target.stand
      this.path = this.navigation.route(this.position, target.stand) ?? [target.stand]
    }
    while (this.path.length > 1 && dist(this.position, this.path[0]) < 0.2 * this.unit) this.path.shift()
    const goal = this.path[0] ?? target.stand, final = this.path.length <= 1
    const delta = [goal[0] - this.position[0], goal[1] - this.position[1]], distance = Math.hypot(delta[0], delta[1])
    if (final && distance < 0.03 * this.unit) {
      this.position = [target.stand[0], target.stand[1]]; this.speed = 0; this.path = []; this.pathGoal = null
      return true
    }
    const error = wrap(Math.atan2(delta[0], delta[1]) - this.heading)
    this.heading = wrap(this.heading + Math.max(-turnRate * dt, Math.min(turnRate * dt, error)))
    const run = !carry && !this.strolls
    const top = (run ? runSpeed : walkSpeed * 1.3) * this.unit
    const wanted = Math.min(top, final ? distance * 3 : top) * Math.max(0, Math.cos(error))
    this.speed += Math.max(-acceleration * this.unit * dt * 2, Math.min(acceleration * this.unit * dt, wanted - this.speed))
    const step = Math.min(this.speed * dt, distance)
    this.position = [this.position[0] + Math.sin(this.heading) * step, this.position[1] + Math.cos(this.heading) * step]
    const moving = this.speed > 0.02 * this.unit
    const name = carry ? 'carry_walk' : run && this.speed > walkSpeed * this.unit * 1.1 ? 'run' : moving ? 'walk' : 'idle_available'
    const nominal = this.clips[name]?.nominal_speed
    const scale = nominal ? Math.max(0.6, Math.min(1.5, this.speed / (nominal * this.unit))) : 1
    this.play(name, locomotionFade, false, scale)
    return false
  }

  turn(yaw, dt) {
    const error = wrap(yaw - this.heading)
    if (Math.abs(error) < 0.02) { this.heading = yaw; return true }
    this.heading = wrap(this.heading + Math.max(-turnRate * dt, Math.min(turnRate * dt, error)))
    return false
  }
}
