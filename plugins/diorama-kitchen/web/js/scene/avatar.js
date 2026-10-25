// One rendered chef (the app's ChefAvatar and PantryCarrier): its director moves it, its rig plays
// what the director decides with crossfades, props ride its hand sockets, its task's dish follows
// it from the board to the pass, and what it fetches is carried between stations.

import * as THREE from 'three'
import { ChefDirector, locomotionClips } from './director.js'
import { named } from './assets.js'
import { crossed } from '../audio.js'

export const props = {
  card: ['prop_recipe_card', 'socket_hand.L', 'planning_recipe'], book: ['prop_cookbook', 'socket_hand.L', 'researching_book'],
  knife: ['prop_knife', 'socket_hand.R', 'working_chop'], spoon: ['prop_spoon', 'socket_hand.R', 'testing_dish'],
  plate: ['prop_plate', 'socket_carry', 'carry_idle'], ticket: ['prop_ticket', 'socket_hand.L', 'read_ticket'],
  mug: ['prop_mug', 'socket_hand.R', 'sit_sip'], cloche: ['prop_cloche', 'socket_hand.R', 'cover_dish'],
  mallet: ['prop_gong_mallet', 'socket_hand.R', 'strike_gong'], can: ['prop_can', 'socket_hand.R', 'stand_sip'],
}
export const dishSize = 0.76
const boardSpot = [-0.05, 0.605, 0.7], tastingSpot = [-0.1, 0.585, 0.66], passSpot = [0, 0.585, 1.0]
export const liftHeight = 0.8
const surprise = 0.9
const squirmBones = [['hips', 0.18, 9, 0], ['spine', 0.14, 11, 1.1], ['chest', 0.12, 8, 2.3], ['head', 0.32, 13, 0.4],
  ['upperarm.L', 0.7, 12, 0], ['upperarm.R', 0.7, 12, 3.1], ['forearm.L', 0.5, 15, 1.2], ['forearm.R', 0.5, 15, 4.0],
  ['thigh.L', 0.3, 10, 0.6], ['thigh.R', 0.3, 10, 3.7]]
const X = new THREE.Vector3(1, 0, 0), Y = new THREE.Vector3(0, 1, 0), Z = new THREE.Vector3(0, 0, 1)

/** A copy whose materials are its own, so it can fade without fading every other copy. */
export function ownCopy(template) {
  const node = template.clone()
  node.traverse((n) => { if (n.isMesh) n.material = Array.isArray(n.material) ? n.material.map((m) => m.clone()) : n.material.clone() })
  return node
}
export function setOpacity(node, value) {
  node.traverse((n) => {
    if (!n.isMesh && !n.isPoints) return
    for (const m of [].concat(n.material)) {
      if (m.opacity === value && m.transparent === value < 1) continue
      m.opacity = value
      if (m.transparent !== value < 1) { m.transparent = value < 1; m.needsUpdate = true }
    }
  })
}
const fit = (manifest, node, clip) => {
  const f = manifest.attach[node]?.[clip]
  return f ? { position: new THREE.Vector3(...f.position), quaternion: new THREE.Quaternion(...f.quaternion) } : null
}

/** Plays clips on a rig by time and weight (the director owns the clock). */
class RigPlayer {
  constructor(root, clips) {
    this.mixer = new THREE.AnimationMixer(root); this.clips = clips; this.actions = new Map(); this.live = new Set()
  }
  action(name) {
    if (!this.actions.has(name)) {
      const clip = this.clips[name]
      if (!clip) return null
      const action = this.mixer.clipAction(clip)
      action.setLoop(THREE.LoopRepeat, Infinity)
      this.actions.set(name, action)
    }
    return this.actions.get(name)
  }
  duration(name) { return this.clips[name]?.duration ?? 0 }
  /** `poses`: [{ name, time, weight }], weights summing to 1. */
  pose(poses) {
    const wanted = new Set()
    for (const { name, time, weight } of poses) {
      const action = this.action(name)
      if (!action) continue
      wanted.add(action)
      if (!this.live.has(action)) { action.play(); this.live.add(action) }
      action.enabled = true
      action.setEffectiveWeight(weight)
      action.time = time
    }
    for (const action of [...this.live]) if (!wanted.has(action)) { action.stop(); this.live.delete(action) }
    this.mixer.update(0)
  }
}

