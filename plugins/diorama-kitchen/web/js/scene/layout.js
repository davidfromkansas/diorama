// The kitchen's floor plan and station table: a port of the app's ChefMetrics, KitchenLayout,
// SceneLayout, SceneRouting, BreakRoomLayout and FloorNavigation. Floor points are [x, z]; rects
// are {x, y, w, h} with y along z, like the app's CGRects.

import { KitchenActivity } from '../core/activity.js'

export const rect = (x, y, w, h) => ({ x, y, w, h })
export const minX = (r) => r.x, maxX = (r) => r.x + r.w, minY = (r) => r.y, maxY = (r) => r.y + r.h
export const midX = (r) => r.x + r.w / 2, midY = (r) => r.y + r.h / 2
export const contains = (r, [x, z]) => x >= r.x && x <= r.x + r.w && z >= r.y && z <= r.y + r.h
export const union = (a, b) => {
  const x = Math.min(a.x, b.x), y = Math.min(a.y, b.y)
  return rect(x, y, Math.max(maxX(a), maxX(b)) - x, Math.max(maxY(a), maxY(b)) - y)
}
export const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1])
export const wrap = (angle) => {
  let a = angle
  while (a > Math.PI) a -= 2 * Math.PI
  while (a < -Math.PI) a += 2 * Math.PI
  return a
}

/** The chef's proportions and pacing: clips are authored against them. */
export const ChefMetrics = {
  chefScale: 1.4,
  chefCounterTop: 0.585,
  chefCounterFront: 0.43,
  chefHeight: 1.9,
  floorTop: 0.112,
  get worktopHeight() { return this.chefScale * this.chefCounterTop },
  get heightScale() { return (this.worktopHeight - this.floorTop) / 1.25 },
  /** Seconds at a station before a non-urgent change of work moves the chef. */
  minimumDwell: 2,
  orderReading: 3,
  arrivalWave: 2.6,
}

export const KitchenLayout = {
  floor: rect(-12, -8, 24, 16),
  connectors: [rect(-9.2, -7.8, 0.8, 1.2), rect(-3.6, -7.8, 2.4, 1.2), rect(8.0, -7.8, 3.8, 1.2), rect(10.6, -6.6, 1.2, 2.2), rect(10.6, 0.4, 1.2, 7.2)],
  breakRoomWalls: [rect(-12, 3.125, 6.6, 0.15), rect(-3.475, 3.125, 0.15, 4.875)],
  elevatorWalls: [rect(-11.6, -7.8, 0.12, 2.0), rect(-9.32, -7.8, 0.12, 2.0)],
}

// MARK: Break room

export const BreakRoomLayout = (() => {
  const farWall = 3.275, leftWall = -11.72
  const coffeeBar = { center: [leftWall + 0.02 + 0.72 / 2, 5.6], facing: Math.PI / 2 }
  const machine = (asset, kind, center, facing, size, scale) => {
    const front = [Math.sin(facing), Math.cos(facing)]
    const reach = 0.43 * 1.4
    const stand = [center[0] + front[0] * (size[1] / 2 + reach + 0.02), center[1] + front[1] * (size[1] / 2 + reach + 0.02)]
    const across = Math.abs(Math.sin(facing)) > 0.5 ? [size[1], size[0]] : size
    return {
      asset, kind, center, facing, size, scale,
      use: { id: 'break:' + asset, area: 'break', stand, facing: facing + Math.PI },
      rect: rect(center[0] - across[0] / 2, center[1] - across[1] / 2, across[0], across[1]),
    }
  }
  const far = (asset, x, width, depth, height) => {
    const scale = 2.0 / height
    return machine(asset, 'arcade', [x, farWall + 0.02 + depth * scale / 2], 0, [width * scale, depth * scale], scale)
  }
  const vendingScale = 2.1 / 1.736
  const machines = [
    far('arcade_cosmic', -8.9, 0.866, 1.0, 2.05),
    far('arcade_jungle', -7.5, 1.0, 0.95, 1.879),
    far('arcade_blue', -6.1, 1.0, 0.938, 1.937),
    machine('vending', 'vending', [leftWall + 0.02 + 0.76 * vendingScale / 2, coffeeBar.center[1]], Math.PI / 2, [1.0 * vendingScale, 0.76 * vendingScale], vendingScale),
  ]
  const sideTable = rect(-4.8, 5.97, 0.6, 0.6)
  const tx = midX(sideTable), tz = midY(sideTable)
  const chairs = [
    { id: 'break:chair0', area: 'break', stand: [tx, tz - 0.97], facing: 0 },
    { id: 'break:chair1', area: 'break', stand: [tx, tz + 0.97], facing: Math.PI },
  ]
  const circleCenters = [[-8.6, 6.6], [-6.5, 6.6]], circleRadius = 0.95
  const circles = circleCenters.map((center, g) => [0, 120, -120].map((degrees, i) => {
    const a = degrees * Math.PI / 180
    const stand = [center[0] + Math.sin(a) * circleRadius, center[1] - Math.cos(a) * circleRadius]
    return { id: `break:circle${g}.${i}`, area: 'break', stand, facing: Math.atan2(center[0] - stand[0], center[1] - stand[1]) }
  }))
  const a = [-7.55, 5.8], b = [-4.9, 4.6]
  circles.push([
    { id: 'break:extra0', area: 'break', stand: a, facing: Math.atan2(b[0] - a[0], b[1] - a[1]) },
    { id: 'break:extra1', area: 'break', stand: b, facing: Math.atan2(a[0] - b[0], a[1] - b[1]) },
  ])
  const spots = [
    ...machines.map((m) => ({ station: m.use, kind: m.kind })),
    ...chairs.map((c) => ({ station: c, kind: 'chair' })),
    ...circles.flatMap((group, g) => group.map((s) => ({ station: s, kind: 'circle' + g }))),
  ]
  return { farWall, leftWall, machines, sideTable, chairs, circles, spots, obstacles: [...machines.map((m) => m.rect), sideTable] }
})()

