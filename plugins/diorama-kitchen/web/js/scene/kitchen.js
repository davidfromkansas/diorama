// The kitchen view (the app's DioramaSceneView): a session's agents appear as chefs working at
// the station that matches their state. It reconciles chefs with agents, paces their moves so
// brief work still shows, runs the break room, the restaurant's diners and the manager, follows
// the selected chef with the camera, and places the station signs, name tags and bubbles.

import * as THREE from 'three'
import { SceneLayout, ChefMetrics, BreakRoomLayout, contains, midX, minY, dist } from './layout.js'
import { ChefAvatar, ownCopy, setOpacity, dishSize, liftHeight } from './avatar.js'
import { BreakRoom, RestaurantGuests, nextVisit, laughing, talking } from './crowd.js'
import { CameraController, followPose, fitDistance, cameraEase } from './camera.js'
import { BurnerFlames, IdleBoards } from './effects.js'
import { strikeGong, swingGong, dishFor } from './room.js'
import { ringBell, hopBell } from './office.js'
import { KitchenActivity, pantryItem, planItem } from '../core/activity.js'
import { ChefTag, tagContent, detectMoments, needsYou, phasePriority, fresh } from '../ui/tags.js'
import { ChefBubble, bubbleSize } from '../ui/bubbles.js'
import { audio } from '../audio.js'

const maxResting = 6, walkOff = 25, catchUpWindow = 1.5, deselectGrace = 0.25, holdDelay = 0.25
const dinerCount = 12, dinerLinger = 8
const scale = ChefMetrics.chefScale
/** The scene's clock in seconds; tests move it on by hand (`skip`). */
export const sceneClock = { skip: 0 }
export const seconds = () => performance.now() / 1000 + sceneClock.skip
const needsAttention = (agent) => agent.status === 'waiting' && agent.attentionReason !== 'other'
const sortedKeys = (map) => [...map.keys()].sort()

export class Kitchen {
  /** `built`: buildKitchen's result; `overlay`: the element tags and signs go in. */
  constructor({ renderer, scene, camera, built, assets, particles, overlay, canvas }) {
    Object.assign(this, { renderer, scene, camera, built, assets, particles, overlay, canvas })
    this.navigation = SceneLayout.navigation
    this.slotTable = SceneLayout.chefSlots
    this.kit = {
      food: built.food, particles, workInProgress: built.workInProgress !== false,
      carry: { skill: built.props.salsa_jar, plugin: built.props.plugin_crate, connector: built.props.connector_object, plan: built.props.plan_plate,
        idea: built.props.lightbulb, board: built.props.chopped_board, pot: built.props.stove_pot },
    }
    this.chefs = new Map(); this.agents = new Map(); this.tags = new Map(); this.pacing = new Map(); this.slots = new Map()
    this.departed = new Map(); this.restingSince = new Map(); this.shownChefs = new Set(); this.seen = false
    this.selectedID = null; this.hoveredID = null; this.heldID = null; this.press = null
    this.reduced = matchMedia('(prefers-reduced-motion: reduce)').matches
    this.tagsHidden = false
    this.observedSince = document.visibilityState === 'visible' ? seconds() : null
    this.lastSilenceCheck = 0
    this.breakClock = seconds()
    const durations = Object.fromEntries(Object.entries(assets.manifest.clips).map(([k, v]) => [k, v.duration]))
    this.durations = durations
    this.breakRoom = new BreakRoom(BreakRoomLayout.spots, durations)
    this.bubbles = new Map(); this.lastBubble = new Map(); this.arcadeTime = new Map(); this.arcadeWins = new Map(); this.bubbleCount = 0
    this.manager = null; this.managerVisit = null; this.managerTalking = null; this.managerLeaving = false
    this.gongStrikesSeen = 0
    this.diners = []; this.tablePlates = []; this.served = new Map(); this.cheers = 0
    this.fades = new Map()
    this.elevatorOpen = false
    this.characters = loadCharacters()
    this.freeCamera = new CameraController()
    this.followID = null; this.cameraMoving = false; this.snapCamera = false; this.overviewPose = null; this.cameraPose = null
    this.onSelect = null; this.onCameraMoved = null; this.reportedAway = false
    this.foodIDs = Object.keys(built.food).sort()
    this.effects = built.makeEffects?.() ?? [new BurnerFlames(scene, built.stations.stove, particles), new IdleBoards(built.stations.cooking, built.props.cleaver_board)]
    this.bell = built.bell ?? null; this.atBell = new Set()
    this.gong = built.stations.bell?.userData.gong ?? null
    this.doors = built.stations.elevator?.userData.doors ?? []
    this.makeSigns()
    this.seatDiners()
    this.bindInput()
  }

  get observed() { return document.visibilityState === 'visible' }
  get catchingUp() { return this.observedSince == null || seconds() - this.observedSince < catchUpWindow }
  noteObservation() {
    if (!this.observed) { this.observedSince = null; this.freeCamera.held.clear() }
    else if (this.observedSince == null) { this.observedSince = seconds(); this.catchUp() }
  }

  // MARK: Characters

  character(id) {
    const available = this.assets.characters.map((c) => c.id)
    const key = `${this.scope ?? ''}:${id}`
    const existing = this.characters[key]
    if (existing && available.includes(existing)) return existing
    const worn = new Map()
    for (const chef of this.chefs.values()) worn.set(chef.character, (worn.get(chef.character) ?? 0) + 1)
    const fewest = Math.min(...available.map((c) => worn.get(c) ?? 0))
    const options = available.filter((c) => (worn.get(c) ?? 0) === fewest)
    const choice = options[Math.floor(Math.random() * options.length)]
    this.characters[key] = choice
    saveCharacters(this.characters)
    return choice
  }

  makeChef(id, character) {
    const chef = new ChefAvatar(id, this.assets.instance(character), this.assets, this.navigation, this.kit, scale)
    chef.character = character
    chef.director.reducedMotion = this.reduced
    return chef
  }

  // MARK: Slots and intents

  /** Spots are owned: a chef keeps its spot until it sets off, and claims a free one (else a queue place) when it leaves. */
  claimSlot(id, area) {
    const current = this.slots.get(id)
    if (current && current.area === area) return current
    const taken = new Set([...this.slots].filter(([k]) => k !== id).map(([, v]) => v.id))
    const options = this.slotTable[area] ?? []
    const free = options.find((o) => !taken.has(o.id))
    if (free) { this.slots.set(id, free); return free }
    if (!options.length) return null
    let n = 0
    while (taken.has(`${options[n % options.length].id}~${n}`)) n += 1
    const base = options[n % options.length], back = (Math.floor(n / options.length) + 1) * 0.95 * scale
    const queued = { id: `${base.id}~${n}`, area, stand: [base.stand[0] - Math.sin(base.facing) * back, base.stand[1] - Math.cos(base.facing) * back], facing: base.facing }
    this.slots.set(id, queued)
    return queued
  }