export class ChefAvatar {
  /** `kit`: { food: dish templates by id, carry: carried-item templates by kind, particles }. */
  constructor(id, rigRoot, assets, navigation, kit, scale = 1.4) {
    this.id = id; this.kit = kit; this.manifest = assets.manifest; this.templates = assets.props
    this.root = new THREE.Group(); this.root.name = 'agent:' + id
    this.visual = new THREE.Group(); this.visual.scale.setScalar(scale)
    this.rigRoot = rigRoot
    this.visual.add(rigRoot); this.root.add(this.visual)
    this.baseScale = scale
    this.player = new RigPlayer(rigRoot, assets.clips)
    this.director = new ChefDirector(assets.manifest.clips, scale, navigation)
    this.sockets = {}
    for (const name of ['socket_hand.L', 'socket_hand.R', 'socket_carry']) this.sockets[name] = named(rigRoot, name)
    this.bones = Object.fromEntries(squirmBones.map(([name]) => [name, named(rigRoot, name)]))
    this.props = new Map()
    this.token = -1; this.last = null; this.fading = null; this.fadeElapsed = 0; this.fadeDuration = 0
    this.heard = []; this.soundClip = null; this.silent = false
    this.held = null
    this.dish = null; this.dishNode = null; this.dishSpot = ''
    this.pantryItem = null; this.prepItem = null
    this.pantryCarry = new PantryCarrier(kit.carry, kit.particles)
    this.opacity = 1
    this.character = 'classic'
  }

  get animating() { return this.held != null || !(this.director.settled && this.fading == null && this.director.reducedMotion) }

  sampleTime(name, time, loop) {
    const duration = this.player.duration(name)
    if (!(duration > 0)) return 0
    if (this.director.reducedMotion && loop && !locomotionClips.has(name)) return duration * 0.35
    return loop ? time : Math.min(time, duration - 0.0001)
  }

  /** Poses the rig: the current clip, crossfading from the previous one. */
  applyPose(name, time, delta) {
    const poses = [{ name, time, weight: 1 }]
    if (this.fading) {
      this.fadeElapsed += Math.max(0, delta)
      if (this.fadeElapsed < this.fadeDuration) {
        this.fading.time += Math.max(0, delta)
        const weight = this.fadeElapsed / this.fadeDuration
        const from = this.fading
        poses[0].weight = weight
        if (from.name === name) poses[0].weight = 1
        else poses.push({ name: from.name, time: this.sampleTime(from.name, from.time, from.loop), weight: 1 - weight })
      } else this.fading = null
    }
    this.player.pose(poses)
  }

  update(delta) {
    if (this.held) { this.updateHeld(delta); return }
    const director = this.director
    director.update(delta)
    this.root.position.set(director.position[0], 0, director.position[1])
    this.root.quaternion.setFromAxisAngle(Y, director.heading)
    const command = director.clip
    this.listen(command)
    if (command.token !== this.token) {
      this.token = command.token
      this.fading = this.last ? { ...this.last } : null; this.fadeElapsed = 0; this.fadeDuration = command.fade
    }
    const time = this.sampleTime(command.name, director.clipTime, command.loop)
    this.applyPose(command.name, time, delta)
    this.last = { name: command.name, time, loop: command.loop }
    this.syncProps()
    const wanted = {}
    if (this.pantryItem) wanted.pantry = this.pantryItem
    if (this.prepItem) wanted.prep = this.prepItem
    wanted.order = { kind: 'idea', name: 'Order' }; wanted.cooking = { kind: 'board', name: 'Chopped board' }; wanted.stove = { kind: 'pot', name: 'Stove pot' }
    const delivering = director.held.has('plate') || !!director.intent?.pickup
    this.pantryCarry.sync(wanted, director.station?.area ?? null, director.reducedMotion, delta, this.sockets['socket_carry'],
      fit(this.manifest, 'prop_plate', 'carry_idle'), this.visual, this.manifest.stations.counter_top, delivering)
    director.carriesJar = this.pantryCarry.carrying
  }