export const areas = [
  { id: 'elevator', label: 'Elevator: new agents arrive', short: 'Elevator', footprint: rect(-11.6, -7.8, 2.4, 2.0), wall: 'freestanding', spots: 1 },
  { id: 'order', label: 'Order rail: read the request', short: 'Orders', footprint: rect(-8.4, -7.8, 4.8, 1.2), wall: 'back', spots: 3 },
  { id: 'prep', label: 'Prep: planning and research', short: 'Prep', footprint: rect(-1.2, -7.8, 9.2, 1.2), wall: 'back', spots: 6 },
  { id: 'cooking', label: 'Cooking island: editing code', short: 'Cooking', footprint: rect(-4.5, -2.8, 9.0, 1.2), wall: 'front', spots: 6 },
  { id: 'stove', label: 'Stove island: running commands', short: 'Stove', footprint: rect(-4.5, 0.6, 9.0, 1.2), wall: 'front', spots: 6 },
  { id: 'tasting', label: 'Tasting: tests and QA', short: 'Tasting', footprint: rect(10.6, -4.4, 1.2, 4.8), wall: 'right', spots: 3 },
  { id: 'bell', label: 'Service gong: needs you', short: 'Needs you', footprint: rect(-0.9, 4.9, 1.8, 0.6), wall: 'freestanding', spots: 6 },
  { id: 'serving', label: 'Serving window: ready for review', short: 'Serving', footprint: rect(3.2, 6.4, 7.4, 1.2), wall: 'front', spots: 5 },
  { id: 'break', label: 'Break room: finished agents', short: 'Break room', footprint: BreakRoomLayout.sideTable, wall: 'island', spots: 10 },
  { id: 'pantry', label: 'Pantry: skills, plugins and MCP', short: 'Pantry', footprint: rect(-11.8, -3.6, 1.2, 6.7), wall: 'left', spots: 3 },
]
export const area = (id) => areas.find((a) => a.id === id)

// MARK: Navigation