  wanted(id, claim, restored = false) {
    const state = this.pacing.get(id), chef = this.chefs.get(id)
    if (!state || !chef) return null
    const work = SceneLayout.work(state.agent)
    let slot = null
    if (work.area === 'break') {
      this.breakRoom.join(id, this.breakClock)
      slot = this.breakRoom.station(id)
      if (claim && slot) this.slots.set(id, slot)
    } else if (work.area) {
      const current = this.slots.get(id)
      if (current && current.area === work.area) slot = current
      else if (claim) slot = this.claimSlot(id, work.area)
      else slot = { id: 'pending:' + work.area, area: work.area, stand: [0, 0], facing: 0 }
    }
    const here = chef.director.station
    const pickup = here && ['cooking', 'stove', 'prep', 'tasting'].includes(here.area) ? here : null
    let intent = SceneLayout.intent(state.agent, slot, pickup, restored)
    const visit = this.managerVisit, station = intent.station
    if (this.managerTalking === id && visit && station && station.area === 'bell' && !station.id.startsWith('pending:')) {
      const toward = [visit.spot.stand[0] - station.stand[0], visit.spot.stand[1] - station.stand[1]]
      intent = { ...intent, station: { ...station, facing: Math.atan2(toward[0], toward[1]) }, loop: 'talk_reply', key: intent.key + '|talk' }
    }
    if (intent.station?.area === 'break' && this.breakRoom.members.has(id)) intent = this.breakIntent(intent, this.breakRoom.members.get(id), this.breakRoom.kind(id))
    return intent
  }

  /** A resting chef's intent at its break-room spot: the room's clip, and at a machine its gesture and what it then holds. */
  breakIntent(base, member, kind) {
    const intent = { ...base }
    const restored = base.oneShot?.restored ?? false
    intent.loop = member.clip || 'idle_available'
    if (kind === 'arcade' || kind.startsWith('circle')) { intent.hand = null; intent.oneShot = null }
    else if (kind === 'vending' || kind === 'espresso') {
      const gesture = kind === 'vending' ? 'use_vending' : 'brew_espresso'
      intent.hand = kind === 'vending' ? 'can' : 'mug'
      intent.oneShot = { id: `${gesture}:${member.since}`, clip: gesture, restored }
    } else if (kind === 'chair') intent.hand = member.clip === 'sit_sip' ? 'mug' : null
    intent.key = ['break', intent.station?.id ?? '', intent.loop, intent.hand ?? '', intent.oneShot?.id ?? ''].join('|')
    return intent
  }

  /** The visit owed for brief work (a test run, a skill fetched), whatever the agent does by now. */
  owedIntent(id, area) {
    const base = this.pacing.get(id)?.agent
    if (!base) return null
    const agent = { ...base, status: 'working', turnHasEdits: true }
    const work = agent.turnWork ?? {}
    if (area === 'pantry') { agent.latestTool = 'Skill'; agent.latestToolDetail = work.resources?.at(-1) ?? '' }
    else if (area === 'cooking') { agent.latestTool = 'Edit'; agent.latestToolDetail = work.files?.at(-1) ?? '' }
    else if (area === 'stove') { agent.latestTool = 'Bash'; agent.latestToolDetail = 'npm run build' }
    else { agent.latestTool = 'Bash'; agent.latestToolDetail = work.tests?.at(-1)?.command ?? 'npm test' }
    return SceneLayout.intent(agent, this.claimSlot(id, area), null, false)
  }

  queuedWithFreeSpot(id) {
    const slot = this.slots.get(id)
    if (!slot || !slot.id.includes('~')) return false
    const taken = new Set([...this.slots].filter(([k]) => k !== id).map(([, v]) => v.id))
    return (this.slotTable[slot.area] ?? []).some((o) => !taken.has(o.id))
  }

  // MARK: Reconciling

  /** Reconcile chefs with agents: everyone with work in hand, plus the most recent resters. */
  apply(agents) {
    const now = seconds()
    this.noteObservation()
    const rank = (agent) => {
      if (needsAttention(agent)) return 0
      if (agent.status === 'working') return 1
      const area = SceneLayout.work(agent).area
      return area === 'serving' ? 2 : area === 'break' ? 3 : 4
    }
    const recency = (agent) => agent.meaningfulUpdatedAt ?? agent.observedAt ?? 0
    const sorted = agents.map((agent, offset) => ({ rank: rank(agent), offset, agent })).sort((a, b) => a.rank - b.rank || a.offset - b.offset)
    const busy = sorted.filter((e) => e.rank !== 3)
    for (const entry of sorted) {
      if (entry.rank !== 3) this.restingSince.delete(entry.agent.id)
      else if (!this.restingSince.has(entry.agent.id) && this.chefs.has(entry.agent.id)) this.restingSince.set(entry.agent.id, now)
    }
    const listed = new Set(agents.map((a) => a.id))
    for (const id of [...this.restingSince.keys()]) if (!listed.has(id)) this.restingSince.delete(id)
    const walking = sorted.filter((e) => e.rank === 3 && this.chefs.has(e.agent.id) && now - (this.restingSince.get(e.agent.id) ?? -Infinity) < walkOff)
    const walkingIDs = new Set(walking.map((e) => e.agent.id))
    const idle = sorted.filter((e) => e.rank === 3 && !walkingIDs.has(e.agent.id))
      .sort((a, b) => recency(b.agent) - recency(a.agent) || a.offset - b.offset)
    const resting = [...walking, ...idle.slice(0, Math.max(0, maxResting - walking.length))]
    const ranked = [...busy, ...resting].map((e) => e.agent)
    const ids = new Set(ranked.map((a) => a.id))
    for (const id of [...this.chefs.keys()]) {
      if (ids.has(id)) continue
      const chef = this.chefs.get(id)
      this.departed.set(id, { position: chef.director.position, heading: chef.director.heading })
      if (this.heldID === id) this.heldID = null
      chef.root.removeFromParent()
      this.chefs.delete(id)
      this.tags.get(id)?.remove(); this.tags.delete(id)
      this.agents.delete(id); this.slots.delete(id); this.pacing.delete(id)
    }
    const catching = this.catchingUp
    for (const agent of ranked) {
      this.agents.set(agent.id, agent)
      const counts = { testsSeen: agent.turnWork?.tests?.length ?? 0, resourcesSeen: agent.turnWork?.resources?.length ?? 0, filesSeen: agent.turnWork?.files?.length ?? 0 }
      if (!this.chefs.has(agent.id)) {
        const chef = this.makeChef(agent.id, this.character(agent.id))
        chef.dish = dishFor(agent.completionKey ?? agent.id, this.foodIDs)
        chef.pantryItem = pantryItem(agent); chef.prepItem = planItem(agent)
        this.chefs.set(agent.id, chef)
        // Only agents that start while someone watches ride the elevator in.
        const returning = this.shownChefs.has(agent.id) || agent.latestRequest != null
        this.shownChefs.add(agent.id)
        const arriving = !returning && !catching && this.seen && fresh(agent)
        const door = this.slotTable.elevator?.[0]
        if (arriving && door && this.claimSlot(agent.id, 'order')) {
          chef.director.place(door.stand, door.facing)
          chef.director.setIntent(SceneLayout.exitIntent(agent.id))
          this.pacing.set(agent.id, { agent, want: null, arrivedAt: null, arriving: true, exiting: true, owed: [], ...counts })
          this.moveElevatorDoors(true)
        } else if (!catching && this.departed.has(agent.id)) {
          const spot = this.departed.get(agent.id), area = SceneLayout.work(agent).area
          const slot = area ? (area === 'break' ? null : this.claimSlot(agent.id, area)) : null
          chef.director.place(spot.position, spot.heading)
          this.pacing.set(agent.id, { agent, want: null, arrivedAt: null, arriving: false, exiting: false, owed: [], ...counts })
          chef.director.setIntent(area === 'break' ? this.wanted(agent.id, true) : SceneLayout.intent(agent, slot, null, false))
          this.pacing.get(agent.id).want = chef.director.intent
        } else {
          // Chefs shown from history start in place: no walk-in, no replayed gesture.
          const area = SceneLayout.work(agent).area
          this.pacing.set(agent.id, { agent, want: null, arrivedAt: null, arriving: false, exiting: false, owed: [], ...counts })
          let intent
          if (area === 'break') intent = this.wanted(agent.id, true, true)
          else intent = SceneLayout.intent(agent, area ? this.claimSlot(agent.id, area) : null, null, true)
          const home = this.slotTable.break ?? []
          const spawn = intent?.station ?? (home.length ? home[this.chefs.size % home.length] : null)
          if (spawn) chef.director.place(spawn.stand, spawn.facing)
          chef.director.setIntent(intent)
          this.pacing.get(agent.id).want = chef.director.intent
        }
        chef.update(0)
        this.scene.add(chef.root)
        if (this.selectedID && this.selectedID !== agent.id) this.fadeChef(chef, 0.4, true)
        const tag = new ChefTag(this.overlay)
        tag.root.dataset.agent = agent.id
        tag.announce = (text) => this.announce(text)
        this.tags.set(agent.id, tag)
      } else {
        const state = this.pacing.get(agent.id), chef = this.chefs.get(agent.id)
        if (!catching && fresh(agent) && state) {
          const moments = detectMoments(state.agent, agent)
          if (moments.length) this.tags.get(agent.id)?.react(moments)
        }
        chef.director.reducedMotion = this.reduced
        chef.dish = dishFor(agent.completionKey ?? agent.id, this.foodIDs)
        chef.pantryItem = pantryItem(agent); chef.prepItem = planItem(agent)
        state.agent = agent
        // Brief work still gets its station: tasting for each new test run, the pantry for each
        // skill fetched, the cooking station for files edited, however quickly the agent moves on.
        if (!catching && agent.status === 'working' && fresh(agent)) {
          if (counts.resourcesSeen > state.resourcesSeen && !state.owed.includes('pantry')) state.owed.push('pantry')
          if (counts.filesSeen > state.filesSeen && !state.owed.includes('cooking')) {
            const at = state.owed.indexOf('tasting')
            state.owed.splice(at < 0 ? state.owed.length : at, 0, 'cooking')
          }
          if (counts.testsSeen > state.testsSeen) {
            const last = agent.turnWork.tests.at(-1)
            const steps = last ? KitchenActivity.stations(last.command) : []
            const areas = steps.map((s) => (s === 'testing' || s === 'checking' ? 'tasting' : s === 'commands' ? 'stove' : null)).filter(Boolean)
            for (const area of areas.length ? areas : ['tasting']) if (!state.owed.includes(area)) state.owed.push(area)
          }
        }
        Object.assign(state, counts)
        if (!state.arriving) state.want = this.wanted(agent.id, false)
      }
      this.tags.get(agent.id)?.update(tagContent(agent), this.reduced)
    }
    this.seen = true
    this.pace(now)
    if (this.catchingUp) this.catchUp()
    this.updateManager()
    this.syncSelection()
    this.updateEffects()
    this.placeChefLabels()
  }