  /** Picked up: a startled jolt, then legs paddling in the air with the body wriggling on top. */
  updateHeld(delta) {
    const hold = this.held, dt = Math.max(0, delta)
    if (hold.time === 0) { this.fading = this.last ? { ...this.last } : null; this.fadeElapsed = 0; this.fadeDuration = 0.12 }
    hold.time += dt
    const previous = [...hold.point]
    const k = Math.min(1, dt * 16)
    hold.point = [hold.point[0] + (hold.target[0] - hold.point[0]) * k, hold.point[1] + (hold.target[1] - hold.point[1]) * k]
    const velocity = dt > 0 ? [(hold.point[0] - previous[0]) / dt, (hold.point[1] - previous[1]) / dt] : [0, 0]
    const clamp = (v) => Math.max(-0.5, Math.min(0.5, v))
    const s = Math.min(1, dt * 8)
    hold.swing = [hold.swing[0] + (clamp(velocity[0] * -0.08) - hold.swing[0]) * s, hold.swing[1] + (clamp(velocity[1] * -0.08) - hold.swing[1]) * s]
    const lift = liftHeight * this.baseScale * Math.min(1, hold.time / 0.15)
    const reduced = this.director.reducedMotion
    const sway = reduced ? 0.04 * Math.sin(hold.time * 2) : 0
    this.root.position.set(hold.point[0], lift, hold.point[1])
    const yaw = new THREE.Quaternion().setFromAxisAngle(Y, this.director.heading)
    const tilt = new THREE.Quaternion().setFromAxisAngle(X, hold.swing[1] + sway).multiply(new THREE.Quaternion().setFromAxisAngle(Z, -hold.swing[0]))
    this.root.quaternion.copy(tilt.multiply(yaw))
    const startled = hold.time < surprise && !reduced
    const name = reduced ? 'idle_available' : startled ? 'blocked_react' : 'run'
    if (!startled && !reduced && this.last?.name === 'blocked_react') { this.fading = { ...this.last }; this.fadeElapsed = 0; this.fadeDuration = 0.15 }
    const time = reduced ? 0 : startled ? hold.time : this.sampleTime('run', (hold.time - surprise) * 1.3, true)
    this.applyPose(name, time, dt)
    if (!reduced) this.squirm(hold.time)
    this.last = { name, time, loop: name !== 'blocked_react' }
    this.syncProps()
  }

  squirm(t) {
    const ease = Math.min(1, t / 0.4), q = new THREE.Quaternion()
    for (const [bone, amount, speed, phase] of squirmBones) {
      const node = this.bones[bone]
      if (!node) continue
      const a = amount * ease * Math.sin(t * speed + phase), b = amount * 0.6 * ease * Math.sin(t * speed * 0.73 + phase * 1.7)
      node.quaternion.multiply(q.setFromAxisAngle(X, a)).multiply(q.setFromAxisAngle(Z, b))
    }
  }

  /** Puts the chef down on the floor and lets its director carry on from there. */
  release(point) {
    this.held = null
    this.visual.scale.setScalar(this.baseScale)
    this.director.putDown(point)
    this.token = -1
  }

  /** Collects the sound cues the clip passed this frame. */
  listen(command) {
    const clipTime = this.director.clipTime
    const previous = this.soundClip
    this.soundClip = { token: command.token, time: clipTime }
    if (this.silent) return
    const meta = this.manifest.clips[command.name]
    if (!meta || !(meta.duration > 0)) return
    if (this.director.reducedMotion && command.loop && !locomotionClips.has(command.name)) return
    const now = clipTime / meta.duration
    let from = -1
    if (previous && previous.token === command.token) {
      from = previous.time / meta.duration
      if (now < from) from -= 1
    }
    this.heard.push(...crossed(command.name, meta.markers, from, now))
  }