/** A small visibility-smoothed A* grid on the floor. Obstacles already include body clearance. */
export class FloorNavigation {
  constructor(min, max, obstacles) {
    this.min = min; this.max = max; this.obstacles = obstacles; this.spacing = 0.5
  }
  isFree([x, z]) {
    return x >= this.min[0] && z >= this.min[1] && x <= this.max[0] && z <= this.max[1] &&
      !this.obstacles.some((o) => x >= o.min[0] && x <= o.max[0] && z >= o.min[1] && z <= o.max[1])
  }
  static intersects(o, a, b) {
    const d = [b[0] - a[0], b[1] - a[1]]
    let low = 0, high = 1
    for (let axis = 0; axis < 2; axis++) {
      if (Math.abs(d[axis]) < 0.00001) { if (a[axis] < o.min[axis] || a[axis] > o.max[axis]) return false }
      else {
        const x = (o.min[axis] - a[axis]) / d[axis], y = (o.max[axis] - a[axis]) / d[axis]
        low = Math.max(low, Math.min(x, y)); high = Math.min(high, Math.max(x, y))
        if (low > high) return false
      }
    }
    return true
  }
  clear(a, b) { return this.isFree(a) && this.isFree(b) && !this.obstacles.some((o) => FloorNavigation.intersects(o, a, b)) }
  route(start, goal) {
    if (!this.isFree(start) || !this.isFree(goal)) return null
    if (this.clear(start, goal)) return [goal]
    const s = this.spacing
    const width = Math.floor((this.max[0] - this.min[0]) / s) + 1, height = Math.floor((this.max[1] - this.min[1]) / s) + 1
    const point = (id) => [this.min[0] + (id % width) * s, this.min[1] + Math.floor(id / width) * s]
    const nearest = (p) => {
      let best = null, bestD = Infinity
      for (let id = 0; id < width * height; id++) {
        const q = point(id), d = (q[0] - p[0]) ** 2 + (q[1] - p[1]) ** 2
        if (d < bestD && this.clear(p, q)) { best = id; bestD = d }
      }
      return best
    }
    const first = nearest(start), last = nearest(goal)
    if (first === null || last === null) return null
    const open = new Set([first]), closed = new Set(), costs = new Map([[first, 0]]), parents = new Map()
    let expansions = 0
    const score = (id) => (costs.get(id) ?? Infinity) + dist(point(id), goal)
    while (open.size) {
      let current = null, best = Infinity
      for (const id of open) { const f = score(id); if (f < best) { best = f; current = id } }
      expansions += 1
      if (expansions > 12000) return null
      if (current === last) {
        const path = [goal, point(last)]
        let id = last
        while (parents.has(id)) { id = parents.get(id); path.push(point(id)) }
        path.push(start); path.reverse()
        const result = []
        let cursor = 0
        while (cursor < path.length - 1) {
          let next = path.length - 1
          while (next > cursor + 1 && !this.clear(path[cursor], path[next])) next -= 1
          result.push(path[next]); cursor = next
        }
        return result
      }
      open.delete(current); closed.add(current)
      const cx = current % width, cy = Math.floor(current / width)
      for (let dx = -1; dx <= 1; dx++) for (let dy = -1; dy <= 1; dy++) {
        if (!dx && !dy) continue
        const x = cx + dx, y = cy + dy
        if (x < 0 || y < 0 || x >= width || y >= height) continue
        const next = y * width + x
        if (closed.has(next) || !this.clear(point(current), point(next))) continue
        const cost = (costs.get(current) ?? 0) + dist(point(current), point(next))
        if (cost < (costs.get(next) ?? Infinity)) { costs.set(next, cost); parents.set(next, current); open.add(next) }
      }
    }
    return null
  }
}

const navigation = (() => {
  const clearance = 0.35 * ChefMetrics.chefScale, f = KitchenLayout.floor
  const fixtures = [...KitchenLayout.connectors, ...KitchenLayout.breakRoomWalls, ...KitchenLayout.elevatorWalls, ...BreakRoomLayout.obstacles]
  const obstacles = [...areas.filter((a) => a.id !== 'elevator').map((a) => a.footprint), ...fixtures].map((r) => ({
    min: [r.x - clearance, r.y - clearance], max: [maxX(r) + clearance, maxY(r) + clearance],
  }))
  return new FloorNavigation([f.x + clearance, f.y + clearance], [maxX(f) - clearance, maxY(f) - clearance], obstacles)
})()

// MARK: Fixed spots