  /** Applies wanted intents: urgent ones at once, others after the chef has worked at its station for the minimum dwell. */
  pace(now) {
    for (const id of sortedKeys(this.chefs)) {
      const chef = this.chefs.get(id), state = this.pacing.get(id)
      if (!chef || chef.held || !state) continue
      const director = chef.director
      if (director.station && state.arrivedAt == null) state.arrivedAt = now
      const settledFor = state.arrivedAt != null ? now - state.arrivedAt : 0
      const walking = !!director.intent?.station && !director.station
      let apply = false, promote = false
      if (!['working', 'done', 'ready'].includes(state.agent.status)) state.owed = []
      if (state.owed.length && !state.arriving) {
        const owedArea = state.owed[0]
        if (state.want?.station?.area === 'bell' || (state.want?.urgent && !state.want?.station)) state.owed = []
        else if (director.intent?.station?.area === owedArea) {
          if (director.station && settledFor >= ChefMetrics.minimumDwell) state.owed.shift()
          continue
        } else if (!walking && (!director.intent?.station || settledFor >= ChefMetrics.minimumDwell)) {
          const next = this.owedIntent(id, owedArea)
          if (next) { director.setIntent(next); state.arrivedAt = null }
          continue
        } else continue
      }
      if (state.arriving && state.exiting) {
        const order = this.slots.get(id)
        if (director.station?.id === SceneLayout.elevatorLanding.id && settledFor >= ChefMetrics.arrivalWave && order?.area === 'order') {
          director.setIntent(SceneLayout.arrivalIntent(order))
          state.exiting = false; state.arrivedAt = null
        }
        continue
      }
      if (state.arriving) {
        apply = state.arrivedAt != null && settledFor >= ChefMetrics.orderReading
        if (apply) state.arriving = false
      } else if (state.want && state.want.key !== director.intent?.key) {
        apply = state.want.urgent || !director.intent?.station || (!walking && settledFor >= ChefMetrics.minimumDwell)
      } else if (!walking && settledFor >= ChefMetrics.minimumDwell && this.queuedWithFreeSpot(id)) {
        apply = true; promote = true
      }
      if (apply) {
        if (promote) this.slots.delete(id)
        const next = this.wanted(id, true)
        if (next) {
          // Work that leaves the serving window for the break room was accepted: celebrate.
          if (next.station?.area === 'break' && director.intent?.station?.area === 'serving') next.prelude = 'celebrate_done'
          director.setIntent(next)
          state.arrivedAt = null
        }
        state.want = this.wanted(id, false)
      }
    }
  }

  /** Jump every chef to where its agent's state puts it: no walk, no replayed gesture. */
  catchUp() {
    const now = seconds()
    for (const id of sortedKeys(this.chefs)) {
      const chef = this.chefs.get(id), state = this.pacing.get(id)
      if (!chef || chef.held || !state) continue
      const director = chef.director
      state.arriving = false; state.exiting = false; state.owed = []
      const walking = !!director.intent?.station && !director.station
      if (!(walking || state.want?.key !== director.intent?.key || this.queuedWithFreeSpot(id))) continue
      if (this.queuedWithFreeSpot(id)) this.slots.delete(id)
      const next = this.wanted(id, true, true)
      if (!next) continue
      if (next.station) director.place(next.station.stand, next.station.facing)
      director.setIntent(next, true)
      state.want = this.wanted(id, false)
      state.arrivedAt = now - ChefMetrics.minimumDwell
    }
  }

