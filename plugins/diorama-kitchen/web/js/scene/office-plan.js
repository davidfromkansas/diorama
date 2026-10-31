// The office's floor plan: a 24 × 12 floor (about the reference's 2 : 1) with the kitchen's stations
// under office names, laid out like an open-plan office. The ticket board, QA bench by the window and the library shelves line
// the back wall; desk pods fill the floor; a reading lounge sits in front of the corner shelves;
// the elevator and the demo (meeting) table are on the right; the manager's bell is on a side table
// at the front. Floor points are [x, z]; rects are {x, y, w, h} with y along z.

const rect = (x, y, w, h) => ({ x, y, w, h })
const scale = 1.4, reach = 0.43 * scale

export const podSize = [4.5, 1.6]
const pod = ([x, z]) => rect(x - podSize[0] / 2, z - podSize[1] / 2, podSize[0], podSize[1])

/** Desk pods: two where agents write code, one (with monitors) where they run commands. */
export const pods = {
  cooking: [[-7.4, -3.6], [-1.6, -3.6]].map(pod),
  stove: [[-4.5, 1.0]].map(pod),
}

export const floor = rect(-12, -8, 24, 12)
const back = -7.75, right = 11.75

export const areas = [
  { id: 'elevator', label: 'Elevator: new teammates arrive', short: 'Elevator', footprint: rect(10.65, 0.8, 1.1, 2.4), wall: 'right', spots: 1 },
  { id: 'order', label: 'Ticket board: read the request', short: 'Tickets', footprint: rect(-11.2, back, 3.2, 0.5), wall: 'back', spots: 2 },
  { id: 'prep', label: 'Library: planning and research', short: 'Library', footprint: rect(2.3, back, 4.5, 0.55), wall: 'back', spots: 3 },
  { id: 'cooking', label: 'Desks: editing code', short: 'Desks', footprint: pods.cooking[0], pods: pods.cooking, wall: 'island', spots: 12 },
  { id: 'stove', label: 'Terminals: running commands', short: 'Terminals', footprint: pods.stove[0], pods: pods.stove, wall: 'island', spots: 6 },
  { id: 'tasting', label: 'QA bench: tests and checks', short: 'QA', footprint: rect(-6.8, back, 5.4, 0.75), wall: 'back', spots: 3 },
  { id: 'bell', label: "Manager's bell: needs you", short: 'Needs you', footprint: rect(-10.3, 2.75, 1.6, 0.7), wall: 'freestanding', spots: 6, ringBase: 180 },
  { id: 'serving', label: 'Demo table: ready for review', short: 'Demo', footprint: rect(4.0, 0.2, 4.6, 1.1), wall: 'island', spots: 6 },
  { id: 'break', label: 'Lounge: finished agents', short: 'Lounge', footprint: rect(7.6, -5.25, 1.3, 0.7), wall: 'island', spots: 10 },
  { id: 'pantry', label: 'Supply shelves: skills, plugins and MCP', short: 'Supplies', footprint: rect(11.2, back + 0.55, 0.55, 3.0), wall: 'right', spots: 2 },
]

// MARK: Lounge

const toward = (from, to) => Math.atan2(to[0] - from[0], to[1] - from[1])
export const lounge = (() => {
  const rug = { center: [8.25, -4.75], radius: 2.25 }
  const table = areas.find((a) => a.id === 'break').footprint
  const sofa = { center: [8.25, -6.4], width: 2.3, depth: 0.9, facing: 0 }
  const armchairs = [{ center: [6.75, -4.9], facing: Math.PI / 2 }, { center: [9.7, -4.9], facing: -Math.PI / 2 }]
  const chairs = [
    { id: 'break:sofa0', area: 'break', stand: [7.7, -6.2], facing: 0 },
    { id: 'break:sofa1', area: 'break', stand: [8.8, -6.2], facing: 0 },
    ...armchairs.map((a, i) => ({ id: 'break:armchair' + i, area: 'break', stand: [a.center[0] + Math.sin(a.facing) * 0.12, a.center[1]], facing: a.facing })),
  ]
  // The coffee corner: an espresso machine on a low cabinet against the right wall.
  const cabinet = rect(right - 0.6, -3.35, 0.6, 1.0)
  const espresso = {
    asset: 'espresso', kind: 'espresso', center: [right - 0.3, -2.85], facing: -Math.PI / 2,
    use: { id: 'break:espresso', area: 'break', stand: [right - 0.6 - reach - 0.05, -2.85], facing: Math.PI / 2 },
    rect: cabinet,
  }
  const circleCenters = [[8.7, -1.7], [3.0, -1.7]], radius = 0.95
  const circles = circleCenters.map((center, g) => [0, 120, -120].map((degrees, i) => {
    const a = degrees * Math.PI / 180
    const stand = [center[0] + Math.sin(a) * radius, center[1] - Math.cos(a) * radius]
    return { id: `break:circle${g}.${i}`, area: 'break', stand, facing: toward(stand, center) }
  }))
  const spots = [
    { station: espresso.use, kind: 'espresso' },
    ...chairs.map((c) => ({ station: c, kind: 'chair' })),
    ...circles.flatMap((group, g) => group.map((s) => ({ station: s, kind: 'circle' + g }))),
  ]
  // Seats aren't obstacles (their stands are on them), as in the kitchen's break room.
  const obstacles = [table, cabinet]
  return { rug, table, sofa, armchairs, chairs, cabinet, machines: [espresso], circles, spots, obstacles }
})()

// MARK: Fixtures

/** Pots on the floor along the walls, as in the reference (none in a walkway). */
export const plants = [[-11.3, -6.9], [-7.5, -7.2], [-1.0, -7.2], [1.95, -7.2], [11.2, -0.3], [11.25, 3.55], [-11.3, -0.6], [-0.8, 3.5], [3.0, 3.5]]

/** The library's shelves: the back wall's run (prep in front of part of it) and the right wall's (the supplies). */
export const shelves = [
  { rect: rect(2.3, back, 4.5, 0.55), station: 'prep' },
  { rect: rect(6.8, back, right - 6.8, 0.55) },
  { rect: rect(right - 0.55, back + 0.55, 0.55, 3.0), station: 'pantry' },
  { rect: rect(right - 0.55, back + 3.55, 0.55, 0.85) },
]

export const elevatorWalls = [rect(10.65, 0.8, 1.1, 0.12), rect(10.65, 3.08, 1.1, 0.12)]

export const fixtures = [
  ...pods.cooking.slice(1), ...pods.stove.slice(1),
  ...elevatorWalls,
  ...lounge.obstacles,
  ...plants.map(([x, z]) => rect(x - 0.25, z - 0.25, 0.5, 0.5)),
  ...shelves.filter((s) => !s.station).map((s) => s.rect),
]

/** Where arriving teammates step out of the elevator, and where the manager comes and goes. */
export const landing = { id: 'elevator landing', area: 'elevator', stand: [10.65 - 1.2, 2.0], facing: -Math.PI / 2 }
export const managerDoor = { id: 'elevator door', area: 'door', stand: [10.65 - 0.6, 1.6], facing: -Math.PI / 2 }
export const loungeArea = rect(4.0, -7.0, 7.75, 6.7)
export const restSign = rect(6.0, -7.0, 4.5, 4.5)