const gongCenter = [midX(area('bell').footprint), midY(area('bell').footprint)]
const gongStrike = (() => {
  const facing = -0.75 * Math.PI, forward = [Math.sin(facing), Math.cos(facing)], right = [-Math.cos(facing), Math.sin(facing)]
  const impact = [gongCenter[0] + 0.1, gongCenter[1] + 0.1], s = ChefMetrics.chefScale
  return { id: 'gong', area: 'gong', stand: [impact[0] - forward[0] * 0.89 * s - right[0] * 0.12 * s, impact[1] - forward[1] * 0.89 * s - right[1] * 0.12 * s], facing }
})()
const elevatorLanding = (() => {
  const door = area('elevator').footprint
  return { id: 'elevator landing', area: 'elevator', stand: [midX(door), maxY(door) + 1.2], facing: 0 }
})()
const loungeArea = (() => {
  const walls = KitchenLayout.breakRoomWalls.reduce(union), f = KitchenLayout.floor
  return rect(f.x, walls.y, maxX(walls) - f.x, maxY(f) - walls.y)
})()

// MARK: Slots

const chefSlots = (() => {
  const s = ChefMetrics.chefScale, reach = ChefMetrics.chefCounterFront * s, spacing = 1.05 * s
  const result = {}
  const row = (id, a, b, facing, gap = spacing) => {
    const length = dist(a, b), count = Math.max(1, Math.floor(length / gap))
    const points = Array.from({ length: count }, (_, i) => {
      const t = (i + 0.5) / count
      return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]
    })
    const free = points.filter((p) => navigation.isFree(p))
    return (free.length ? free : points).map((stand) => ({ area: id, stand, facing }))
  }
  for (const a of areas) {
    const f = a.footprint, x0 = minX(f), x1 = maxX(f), z0 = minY(f), z1 = maxY(f)
    let slots
    if (a.id === 'elevator') slots = [{ area: a.id, stand: [midX(f), midY(f)], facing: 0 }]
    else if (a.id === 'bell') {
      slots = [0, -38, 38, -76, 76, -100].map((degrees) => {
        const angle = degrees * Math.PI / 180
        const stand = [gongCenter[0] + Math.sin(angle) * 1.7, gongCenter[1] + Math.cos(angle) * 1.7]
        return { area: a.id, stand, facing: Math.atan2(gongCenter[0] - stand[0], gongCenter[1] - stand[1]) }
      })
    } else if (a.id === 'break') slots = BreakRoomLayout.spots.map((spot) => spot.station)
    else if (a.id === 'pantry') slots = row(a.id, [x1 + reach, z0], [x1 + reach, z1], -Math.PI / 2, (z1 - z0) / a.spots)
    else if (a.wall === 'back') slots = row(a.id, [x0, z1 + reach], [x1, z1 + reach], Math.PI)
    else if (a.wall === 'left') slots = row(a.id, [x1 + reach, z0], [x1 + reach, z1], -Math.PI / 2)
    else if (a.wall === 'right') slots = row(a.id, [x0 - reach, z0], [x0 - reach, z1], Math.PI / 2)
    else if (a.wall === 'front') slots = row(a.id, [x0, z0 - reach], [x1, z0 - reach], 0)
    else slots = [...row(a.id, [x0, z0 - reach], [x1, z0 - reach], 0), ...row(a.id, [x0, z1 + reach], [x1, z1 + reach], Math.PI)]
    result[a.id] = slots.map((slot, i) => ({ id: `${a.id}#${i}`, area: a.id, stand: slot.stand, facing: slot.facing }))
  }
  return result
})()

/** Where the manager stands to talk with a chef waiting at `stand`. */
function managerSpot(stand, others) {
  let out = [stand[0] - gongCenter[0], stand[1] - gongCenter[1]]
  const length = Math.hypot(out[0], out[1])
  out = length > 0.01 ? [out[0] / length, out[1] / length] : [0, 1]
  const side = [-out[1], out[0]], reach = 1.2
  const offsets = [
    [side[0] * reach, side[1] * reach], [-side[0] * reach, -side[1] * reach],
    [side[0] * reach + out[0] * 0.7, side[1] * reach + out[1] * 0.7], [-side[0] * reach + out[0] * 0.7, -side[1] * reach + out[1] * 0.7],
    [out[0] * 1.4, out[1] * 1.4],
  ]
  const candidates = offsets.map((o) => [stand[0] + o[0], stand[1] + o[1]])
  const spot = candidates.find((p) => navigation.isFree(p) && others.every((q) => dist(q, p) > 0.9)) ?? candidates[0]
  return { id: 'manager', area: 'manager', stand: spot, facing: Math.atan2(stand[0] - spot[0], stand[1] - spot[1]) }
}

// MARK: Routing