  updateEffects() {
    const snapshot = [...this.chefs.values()].map((chef) => ({ station: chef.director.station, clip: chef.director.clip.name, position: chef.director.position, choppingOnBoard: chef.choppingOnBoard }))
    for (const effect of this.effects) effect.update(snapshot, this.reduced)
  }

  // MARK: Elevator

  moveElevatorDoors(open) {
    if (open === this.elevatorOpen) return
    this.elevatorOpen = open
    const now = seconds()
    for (const d of this.doors) d.tween = { from: d.door.position.x, to: d.closed + (open ? d.slide : 0), start: now }
  }
  updateElevator(now) {
    if (this.elevatorOpen && ![...this.pacing.values()].some((s) => s.arriving && (s.exiting || s.arrivedAt == null))) this.moveElevatorDoors(false)
    for (const d of this.doors) {
      if (!d.tween) continue
      const p = Math.min(1, (now - d.tween.start) / 0.6), e = p < 0.5 ? 2 * p * p : 1 - (-2 * p + 2) ** 2 / 2
      d.door.position.x = d.tween.from + (d.tween.to - d.tween.from) * e
      if (p >= 1) d.tween = null
    }
  }

  // MARK: Frame

  frame(time, delta) {
    const now = seconds()
    this.noteObservation()
    if (this.freeCamera.held.size && !this.selectedID) { this.freeCamera.step(delta); this.applyFreeCamera() }
    this.pace(now)
    this.updateManager()
    this.updateGong(now)
    this.updateBreakRoom(now)
    this.serveDiners(now)
    const step = Math.min(0.1, delta)
    for (const chef of this.allChefs()) chef.update(step)
    this.updateFades(now)
    this.playSounds()
    this.updateEffects()
    this.updateElevator(now)
    this.stepCamera(step)
    this.noticeSilence()
    this.placeChefLabels()
    this.placeBubbles(now)
    this.updateRing(now)
  }
  allChefs() { return [...this.chefs.values(), ...this.diners, ...(this.manager ? [this.manager] : [])] }

  /** Once a second, working tags catch up with the clock: a quiet agent turns to thinking, the times count up. */
  noticeSilence() {
    const time = seconds()
    if (time - this.lastSilenceCheck < 1 || this.catchingUp) return
    this.lastSilenceCheck = time
    for (const [id, agent] of this.agents) if (fresh(agent) && agent.status === 'working') this.tags.get(id)?.update(tagContent(agent), this.reduced)
  }

  /** Plays the sounds chefs cued this frame, panned to where each stands on screen, quieter out of frame. */
  playSounds() {
    const audible = this.observedSince != null && seconds() >= this.observedSince + catchUpWindow
    const width = this.canvas.clientWidth
    for (const chef of this.allChefs()) {
      if (!chef.heard.length) continue
      const sounds = chef.heard; chef.heard = []
      const spot = chef.director.position
      const resting = chef.director.station?.area === 'break' || contains(SceneLayout.loungeArea, spot)
      if (!audible || !width || resting) continue
      const point = this.project(chef.root.position)
      const x = point ? point.x / width : -1
      const inFrame = point && x >= 0 && x <= 1
      for (const sound of sounds) audio.play(sound, x * 2 - 1, inFrame ? 1 : 0.35)
    }
  }

  // MARK: Fading

  fadeChef(chef, to, instant = false) {
    if (instant || this.reduced) { this.fades.delete(chef); chef.setOpacity(to); return }
    if (chef.opacity === to && !this.fades.has(chef)) return
    this.fades.set(chef, { from: chef.opacity, to, start: seconds(), duration: 0.25 })
  }
  updateFades(now) {
    for (const [chef, f] of this.fades) {
      const p = Math.min(1, (now - f.start) / f.duration)
      chef.setOpacity(f.from + (f.to - f.from) * p)
      if (p >= 1) { this.fades.delete(chef); f.done?.() }
    }
  }

  // MARK: Camera

  project(point) {
    const v = new THREE.Vector3(point.x ?? point[0], point.y ?? point[1], point.z ?? point[2]).project(this.camera)
    if (v.z > 1) return null
    const w = this.canvas.clientWidth, h = this.canvas.clientHeight
    return { x: (v.x + 1) / 2 * w, y: (1 - v.y) / 2 * h }
  }

