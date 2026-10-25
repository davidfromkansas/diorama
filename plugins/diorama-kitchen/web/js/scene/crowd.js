// Who does what around the chefs at work, on a seeded clock: the break room's machines, chairs
// and circles (the app's BreakRoom), the restaurant's diners (RestaurantGuests) and the manager's
// rounds (KitchenManager).

import { dist } from './layout.js'

const mask = (1n << 64n) - 1n

/** A small seeded generator (SplitMix64), so the same scene behaves the same way each time. */
export class SplitMix {
  constructor(seed) { this.state = BigInt.asUintN(64, BigInt(seed)) }
  nextInt() {
    this.state = (this.state + 0x9E3779B97F4A7C15n) & mask
    let z = this.state
    z = ((z ^ (z >> 30n)) * 0xBF58476D1CE4E5B9n) & mask
    z = ((z ^ (z >> 27n)) * 0x94D049BB133111EBn) & mask
    return z ^ (z >> 31n)
  }
  next(lo, hi) { return lo + Number(this.nextInt() >> 11n) / 2 ** 53 * (hi - lo) }
}

function pick(options, random) {
  const total = options.reduce((sum, [, w]) => sum + w, 0)
  let x = random.next(0, total)
  for (const [clip, weight] of options) { x -= weight; if (x <= 0) return clip }
  return options[options.length - 1][0]
}

// MARK: Break room

export const talking = new Set(['talk_reply', 'sit_talk', 'sit_gesture'])
export const laughing = new Set(['stand_laugh', 'sit_laugh'])
const standChat = [['talk_reply', 4], ['stand_listen', 2], ['stand_laugh', 1]]
const standListen = [['stand_listen', 3], ['stand_laugh', 2]]
const sitChat = [['sit_talk', 4], ['sit_gesture', 1.5], ['sit_sip', 1.5], ['sit_laugh', 1], ['sit_idle', 1]]
const sitListen = [['sit_idle', 2], ['sit_laugh', 2], ['sit_sip', 1]]
const machineKinds = new Set(['arcade', 'vending', 'espresso'])
const sorted = (keys) => [...keys].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))

/** Resting chefs take a free machine, then a chair, then a place in a circle; turns hand machines on. */
export class BreakRoom {
  constructor(spots, durations, seed = 0xB4EA) {
    this.spots = spots; this.durations = durations; this.random = new SplitMix(seed)
    this.members = new Map()
  }
  station(id) { const m = this.members.get(id); return m ? this.spots[m.spot].station : null }
  kind(id) { const m = this.members.get(id); return m ? this.spots[m.spot].kind : null }
  join(id, now) {
    if (this.members.has(id)) return
    const taken = new Set([...this.members.values()].map((m) => m.spot))
    const spot = this.spots.findIndex((_, i) => !taken.has(i))
    if (spot < 0) return
    this.members.set(id, { spot, clip: '', until: 0, since: now, turnEnds: null })
    this.settle(id, now)
  }
  /** Keeps the members to the chefs resting now; returns those whose spot or clip changed. */
  update(resting, now) {
    const changed = new Set(), staying = new Set(resting)
    for (const id of [...this.members.keys()]) if (!staying.has(id)) this.members.delete(id)
    for (const id of sorted(resting)) if (!this.members.has(id)) { this.join(id, now); changed.add(id) }
    for (const id of sorted(this.members.keys())) {
      const member = this.members.get(id)
      if (member.turnEnds == null || now < member.turnEnds) continue
      let waiting = null
      for (const [key, other] of this.members) {
        if (!this.spots[other.spot].kind.startsWith('circle')) continue
        if (!waiting || other.since < waiting[1].since || (other.since === waiting[1].since && key < waiting[0])) waiting = [key, other]
      }
      if (!waiting) { member.turnEnds = now + this.random.next(45, 90); continue }
      const [next, other] = waiting, spot = member.spot
      member.spot = other.spot; member.since = now
      other.spot = spot; other.since = now
      this.settle(id, now); this.settle(next, now)
      changed.add(id); changed.add(next)
      break
    }
    for (const id of sorted(this.members.keys())) {
      if (now >= this.members.get(id).until && !changed.has(id)) { this.choose(id, now); changed.add(id) }
    }
    return changed
  }
  settle(id, now) {
    const member = this.members.get(id)
    if (!member) return
    const kind = this.spots[member.spot].kind
    member.clip = kind === 'arcade' ? 'play_arcade' : kind === 'vending' || kind === 'espresso' ? 'stand_sip' : ''
    if (machineKinds.has(kind)) { member.turnEnds = now + this.random.next(45, 90); member.until = Infinity }
    else { member.turnEnds = null; member.until = now }
    if (!member.clip) this.choose(id, now)
  }
  choose(id, now) {
    const member = this.members.get(id)
    if (!member) return
    const kind = this.spots[member.spot].kind, seated = kind === 'chair'
    if (!seated && !kind.startsWith('circle')) return
    let someoneTalking = false
    for (const [key, other] of this.members) if (key !== id && this.spots[other.spot].kind === kind && talking.has(other.clip)) someoneTalking = true
    let options = seated ? (someoneTalking ? sitListen : sitChat) : (someoneTalking ? standListen : standChat)
    options = options.map(([c, w]) => [c, c === member.clip ? w * 0.25 : w])
    const clip = pick(options, this.random)
    const loop = this.durations[clip] ?? 3
    member.clip = clip
    member.until = now + Math.max(3, loop * Math.floor(this.random.next(1, 2.999)))
  }
}