/** Agent state → station: where its chef works, the clip it loops and the prop in its hand. */
export function route(agent) {
  const fresh = agent.freshness === 'live' || agent.freshness === 'recentlyObserved'
  switch (agent.status) {
    case 'ready': return { area: 'order', loop: 'idle_available' }
    case 'waiting':
      if (agent.attentionReason === 'other') return { area: 'bell', loop: 'blocked_wait', oneShot: 'blocked_react', urgent: true }
      return { area: 'bell', loop: 'wait_input', oneShot: 'request_input', urgent: true }
    case 'failed': return { area: 'bell', loop: 'blocked_wait', oneShot: 'error_react', urgent: true }
    case 'stopped': return rest(agent, true)
    case 'unknown': return { area: null, loop: 'unknown_wait', urgent: true }
  }
  if (agent.status === 'done' && fresh) return { area: 'serving', loop: 'wait_review', oneShot: 'present_review', urgent: true, deliversPlate: true }
  if (agent.status === 'working' && fresh) {
    const kind = KitchenActivity.classify(agent.latestTool, agent.latestToolDetail), edits = !!agent.turnHasEdits
    if (kind === 'testing' || kind === 'checking') return { area: 'tasting', loop: 'testing_dish', hand: 'spoon' }
    if (kind === 'resources') return { area: 'pantry', loop: 'idle_available', oneShot: 'pickup' }
    if (kind === 'planning' && !edits) return { area: 'prep', loop: 'planning_recipe', hand: 'card' }
    if (kind === 'commands') return { area: 'stove', loop: 'waiting_tool' }
    if (!edits) return { area: 'prep', loop: 'researching_book', hand: 'book' }
    return { area: 'cooking', loop: 'working_chop', hand: 'knife' }
  }
  return rest(agent, true)
}

/** Resting chefs sit down in a lounge chair and idle, sip coffee or chat (stable per agent). */
export function rest(agent, urgent) {
  const loops = ['sit_idle', 'sit_sip', 'sit_chat']
  let hash = 7
  for (const byte of new TextEncoder().encode(agent.id)) hash = (Math.imul(hash, 31) + byte) >>> 0
  const pick = loops[hash % loops.length]
  return { area: 'break', loop: pick, hand: pick === 'sit_sip' ? 'mug' : null, oneShot: 'sit_down', urgent }
}

/** The intent an agent calls for at `slot`: equal keys mean "keep going". */
function intent(agent, slot, pickup, restored) {
  const work = route(agent)
  if (slot && slot.area === 'serving' && slot.id.includes('~')) {
    return { key: ['serving-line', slot.id, 'carry_idle'].join('|'), station: slot, loop: 'carry_idle', oneShot: null, hand: 'plate',
      pickup: restored ? null : pickup, urgent: !!work.urgent }
  }
  const cause = agent.completionKey ?? agent.meaningfulEventID
  const shot = work.oneShot ? { id: `${work.oneShot}:${agent.status}:${cause}`, clip: work.oneShot, restored } : null
  const key = [work.area ?? 'here', slot?.id ?? '', work.loop, work.hand ?? '', shot?.id ?? ''].join('|')
  return {
    key, station: work.area == null ? null : slot, loop: work.loop, oneShot: shot, hand: work.hand ?? null,
    pickup: work.deliversPlate && !restored ? pickup : null, urgent: !!work.urgent, prelude: restored ? null : work.prelude ?? null,
    strike: work.area === 'bell' && shot && !restored ? gongStrike : null,
  }
}

export const SceneLayout = {
  floor: KitchenLayout.floor, areas, connectors: KitchenLayout.connectors, partitionWalls: KitchenLayout.breakRoomWalls,
  navigation, chefSlots, gongCenter, gongStrike, elevatorLanding, loungeArea, managerSpot,
  managerDoor: { id: 'dining door', area: 'door', stand: [1.9, maxY(KitchenLayout.floor) - 0.6], facing: Math.PI },
  restSign: rect(-10.6, 4.5, 6.8, 3.3),
  work: route, intent,
  exitIntent: (agent) => ({ key: 'arrival-exit', station: elevatorLanding, loop: 'idle_available',
    oneShot: { id: 'arrive_wave:' + agent, clip: 'arrive_wave', restored: false } }),
  arrivalIntent: (slot) => ({ key: 'arrival|' + slot.id, station: slot, loop: 'read_ticket', hand: 'ticket' }),
}