  /** Frames the stations (and, in a wide window, the restaurant's tables) in the home view. */
  fit() {
    const w = this.canvas.clientWidth, h = this.canvas.clientHeight
    if (!(w > 1 && h > 1)) return
    this.camera.aspect = w / h; this.camera.updateProjectionMatrix()
    this.particles.resize(h)
    const points = []
    for (const a of SceneLayout.areas) {
      const station = this.built.stations[a.id]
      if (!station) continue
      for (const node of a.id === 'break' ? station.children : [station]) {
        const box = new THREE.Box3().setFromObject(node)
        if (box.isEmpty()) continue
        for (const x of [box.min.x, box.max.x]) for (const y of [box.min.y, box.max.y]) for (const z of [box.min.z, box.max.z]) points.push([x, y, z])
      }
    }
    if (w / h >= 1.5) for (const seat of this.built.seats) points.push(seat.dish)
    points.push(...(this.built.framePoints ?? []))
    const center = this.built.homeCenter ?? [0, 0]
    this.freeCamera.setHome(center, fitDistance(points.map(([x, y, z]) => [x - center[0], y, z - center[1]]), w, h))
    this.overviewPose = { eye: this.freeCamera.eye, look: this.freeCamera.look }
    const following = this.followID || this.cameraMoving || !this.freeCamera.isHome
    if (!following) { this.cameraPose = this.overviewPose; this.applyPose(this.cameraPose) }
    this.syncSelection()
  }
  applyPose(pose) {
    this.camera.position.set(...pose.eye); this.camera.lookAt(...pose.look); this.camera.updateMatrixWorld()
  }
  applyFreeCamera() {
    this.overviewPose = { eye: this.freeCamera.eye, look: this.freeCamera.look }
    this.cameraMoving = true; this.snapCamera = this.reduced
    const away = !this.freeCamera.isHome
    if (away !== this.reportedAway) { this.reportedAway = away; this.onCameraMoved?.(away) }
    this.syncSelection()
  }
  resetCamera() { this.freeCamera.reset(); this.applyFreeCamera() }
  stepCamera(delta) {
    if (!this.overviewPose) return
    const followed = this.followID ? this.chefs.get(this.followID) : null
    const target = followed ? followPose(followed.root.position) : this.overviewPose
    if (!this.cameraMoving && !this.followID) return
    const pose = this.cameraPose ?? this.overviewPose
    const blend = this.snapCamera ? 1 : 1 - Math.exp(-delta / cameraEase)
    const mix = (a, b) => a.map((v, i) => v + (b[i] - v) * blend)
    let next = { eye: mix(pose.eye, target.eye), look: mix(pose.look, target.look) }
    const close = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]) < 0.01
    const arrived = close(next.eye, target.eye) && close(next.look, target.look)
    if (arrived) next = { eye: [...target.eye], look: [...target.look] }
    this.cameraPose = next
    this.applyPose(next)
    if (!this.followID && arrived) { this.cameraMoving = false; this.snapCamera = false; this.syncSelection() }
  }

  // MARK: Selection

  setSelection(id, immediately = false) {
    if (id == null && this.selectedID != null && !immediately) {
      if (this.pendingDeselect) return
      this.pendingDeselect = setTimeout(() => { this.pendingDeselect = null; this.selectedID = null; this.syncSelection(); this.onSelect?.(null) }, deselectGrace * 1000)
      return
    }
    clearTimeout(this.pendingDeselect); this.pendingDeselect = null
    if (id === this.selectedID) return
    this.selectedID = id
    this.syncSelection()
    this.onSelect?.(id)
  }

  syncSelection() {
    const chef = this.selectedID ? this.chefs.get(this.selectedID) : null
    const previous = this.followID
    this.followID = chef ? this.selectedID : null
    if (this.followID !== previous) { this.cameraMoving = true; this.snapCamera = this.reduced }
    for (const [id, other] of this.chefs) this.fadeChef(other, !this.selectedID || id === this.selectedID ? 1 : 0.4)
    if (chef && this.freeCamera.held.size) this.freeCamera.held.clear()
    if (chef) {
      this.ring ??= makeSelectionRing()
      if (!this.ring.parent) this.scene.add(this.ring)
      this.ring.position.copy(chef.root.position)
    } else this.ring?.removeFromParent()
    const overview = !chef && !this.cameraMoving && this.freeCamera.isHome
    this.signLayer.style.display = overview ? '' : 'none'
    if (overview) this.placeSigns()
    this.placeChefLabels()
  }
  updateRing(now) {
    if (!this.ring?.parent) return
    const chef = this.chefs.get(this.selectedID)
    if (chef) this.ring.position.set(chef.root.position.x, 0, chef.root.position.z)
    if (this.reduced) return
    this.ring.rotation.y = -now / 7 * Math.PI * 2
    this.ring.children[0].material.opacity = 0.8 + 0.2 * Math.cos(now / 1.8 * Math.PI * 2)
  }

  // MARK: Name tags

  placeChefLabels() {
    const placed = []
    const w = this.canvas.clientWidth, h = this.canvas.clientHeight
    const priority = (id) => {
      const phase = this.tags.get(id)?.content?.phase
      if (!phase) return 5
      if (needsYou(phase)) return 0
      return id === this.selectedID ? 1 : phasePriority(phase)
    }
    const order = [...this.chefs.keys()].map((id) => ({ id, priority: priority(id) })).sort((a, b) => a.priority - b.priority || (a.id < b.id ? -1 : 1))
    const clashes = (f) => placed.find((p) => p.x - 2 < f.x + f.w && f.x < p.x + p.w + 2 && p.y - 1 < f.y + f.h && f.y < p.y + p.h + 1)
    const frameAt = (size, point, above) => {
      const x = Math.min(Math.max(4, point.x - size.w / 2), Math.max(4, w - size.w - 4))
      const y = above ? point.y - size.h : point.y
      return { x, y: Math.min(Math.max(4, y), Math.max(4, h - size.h - 4)), w: size.w, h: size.h }
    }
    for (const { id } of order) {
      const tag = this.tags.get(id), chef = this.chefs.get(id)
      if (!tag || !chef) continue
      if (this.heldID === id || this.tagsHidden) { tag.setHidden(true); continue }
      const selected = this.selectedID === id, hovered = this.hoveredID === id
      if (!this.selectedID && tag.content?.resting && !hovered) { tag.setHidden(true); continue }
      const position = chef.root.position
      const point = this.project({ x: position.x, y: position.y + 2.05 * scale, z: position.z })
      if (!point || point.x < -24 || point.y < -24 || point.x > w + 24 || point.y > h + 24) { tag.setHidden(true); continue }
      let mode = this.selectedID && !selected && !needsYou(tag.content?.phase) ? 'compact' : 'full'
      let frame = frameAt(tag.size(mode, selected, hovered), point, true)
      if (clashes(frame) && !selected && !hovered) {
        const feet = this.project(position)
        if (feet) { mode = 'compact'; frame = frameAt(tag.size(mode, false, false), feet, false) }
      }
      const start = frame.y + frame.h / 2
      for (let clash = clashes(frame), guard = 0; clash && guard < 50; clash = clashes(frame), guard++) frame.y = clash.y + clash.h + 2
      if (!selected && !hovered && Math.abs(frame.y + frame.h / 2 - start) > frame.h * 3) { tag.setHidden(true); continue }
      placed.push(frame)
      tag.setHidden(false)
      tag.present(mode, selected, hovered)
      tag.place(frame)
    }
  }

  // MARK: Station signs

  makeSigns() {
    this.signLayer = document.createElement('div'); this.signLayer.className = 'signs'
    this.leaders = document.createElementNS('http://www.w3.org/2000/svg', 'svg'); this.leaders.classList.add('leaders')
    this.leaderPath = document.createElementNS('http://www.w3.org/2000/svg', 'path'); this.leaders.appendChild(this.leaderPath)
    this.signLayer.appendChild(this.leaders)
    this.signs = SceneLayout.areas.map((a) => {
      const sign = document.createElement('div'); sign.className = 'sign'; sign.textContent = a.short; sign.title = a.label
      sign.setAttribute('aria-label', a.label)
      this.signLayer.appendChild(sign)
      return { area: a, sign, width: Math.min(150, Math.ceil(measureSign(a.short)) + 18) }
    })
    this.overlay.appendChild(this.signLayer)
  }
  placeSigns() {
    const occupied = [], height = 18, W = this.canvas.clientWidth, H = this.canvas.clientHeight
    let path = ''
    for (const { area, sign, width } of this.signs) {
      const spot = area.id === 'break' ? SceneLayout.restSign : area.footprint
      const anchor = this.project([midX(spot), 2.6, minY(spot)])
      if (!anchor) { sign.style.display = 'none'; continue }
      sign.style.display = ''
      const candidate = (offset) => ({
        x: Math.min(Math.max(8, anchor.x - width / 2), Math.max(8, W - width - 8)),
        y: Math.min(Math.max(8, anchor.y + offset - height / 2), Math.max(8, H - height - 8)), w: width, h: height,
      })
      let frame = candidate(0)
      for (let step = 0; step < 20; step++) {
        const offset = Math.floor((step + 1) / 2) * (height + 6) * (step % 2 === 0 ? -1 : 1)
        const proposed = candidate(offset)
        if (!occupied.some((o) => o.x - 4 < proposed.x + proposed.w && proposed.x < o.x + o.w + 4 && o.y - 4 < proposed.y + proposed.h && proposed.y < o.y + o.h + 4)) { frame = proposed; break }
      }
      occupied.push(frame)
      sign.style.transform = `translate(${Math.round(frame.x)}px, ${Math.round(frame.y)}px)`; sign.style.width = width + 'px'
      path += `M${anchor.x.toFixed(1)} ${anchor.y.toFixed(1)}L${(frame.x + width / 2).toFixed(1)} ${(frame.y + height / 2).toFixed(1)}`
    }
    this.leaderPath.setAttribute('d', path)
  }

  // MARK: Pointer

  bindInput() {
    const canvas = this.canvas
    this.raycaster = new THREE.Raycaster()
    canvas.addEventListener('pointermove', (e) => {
      if (this.heldID) { this.carry(e); return }
      if (this.press && Math.hypot(e.clientX - this.press.x, e.clientY - this.press.y) > 4) { this.pickUp(e); return }
      const found = this.chefAt(e)
      if (found !== this.hoveredID) { this.hoveredID = found; canvas.style.cursor = found ? 'pointer' : ''; this.placeChefLabels() }
    })
    canvas.addEventListener('pointerleave', () => { if (this.hoveredID) { this.hoveredID = null; this.placeChefLabels() } })
    canvas.addEventListener('pointerdown', (e) => {
      audio.unlock()
      if (e.button !== 0) return
      clearTimeout(this.press?.timer); this.press = null
      const id = this.chefAt(e)
      if (!id || this.heldID) return
      canvas.setPointerCapture(e.pointerId)
      this.press = { id, x: e.clientX, y: e.clientY, timer: setTimeout(() => this.pickUp(this.lastPointer ?? e), holdDelay * 1000) }
    })
    canvas.addEventListener('pointermove', (e) => { this.lastPointer = e })
    canvas.addEventListener('pointerup', (e) => {
      clearTimeout(this.press?.timer)
      const pressed = this.press; this.press = null
      if (this.heldID) { this.drop(); return }
      if (e.button !== 0) return
      const id = pressed?.id ?? this.chefAt(e)
      if (id && this.agents.has(id)) { this.setSelection(this.selectedID === id ? null : id, this.selectedID === id); return }
      if (this.selectedID) this.setSelection(null, true)
    })
    this.overlay.addEventListener('click', (e) => {
      const tag = e.target.closest?.('.tag')
      if (!tag) return
      const id = tag.dataset.agent
      if (id && this.agents.has(id)) { audio.unlock(); if (this.selectedID === id) this.onOpen?.(id); else this.setSelection(id) }
    })
    canvas.addEventListener('wheel', (e) => {
      if (this.selectedID || e.ctrlKey || e.metaKey || e.altKey || e.shiftKey) return
      e.preventDefault()
      const delta = e.deltaMode === 1 ? -e.deltaY * 8 : -e.deltaY
      if (!delta) return
      this.freeCamera.scroll(delta)
      this.applyFreeCamera()
    }, { passive: false })
    const keys = { ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right', q: 'turnLeft', w: 'turnRight' }
    const handle = (e) => {
      if (this.heldID && e.key === 'Escape') { if (e.type === 'keydown') this.drop(true); e.preventDefault(); return }
      if (e.metaKey || e.ctrlKey || e.altKey) return
      if (e.target.closest?.('input, textarea, [contenteditable]')) return
      const down = e.type === 'keydown', key = e.key.length === 1 ? e.key.toLowerCase() : e.key
      if (key === 'Escape' && down && this.selectedID) { this.setSelection(null, true); return }
      if (key === 'r') { if (down && !e.repeat && !this.freeCamera.isHome) { this.resetCamera(); e.preventDefault() } return }
      if (key === 'a') { if (down && !e.repeat) { this.tagsHidden = !this.tagsHidden; this.placeChefLabels() } return }
      const action = keys[key]
      if (!action || this.selectedID) return
      if (['up', 'down', 'left', 'right'].includes(action) && !this.freeCamera.isZoomedIn) return
      e.preventDefault()
      if (down) this.freeCamera.held.add(action); else this.freeCamera.held.delete(action)
    }
    addEventListener('keydown', handle); addEventListener('keyup', handle)
    addEventListener('blur', () => { this.freeCamera.held.clear(); if (this.heldID) this.drop(true) })
  }

  ray(e) {
    const rect = this.canvas.getBoundingClientRect()
    const ndc = new THREE.Vector2((e.clientX - rect.left) / rect.width * 2 - 1, -((e.clientY - rect.top) / rect.height) * 2 + 1)
    this.raycaster.setFromCamera(ndc, this.camera)
    return this.raycaster
  }
  /** The chef under the pointer: its body, generously (a box around it), so small chefs are easy to pick. */
  chefAt(e) {
    const ray = this.ray(e).ray
    let best = null, bestDistance = Infinity
    const box = new THREE.Box3(), hit = new THREE.Vector3()
    for (const [id, chef] of this.chefs) {
      const p = chef.root.position
      box.min.set(p.x - 0.35 * scale, p.y, p.z - 0.35 * scale); box.max.set(p.x + 0.35 * scale, p.y + 1.75 * scale, p.z + 0.35 * scale)
      if (!ray.intersectBox(box, hit)) continue
      const d = hit.distanceTo(ray.origin)
      if (d < bestDistance) { bestDistance = d; best = id }
    }
    return best
  }
  /** Where a pointer's ray crosses the horizontal plane at `y` (world x, z). */
  floorRay(e, y) {
    const ray = this.ray(e).ray
    if (Math.abs(ray.direction.y) < 0.00001) return null
    const t = (y - ray.origin.y) / ray.direction.y
    if (t <= 0) return null
    return [ray.origin.x + ray.direction.x * t, ray.origin.z + ray.direction.z * t]
  }
  grabPoint(e) {
    const hit = this.floorRay(e, (liftHeight + 1.7) * scale)
    if (!hit) return null
    const f = SceneLayout.floor
    return [Math.max(-f.w, Math.min(f.w, hit[0])), Math.max(-f.h, Math.min(f.h, hit[1]))]
  }
  /** Lifts the pressed chef: it squirms in the grip and its tag hides. */
  pickUp(e) {
    const press = this.press
    if (!press) return
    clearTimeout(press.timer); this.press = null
    const chef = this.chefs.get(press.id)
    if (!chef) return
    this.heldID = press.id
    const start = chef.director.position
    chef.held = { target: this.grabPoint(e) ?? start, point: [...start], time: 0, swing: [0, 0] }
    this.hoveredID = null
    this.canvas.style.cursor = 'grabbing'
    this.placeChefLabels()
    audio.play('grab', press.x / Math.max(1, this.canvas.clientWidth) * 2 - 1)
  }
  carry(e) {
    const chef = this.chefs.get(this.heldID)
    const target = chef && this.grabPoint(e)
    if (target) chef.held.target = target
  }
  /** Puts the held chef down on the nearest free floor, from where it walks back to its work. */
  drop() {
    const id = this.heldID, chef = this.chefs.get(id)
    this.heldID = null; this.canvas.style.cursor = ''
    if (!chef) return
    const spot = chef.held?.point ?? chef.director.position
    const f = SceneLayout.floor, half = [f.w / 2 - 0.3, f.h / 2 - 0.3]
    const inside = [Math.max(-half[0], Math.min(half[0], spot[0])), Math.max(-half[1], Math.min(half[1], spot[1]))]
    chef.release(this.freeFloor(inside))
    const point = this.project([spot[0], 0, spot[1]])
    audio.play('plate', point ? point.x / Math.max(1, this.canvas.clientWidth) * 2 - 1 : 0, 0.7)
    const state = this.pacing.get(id)
    if (state) state.arrivedAt = null
    this.placeChefLabels()
  }
  freeFloor(point) {
    if (this.navigation.isFree(point)) return point
    for (let ring = 1; ring <= 24; ring++) {
      const r = ring * 0.25
      for (let step = 0; step < ring * 8; step++) {
        const angle = step / (ring * 8) * 2 * Math.PI
        const candidate = [point[0] + Math.cos(angle) * r, point[1] + Math.sin(angle) * r]
        if (this.navigation.isFree(candidate)) return candidate
      }
    }
    return point
  }

  // MARK: Diners

  /** Seats the restaurant's guests at the tables along both sides of the kitchen, each with a plate, chatting. */
  seatDiners() {
    const seats = this.built.seats.slice(0, dinerCount)
    const cast = RestaurantGuests.cast(this.assets.guests.map((g) => g.id), seats.map((s) => s.dish))
    this.guests = new RestaurantGuests(seats.map((s) => s.dish), this.durations)
    const foods = Object.keys(this.built.food).sort()
    seats.forEach((seat, index) => {
      const diner = this.makeChef('diner-' + seat.id, cast[index] ?? 'classic')
      diner.root.name = 'diner:' + seat.id
      diner.silent = true
      diner.director.place(seat.stand, seat.facing)
      diner.director.setIntent(this.dinerIntent(seat, this.guests.seats[index].clip))
      diner.update(0)
      this.scene.add(diner.root)
      this.diners.push(diner)
      const template = foods.length ? this.built.food[foods[(index * 7 + 3) % foods.length]] : null
      if (template) {
        const plate = template.clone()
        plate.scale.setScalar(dishSize * scale * 0.62)
        plate.position.set(seat.dish[0], seat.dish[1] + 0.005, seat.dish[2])
        plate.traverse((n) => { if (n.isMesh) { n.castShadow = true; n.receiveShadow = true } })
        this.scene.add(plate)
        this.tablePlates.push(plate)
      } else this.tablePlates.push(null)
    })
  }
  dinerIntent(seat, clip) {
    const station = { id: 'dining-' + seat.id, area: 'dining', stand: seat.stand, facing: seat.facing }
    const script = this.guests.script
    const hand = clip === script.enjoy ? script.enjoyHand : clip === 'sit_sip' ? 'mug' : null
    if (clip === script.cheer) {
      return { key: ['dining', seat.id, clip, this.cheers].join('|'), station, loop: script.enjoy,
        oneShot: { id: `cheer-${seat.id}-${this.cheers}`, clip, restored: false }, hand: null }
    }
    return { key: ['dining', seat.id, clip].join('|'), station, loop: clip, hand, oneShot: null }
  }
  /** A finished task's dish set on the pass is served to the nearest free diner; once accepted the table clears. */
  serveDiners(now) {
    if (!this.diners.length) return
    const seats = this.built.seats
    const plated = new Map()
    for (const [id, chef] of this.chefs) {
      const agent = this.agents.get(id)
      if (chef.director.placedPlate && agent?.isMain) plated.set(agent.completionKey ?? id, chef.dish ?? '')
    }
    for (const [key, dishID] of [...plated].sort()) {
      const back = this.served.get(key)
      if (back && back.leftAt == null) continue
      if (back) { back.leftAt = null; continue }
      const taken = new Set([...this.served.values()].map((s) => s.seat))
      const seat = this.diners.findIndex((_, i) => !taken.has(i))
      if (seat < 0 || seat >= seats.length) break
      const spot = seats[seat]
      let plate = null
      const template = this.built.food[dishID]
      if (template) {
        plate = template.clone(); plate.scale.setScalar(dishSize * scale * 0.62)
        plate.position.set(spot.dish[0], spot.dish[1] + 0.005, spot.dish[2])
        this.scene.add(plate)
      }
      this.served.set(key, { seat, dish: plate, leftAt: null })
      if (plate && this.tablePlates[seat]) this.tablePlates[seat].visible = false
      this.guests.serve(seat, now); this.cheers += 1
      this.diners[seat].director.setIntent(this.dinerIntent(spot, this.guests.script.cheer))
      const point = this.project(spot.dish)
      if (point && this.observedSince != null) audio.play('clink', point.x / Math.max(1, this.canvas.clientWidth) * 2 - 1, 0.8)
    }
    for (const [key, entry] of [...this.served]) {
      if (plated.has(key)) continue
      if (entry.leftAt == null) { entry.leftAt = now; continue }
      if (now - entry.leftAt <= dinerLinger) continue
      entry.dish?.removeFromParent()
      if (this.tablePlates[entry.seat]) this.tablePlates[entry.seat].visible = true
      this.served.delete(key)
    }
    for (const seat of this.guests.update(now)) {
      if (this.diners[seat] && seats[seat]) this.diners[seat].director.setIntent(this.dinerIntent(seats[seat], this.guests.seats[seat].clip))
    }
  }

  // MARK: Gong and manager

  gongWaiting() {
    const waiting = []
    for (const [id, chef] of this.chefs) {
      const state = this.pacing.get(id)
      if (chef.held || state?.want?.station?.area !== 'bell') continue
      const arrived = chef.director.station?.area === 'bell'
      const visited = id === this.managerVisit?.id && chef.director.intent?.station?.area === 'bell'
      if (arrived || visited) waiting.push({ id, since: state.arrivedAt ?? 0 })
    }
    return waiting
  }

  /** The manager comes in from the dining room when a chef waits at the gong, talks with it until you answer, then leaves. */
  updateManager() {
    const waiting = this.gongWaiting()
    const target = nextVisit(this.managerVisit?.id ?? null, waiting)
    const chef = target ? this.chefs.get(target) : null
    const stand = chef ? (chef.director.intent?.station ?? chef.director.station)?.stand : null
    if (target && chef && stand) {
      const manager = this.manager ?? this.enterManager()
      this.managerLeaving = false
      if (this.managerVisit?.id !== target || dist(this.managerVisit.spot.stand, stand) < 1.0) {
        this.stopTalking()
        const others = waiting.filter((w) => w.id !== target).map((w) => this.chefs.get(w.id)?.director.station?.stand).filter(Boolean)
        others.push(SceneLayout.gongStrike.stand)
        const spot = SceneLayout.managerSpot(stand, others)
        this.managerVisit = { id: target, spot }
        if (this.catchingUp) manager.director.place(spot.stand, spot.facing)
        manager.director.setIntent({ key: 'manager|' + target, station: spot, loop: 'manager_talk', urgent: true })
      }
      if (this.managerTalking !== target && manager.director.station?.id === this.managerVisit?.spot.id) {
        this.managerTalking = target
        const state = this.pacing.get(target)
        if (state) state.want = this.wanted(target, false)
      }
    } else if (this.manager) {
      const manager = this.manager
      this.stopTalking()
      this.managerVisit = null
      if (!this.managerLeaving) {
        this.managerLeaving = true
        manager.director.setIntent({ key: 'manager|leave', station: SceneLayout.managerDoor, loop: 'idle_available', urgent: true })
      } else if (manager.director.station?.id === SceneLayout.managerDoor.id || this.catchingUp) {
        this.manager = null; this.managerLeaving = false
        if (this.catchingUp) manager.root.removeFromParent()
        else { this.fades.set(manager, { from: 1, to: 0, start: seconds(), duration: 0.35, done: () => manager.root.removeFromParent() }) }
      }
    }
  }
  enterManager() {
    const manager = this.makeChef('manager', 'staff:manager')
    manager.root.name = 'staff:manager'
    manager.director.strolls = true
    const door = SceneLayout.managerDoor
    manager.director.place(door.stand, door.facing)
    manager.update(0)
    this.scene.add(manager.root)
    if (!this.catchingUp) { manager.setOpacity(0); this.fades.set(manager, { from: 0, to: 1, start: seconds(), duration: 0.35 }) }
    this.manager = manager
    return manager
  }
  stopTalking() {
    const talking = this.managerTalking
    if (!talking) return
    this.managerTalking = null
    const state = this.pacing.get(talking)
    if (state) state.want = this.wanted(talking, false)
  }
  /** Sets the gong shivering each time a chef's mallet lands on it. */
  updateGong(now) {
    const strikes = [...this.chefs.values()].reduce((sum, c) => sum + c.director.gongStrikes, 0)
    if (strikes > this.gongStrikesSeen && !this.reduced && this.gong) strikeGong(this.gong, now)
    this.gongStrikesSeen = strikes
    if (this.gong) swingGong(this.gong, now)
    if (!this.bell) return
    // The office's desk bell rings as each teammate who needs you reaches it.
    const here = new Set([...this.chefs].filter(([, c]) => c.director.station?.area === 'bell').map(([id]) => id))
    const arrived = [...here].some((id) => !this.atBell.has(id))
    this.atBell = here
    if (arrived && !this.catchingUp) {
      if (!this.reduced) ringBell(this.bell, now)
      const point = this.project(this.bell.getWorldPosition(new THREE.Vector3()))
      if (point && this.observedSince != null) audio.play('gong', point.x / Math.max(1, this.canvas.clientWidth) * 2 - 1, 0.8)
    }
    hopBell(this.bell, now)
  }

  // MARK: Break room

  updateBreakRoom(now) {
    this.breakClock = now
    const resting = [...this.pacing].filter(([id, state]) => this.chefs.has(id) && SceneLayout.work(state.agent).area === 'break').map(([id]) => id)
    const before = new Map([...this.breakRoom.members].map(([k, v]) => [k, { ...v }]))
    const changed = this.breakRoom.update(resting, now)
    for (const id of changed) { const state = this.pacing.get(id); if (state) state.want = this.wanted(id, true) }
    const said = []
    for (const id of [...changed].sort()) {
      const member = this.breakRoom.members.get(id), kind = this.breakRoom.kind(id)
      if (!member || !kind) continue
      const moved = before.get(id)?.spot !== member.spot
      if (kind === 'arcade' && moved) said.push([id, ['🎮', '🕹️']])
      else if (kind === 'vending' && moved) said.push([id, ['🥤']])
      else if (kind === 'espresso' && moved) said.push([id, ['☕']])
      else if (laughing.has(member.clip)) said.push([id, ['😂', '🤣', '😆']])
      else if (talking.has(member.clip)) said.push([id, ['💬', '🗣️', '💬', '👀']])
    }
    for (const [id, member] of this.breakRoom.members) {
      if (member.clip !== 'play_arcade') continue
      const director = this.chefs.get(id)?.director
      if (!director || director.clip.name !== 'play_arcade') { this.arcadeTime.delete(id); continue }
      const clip = director.clips.play_arcade
      const win = (clip?.duration ?? 6) * (clip?.markers?.win ?? 0.77)
      const t = director.clipTime, last = this.arcadeTime.get(id) ?? t
      if ((last < win && t >= win) || (t < last && win <= t)) {
        this.arcadeWins.set(id, (this.arcadeWins.get(id) ?? 0) + 1)
        if (this.arcadeWins.get(id) % 2 === 1) said.push([id, ['🏆', '⭐', '🎉']])
      }
      this.arcadeTime.set(id, t)
    }
    for (const [id, options] of said) this.say(id, options, now)
  }
  say(id, options, now) {
    if (this.selectedID || !options.length || now - (this.lastBubble.get(id) ?? -Infinity) < 3) return
    const showing = [...this.bubbles.values()].filter((b) => b.until > now).length
    if (showing >= 4 && !this.bubbles.has(id)) return
    let bubble = this.bubbles.get(id)
    if (!bubble) { bubble = new ChefBubble(this.overlay); this.bubbles.set(id, bubble) }
    this.bubbleCount += 1
    bubble.show(options[this.bubbleCount % options.length], now, this.reduced)
    this.lastBubble.set(id, now)
  }
  placeBubbles(now) {
    for (const [id, bubble] of this.bubbles) {
      const chef = this.chefs.get(id)
      const point = chef && !this.selectedID && bubble.update(now)
        ? this.project({ x: chef.root.position.x + 0.35, y: chef.root.position.y + 2.15 * scale, z: chef.root.position.z }) : null
      if (!point) { bubble.remove(); this.bubbles.delete(id); continue }
      bubble.place(point.x - bubbleSize.w / 2, point.y - bubbleSize.h)
    }
  }

  announce(text) { this.onAnnounce?.(text) }
}