  propNode(prop) {
    if (this.props.has(prop)) return this.props.get(prop)
    const template = this.templates[props[prop][0]]
    if (!template) return null
    const node = ownCopy(template); node.name = props[prop][0]
    node.traverse((n) => { if (n.isMesh) n.castShadow = true })
    this.props.set(prop, node)
    if (this.opacity < 1) setOpacity(node, this.opacity)
    return node
  }

  syncProps() {
    const dish = this.currentDish()
    this.syncDish(dish)
    const director = this.director
    for (const prop of Object.keys(props)) {
      if (prop === 'plate' && dish) { this.props.get(prop)?.removeFromParent(); continue }
      const [node, socketName, clip] = props[prop]
      if (director.held.has(prop)) {
        const socket = this.sockets[socketName], object = this.propNode(prop)
        if (!socket || !object) continue
        if (object.parent !== socket) {
          object.removeFromParent(); socket.add(object)
          const f = fit(this.manifest, node, clip)
          object.position.copy(f?.position ?? new THREE.Vector3()); object.quaternion.copy(f?.quaternion ?? new THREE.Quaternion())
        }
      } else if (prop === 'plate' && director.placedPlate) {
        const object = this.propNode(prop)
        if (object && object.parent !== this.visual) {
          object.removeFromParent(); this.visual.add(object)
          object.position.set(0, this.manifest.stations.counter_top, 0.57); object.quaternion.identity()
        }
      } else this.props.get(prop)?.removeFromParent()
    }
  }

  currentDish() {
    const template = this.dish ? this.kit.food[this.dish] : null
    if (!template) { this.dishNode?.node.removeFromParent(); this.dishNode = null; return null }
    if (this.dishNode?.id !== this.dish) {
      this.dishNode?.node.removeFromParent()
      const node = ownCopy(template); node.scale.setScalar(dishSize)
      node.traverse((n) => { if (n.isMesh) n.castShadow = true })
      if (this.opacity < 1) setOpacity(node, this.opacity)
      this.dishNode = { id: this.dish, node }; this.dishSpot = ''
    }
    return this.dishNode.node
  }
  get choppingOnBoard() { return this.pantryCarry.placement === 'counter' && this.pantryCarry.item?.kind === 'board' }

  syncDish(node) {
    if (!node) return
    const director = this.director, station = director.station?.area, clip = director.clip.name
    let parent = this.visual, position = [0, 0, 0], quaternion = new THREE.Quaternion(), spot
    if (director.held.has('plate') && this.sockets['socket_carry']) {
      const f = fit(this.manifest, 'prop_plate', 'carry_idle')
      parent = this.sockets['socket_carry']; position = f ? f.position.toArray() : position; quaternion = f?.quaternion ?? quaternion; spot = 'carry'
    } else if (director.placedPlate) { position = passSpot; spot = 'pass' }
    else if (station === 'cooking' && clip === 'working_chop' && !this.choppingOnBoard) { position = boardSpot; spot = 'board' }
    else if (station === 'tasting' && clip === 'testing_dish') { position = tastingSpot; spot = 'tasting' }
    else { parent = null; spot = 'hidden' }
    if (spot === this.dishSpot) return
    this.dishSpot = spot
    node.removeFromParent()
    if (!parent) return
    parent.add(node)
    node.position.set(...position); node.quaternion.copy(quaternion)
  }

  setOpacity(value) {
    if (this.opacity === value) return
    this.opacity = value
    setOpacity(this.root, value)
  }
}

// MARK: Carried items