// MARK: Restaurant guests

export const GuestScript = {
  chatting: [['sit_talk', 4], ['sit_eat', 3], ['sit_gesture', 1.5], ['sit_sip', 1.5], ['sit_laugh', 1], ['sit_idle', 1]],
  listening: [['sit_idle', 2], ['sit_laugh', 2], ['sit_eat', 3], ['sit_sip', 1]],
  talking: new Set(['sit_talk', 'sit_gesture']),
  cheer: 'sit_cheer', enjoy: 'sit_eat', enjoyHand: 'spoon',
}

const dist3 = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2])

/** Partners at a table take turns talking and listening; a served guest cheers, then eats. */
export class RestaurantGuests {
  constructor(positions, durations, seed = 0x5EA7) {
    this.durations = durations; this.script = GuestScript
    this.partners = positions.map((p, i) => {
      let best = null
      positions.forEach((q, j) => { if (j !== i && (best === null || dist3(q, p) < dist3(positions[best], p))) best = j })
      return best !== null && dist3(positions[best], p) < 1.5 ? best : null
    })
    this.seats = positions.map((_, i) => {
      const random = new SplitMix(BigInt.asUintN(64, BigInt(seed) + BigInt(i) * 0x9E3779B97F4A7C15n))
      const clip = pick(GuestScript.chatting, random)
      return { clip, until: random.next(0.5, 4.5), random, feastUntil: null }
    })
  }
  update(now) {
    const changed = []
    this.seats.forEach((seat, i) => {
      if (now < seat.until) return
      if (seat.feastUntil != null) {
        if (now < seat.feastUntil) { seat.clip = this.script.enjoy; seat.until = seat.feastUntil }
        else { seat.feastUntil = null; this.choose(i, now) }
      } else this.choose(i, now)
      changed.push(i)
    })
    return changed
  }
  serve(i, now, seconds = 12) {
    const seat = this.seats[i]
    if (!seat) return
    const cheer = this.durations[this.script.cheer] ?? 1.6
    seat.clip = this.script.cheer; seat.until = now + cheer; seat.feastUntil = now + cheer + seconds
  }
  choose(i, now) {
    const seat = this.seats[i], partner = this.partners[i]
    const partnerTalking = partner != null && this.script.talking.has(this.seats[partner].clip)
    const options = (partnerTalking ? this.script.listening : this.script.chatting).map(([c, w]) => [c, c === seat.clip ? w * 0.25 : w])
    const clip = pick(options, seat.random)
    const loop = this.durations[clip] ?? 3
    const repeats = Math.floor(seat.random.next(1, 2.999))
    seat.clip = clip; seat.until = now + Math.max(3, loop * repeats)
  }
  /** Which guest sits at each seat: every guest once (a fixed shuffle), then repeats far apart. */
  static cast(guests, positions, seed = 0xD1E7) {
    if (!guests.length) return []
    const random = new SplitMix(seed), order = [...guests]
    for (let i = order.length - 1; i > 0; i--) {
      const j = Math.floor(random.next(0, i + 0.999));
      [order[i], order[j]] = [order[j], order[i]]
    }
    const cast = order.slice(0, positions.length), repeated = new Set()
    while (cast.length < positions.length) {
      const seat = cast.length
      const candidates = order.filter((g) => !repeated.has(g))
      const nearest = (g) => Math.min(...cast.map((c, k) => (c === g ? dist3(positions[k], positions[seat]) : Infinity)).concat([Infinity]))
      const score = (g) => { const d = nearest(g); return d === Infinity ? 0 : d }
      let best = null
      for (const g of candidates.length ? candidates : order) if (best === null || score(g) > score(best)) best = g
      repeated.add(best); cast.push(best)
    }
    return cast
  }
}

/** Whom the manager talks with next: the current chef while it still waits, else the longest waiting. */
export function nextVisit(current, waiting) {
  if (current && waiting.some((w) => w.id === current)) return current
  let best = null
  for (const w of waiting) if (!best || w.since < best.since || (w.since === best.since && w.id < best.id)) best = w
  return best?.id ?? null
}

export { dist }