// MARK: Pieces

function measureSign(text) {
  const c = measureSign.context ??= document.createElement('canvas').getContext('2d')
  c.font = '600 9.5px -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif'
  return c.measureText(text.toUpperCase()).width + text.length * 0.9
}

/** A glowing ring on the floor around the selected chef, slowly turning (StarCraft-style). */
function makeSelectionRing() {
  const side = 512, canvas = document.createElement('canvas'); canvas.width = canvas.height = side
  const g = canvas.getContext('2d'), c = side / 2, radius = side * 0.4
  const color = (a) => `rgba(89,255,158,${a})`
  const glow = g.createRadialGradient(c, c, 0, c, c, side / 2)
  glow.addColorStop(0.62, color(0)); glow.addColorStop(0.8, color(0.45)); glow.addColorStop(1, color(0))
  g.fillStyle = glow; g.fillRect(0, 0, side, side)
  g.strokeStyle = color(0.9); g.lineWidth = 7; g.beginPath(); g.arc(c, c, radius, 0, Math.PI * 2); g.stroke()
  g.strokeStyle = color(1); g.lineWidth = 14; g.lineCap = 'round'
  for (let start = 0; start < 360; start += 120) { g.beginPath(); g.arc(c, c, radius + 18, start * Math.PI / 180, (start + 62) * Math.PI / 180); g.stroke() }
  const texture = new THREE.CanvasTexture(canvas); texture.colorSpace = THREE.SRGBColorSpace
  const size = 1.75 * scale
  const material = new THREE.MeshBasicMaterial({ map: texture, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide })
  const disc = new THREE.Mesh(new THREE.PlaneGeometry(size, size), material)
  disc.name = 'selection ring disc'; disc.rotation.x = -Math.PI / 2; disc.position.y = ChefMetrics.floorTop + 0.012; disc.renderOrder = 5
  const ring = new THREE.Group(); ring.name = 'selection ring'; ring.add(disc)
  return ring
}

function loadCharacters() {
  try { return JSON.parse(localStorage.getItem('kitchenCharacters') ?? '{}') ?? {} } catch { return {} }
}
function saveCharacters(value) {
  try { localStorage.setItem('kitchenCharacters', JSON.stringify(value)) } catch {}
}

export { setOpacity, ownCopy }