const sizes = { idea: 0.35, board: 0.6, pot: 0.55 }
const size = (kind) => sizes[kind] ?? 0.5
const sticky = new Set(['plan', 'idea', 'board', 'pot'])
const counterAreas = new Set(['order', 'prep', 'cooking', 'stove', 'tasting', 'pantry', 'serving'])
const puffColors = { skill: [0.35, 0.85, 0.45], plugin: [1, 0.7, 0.25], connector: [0.4, 0.6, 1], plan: [0.4, 0.6, 1], idea: [1, 0.88, 0.35], board: [0.55, 0.85, 0.4], pot: [1, 0.55, 0.3] }
const carryBoardSpot = [-0.05, 0, 0.7], fade = 3.5
const same = (a, b) => !!a && !!b && a.kind === b.kind && a.name === b.name
export const overshoot = (p) => { const c = 2.2, x = p - 1; return 1 + (c + 1) * x * x * x + c * x * x }

/** What a chef picks up at a station and carries in both hands to the next one. */
export class PantryCarrier {
  constructor(models, particles) {
    this.models = models; this.particles = particles
    this.placement = 'none'; this.item = null; this.node = null; this.opacity = 1; this.faded = 0
    this.base = { position: [0, 0, 0], quaternion: new THREE.Quaternion() }
    this.phase = 0; this.clock = 0; this.landed = false; this.reducedMotion = false
    this.origin = null; this.retired = []
  }
  get carrying() { return this.placement === 'counter' || this.placement === 'carried' }

  sync(wanted, area, reducedMotion, delta, carrySocket, carryFit, floor, counterTop, delivering) {
    this.reducedMotion = reducedMotion
    const step = Math.max(0, Math.min(delta, 0.1))
    this.phase += step; this.clock += step
    this.fadeRetired(step)
    if (area && wanted[area] && delivering) { if (this.carrying) this.retire(floor, counterTop); return }
    if (area && wanted[area]) {
      const want = wanted[area]
      if (this.carrying && this.origin === area && this.item?.kind === want.kind && (sticky.has(want.kind) || same(this.item, want))) this.item = want
      else { if (this.carrying) this.retire(floor, counterTop); this.spawn(want); this.origin = area }
      const spot = want.kind === 'board' ? [carryBoardSpot[0], carryBoardSpot[1] + counterTop, carryBoardSpot[2]] : [0, counterTop, 0.5]
      this.place('counter', floor, spot, null)
      this.animate()
      return
    }
    if (this.placement === 'counter' || this.placement === 'carried') {
      if (!area) {
        if (carrySocket) this.place('carried', carrySocket, carryFit ? carryFit.position.toArray() : [0, 0, 0], carryFit?.quaternion ?? null)
        else this.place('carried', floor, [0, counterTop * 0.85, 0.32], null)
      } else if (!counterAreas.has(area)) {
        if (this.node && !reducedMotion) this.puff(this.node)
        this.clear(); return
      } else {
        this.faded = 0; this.opacity = 1; this.landed = false
        this.place('setDown', floor, [0.42, counterTop, 0.5], null)
        if (reducedMotion) { this.clear(); return }
      }
    } else if (this.placement === 'setDown') {
      if (this.phase > 0.6) this.faded += step
      this.opacity = Math.max(0, 1 - this.faded / fade)
      if (this.opacity <= 0) { this.clear(); return }
    }
    this.animate()
  }

  animate() {
    const node = this.node
    if (!node) return
    const offset = [0, 0, 0]; let scale = [1, 1, 1]; const turn = new THREE.Quaternion()
    if (!this.reducedMotion) {
      if (this.placement === 'counter' && this.item?.kind === 'board') {
        scale = Array(3).fill(overshoot(Math.min(1, this.phase / 0.45)))
      } else if (this.placement === 'counter') {
        const p = Math.min(1, this.phase / 0.45)
        scale = Array(3).fill(overshoot(p))
        offset[1] = 0.22 * (1 - p) * (1 - p) + (p >= 1 ? 0.025 * Math.sin(this.phase * 3) : 0)
        turn.setFromAxisAngle(Y, Math.PI * (1 - p))
      } else if (this.placement === 'carried') {
        const gait = this.clock * 8.5
        offset[1] = 0.035 * Math.abs(Math.sin(gait))
        turn.setFromAxisAngle(Z, 0.14 * Math.sin(gait)).multiply(new THREE.Quaternion().setFromAxisAngle(X, 0.07 * Math.sin(gait * 0.5)))
        scale = Array(3).fill(0.85 + 0.15 * overshoot(Math.min(1, this.phase / 0.25)))
      } else if (this.placement === 'setDown') {
        const p = Math.min(1, this.phase / 0.5)
        offset[1] = 0.28 * Math.abs(Math.cos(p * Math.PI * 2.5)) * (1 - p) * (1 - p)
        const squash = p > 0.15 && p < 0.55 ? Math.sin((p - 0.15) / 0.4 * Math.PI) * 0.18 : 0
        scale = [1 + squash, 1 - squash, 1 + squash]
        if (p >= 0.2 && !this.landed) { this.landed = true; this.puff(node) }
        const gone = 1 - this.opacity
        scale = scale.map((v) => v * (1 - 0.45 * gone))
        offset[1] += 0.2 * gone
      }
    }
    const s = size(this.item?.kind)
    node.position.set(this.base.position[0] + offset[0], this.base.position[1] + offset[1], this.base.position[2] + offset[2])
    node.quaternion.copy(this.base.quaternion).multiply(turn)
    node.scale.set(scale[0] * s, scale[1] * s, scale[2] * s)
    setOpacity(node, this.opacity)
  }

  clear() {
    this.node?.removeFromParent()
    this.node = null; this.item = null; this.origin = null; this.placement = 'none'; this.opacity = 1; this.faded = 0; this.phase = 0; this.landed = false
  }
  retire(floor, counterTop) {
    const node = this.node
    if (!node) return
    if (this.reducedMotion) node.removeFromParent()
    else {
      const lies = this.placement === 'counter'
      node.removeFromParent(); floor.add(node)
      if (lies) node.position.set(...this.base.position); else node.position.set(0.42, counterTop, 0.5)
      node.quaternion.identity()
      this.retired.push({ node, time: 0, size: size(this.item?.kind) })
      this.puff(node)
    }
    this.node = null; this.item = null; this.origin = null; this.placement = 'none'; this.opacity = 1; this.faded = 0
  }
  fadeRetired(step) {
    this.retired = this.retired.filter((entry) => {
      entry.time += step
      const gone = Math.min(1, entry.time / 1.2)
      setOpacity(entry.node, 1 - gone)
      entry.node.scale.setScalar(entry.size * (1 - 0.45 * gone))
      if (gone >= 1) { entry.node.removeFromParent(); return false }
      return true
    })
  }
  spawn(want) {
    this.clear()
    const template = this.models[want.kind]
    if (!template) return
    const node = ownCopy(template)
    node.traverse((n) => { if (n.isMesh) n.castShadow = true })
    node.scale.setScalar(size(want.kind)); node.name = 'pantry-carry'
    this.node = node; this.item = want; this.placement = 'counter'
    if (!this.reducedMotion) this.puff(node, 0.05)
  }
  place(next, parent, position, quaternion) {
    const node = this.node
    if (!node) return
    const changed = this.placement !== next || node.parent !== parent
    if (this.placement !== next) this.phase = 0
    this.placement = next
    this.base = { position, quaternion: quaternion ? quaternion.clone() : new THREE.Quaternion() }
    if (!changed) return
    node.removeFromParent(); parent.add(node)
  }
  /** A short burst of sparkles in the item's colour. */
  puff(node, delay = 0) {
    if (!this.item || !node.parent || !this.particles) return
    const world = node.parent.localToWorld(node.position.clone().add(new THREE.Vector3(0, 0.35, 0)))
    this.particles.burst({ position: world.toArray(), rate: 260, duration: 0.08, wait: delay, life: 0.55, lifeVariation: 0.2,
      velocity: 0.9, velocityVariation: 0.5, spread: 80, acceleration: -1.6, size: 0.035 * 1.4, sizeVariation: 0.015 * 1.4,
      color: puffColors[this.item.kind], colorVariation: [0, 0.1, 0.15] })
  }
}
