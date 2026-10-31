// The office's room and furniture, built in code: a light oak floor on a sage plinth, cream walls
// with oak trim, desk pods with laptops (and monitors at the terminals), library shelves wrapping
// the back corner over a reading lounge, a QA bench under the window, a ticket board, a demo
// table, the manager's bell on a side table, an elevator, plants and pictures. Live details (lit
// screens, chairs pulled out, the bell's hop) are in `OfficeEffects`.

import * as THREE from 'three'
import { model, srgb } from './assets.js'
import { ChefMetrics, SceneLayout, BreakRoomLayout, areas, area, midX, midY, maxX, maxY, minX, minY } from './layout.js'
import * as Plan from './office-plan.js'

const floorTop = ChefMetrics.floorTop
const deskTop = ChefMetrics.worktopHeight - floorTop

// MARK: Palette

const mat = (color, roughness = 0.75, metalness = 0) => new THREE.MeshStandardMaterial({ color, roughness, metalness })
const C = {
  cream: mat(srgb(0.97, 0.92, 0.8), 0.9), paper: mat(srgb(0.99, 0.97, 0.92), 0.85),
  oak: mat(srgb(0.86, 0.6, 0.36), 0.6), oakDark: mat(srgb(0.7, 0.46, 0.26), 0.6), trim: mat(srgb(0.82, 0.6, 0.38), 0.6),
  sage: mat(srgb(0.55, 0.66, 0.52), 0.85), sageLight: mat(srgb(0.7, 0.79, 0.66), 0.9), sageDark: mat(srgb(0.36, 0.5, 0.38), 0.8),
  charcoal: mat(srgb(0.2, 0.21, 0.22), 0.6), black: mat(srgb(0.1, 0.1, 0.11), 0.55), steel: mat(srgb(0.6, 0.62, 0.62), 0.35, 0.7),
  silver: mat(srgb(0.82, 0.83, 0.85), 0.35, 0.5), white: mat(srgb(0.96, 0.96, 0.94), 0.5), leaf: mat(srgb(0.3, 0.55, 0.3), 0.8),
  leafLight: mat(srgb(0.42, 0.66, 0.38), 0.8), soil: mat(srgb(0.3, 0.22, 0.15), 1),
  rug: mat(srgb(0.78, 0.86, 0.75), 1), rugCream: mat(srgb(0.94, 0.91, 0.83), 1), cork: mat(srgb(0.8, 0.66, 0.46), 1),
  glow: new THREE.MeshStandardMaterial({ color: srgb(1, 0.95, 0.82), emissive: srgb(1, 0.9, 0.7), emissiveIntensity: 0.9, roughness: 0.5 }),
}
const books = [srgb(0.95, 0.93, 0.86), srgb(0.62, 0.74, 0.58), srgb(0.84, 0.86, 0.8), srgb(0.45, 0.6, 0.45), srgb(0.9, 0.84, 0.7), srgb(0.75, 0.82, 0.7)]

// MARK: Pieces

function box(parent, name, w, h, d, x, y, z, material, shadow = true) {
  const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), material)
  mesh.name = name; mesh.position.set(x, y, z)
  mesh.castShadow = shadow; mesh.receiveShadow = true
  parent.add(mesh)
  return mesh
}
function cylinder(parent, name, top, bottom, h, x, y, z, material, segments = 24) {
  const mesh = new THREE.Mesh(new THREE.CylinderGeometry(top, bottom, h, segments), material)
  mesh.name = name; mesh.position.set(x, y, z)
  mesh.castShadow = true; mesh.receiveShadow = true
  parent.add(mesh)
  return mesh
}
function group(name, x = 0, z = 0, facing = 0) {
  const g = new THREE.Group(); g.name = name
  g.position.set(x, floorTop, z); g.rotation.y = facing
  return g
}
const canvasTexture = (width, height, draw, repeat) => {
  const canvas = document.createElement('canvas'); canvas.width = width; canvas.height = height
  draw(canvas.getContext('2d'), width, height)
  const t = new THREE.CanvasTexture(canvas); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8
  if (repeat) { t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(...repeat) }
  return t
}

/** Light oak planks, staggered, with a soft grain. */
function planks(f) {
  const map = canvasTexture(1024, 1024, (g, w, h) => {
    const rows = 8, rowH = h / rows
    for (let r = 0; r < rows; r++) {
      let x = -((r * 397) % 600)
      while (x < w) {
        const length = 420 + ((r * 131 + x * 7) % 260)
        const tone = 0.94 + (((r * 17 + Math.floor(x)) * 7919) % 100) / 1600
        g.fillStyle = `rgb(${Math.round(236 * tone)},${Math.round(206 * tone)},${Math.round(160 * tone)})`
        g.fillRect(x, r * rowH, length, rowH)
        g.fillStyle = 'rgba(150,110,60,0.06)'
        for (let i = 0; i < 6; i++) g.fillRect(x, r * rowH + 6 + i * 20, length, 2)
        g.fillStyle = 'rgba(140,100,60,0.35)'; g.fillRect(x, r * rowH, 2, rowH)
        x += length
      }
      g.fillStyle = 'rgba(140,100,60,0.3)'; g.fillRect(0, r * rowH, w, 2)
    }
  }, [f.w / 6, f.h / 6])
  return new THREE.MeshStandardMaterial({ map, roughness: 0.6 })
}

function plant(parent, x, z, size = 1) {
  const g = group('plant', x, z)
  cylinder(g, 'pot', 0.24 * size, 0.19 * size, 0.42 * size, 0, 0.21 * size, 0, C.white)
  cylinder(g, 'soil', 0.22 * size, 0.22 * size, 0.02, 0, 0.41 * size, 0, C.soil)
  cylinder(g, 'stem', 0.025, 0.03, 0.5 * size, 0, 0.66 * size, 0, C.leaf, 8)
  const leaf = new THREE.SphereGeometry(0.17 * size, 12, 8)
  const spots = [[0, 1.05, 0], [0.16, 0.86, 0.05], [-0.15, 0.9, -0.04], [0.05, 0.72, -0.15], [-0.06, 0.74, 0.16], [0.1, 1.2, -0.05], [-0.1, 1.18, 0.07]]
  spots.forEach(([lx, ly, lz], i) => {
    const m = new THREE.Mesh(leaf, i % 2 ? C.leaf : C.leafLight)
    m.position.set(lx * size, ly * size, lz * size); m.scale.set(0.75, 1.25, 0.5); m.rotation.set(lz * 3, i, lx * 3)
    m.castShadow = true; g.add(m)
  })
  parent.add(g)
  return g
}

function smallPlant(parent, x, y, z) {
  const g = new THREE.Group(); g.position.set(x, y, z)
  cylinder(g, 'pot', 0.07, 0.055, 0.1, 0, 0.05, 0, C.white)
  for (const [lx, lz] of [[0, 0], [0.04, 0.03], [-0.04, -0.02]]) {
    const leaf = new THREE.Mesh(new THREE.SphereGeometry(0.05, 8, 6), C.leafLight)
    leaf.position.set(lx, 0.15, lz); leaf.scale.set(0.8, 1.3, 0.6); leaf.castShadow = true; g.add(leaf)
  }
  parent.add(g)
  return g
}

/** A framed print: cream mat with a sage circle, arch or square. */
function picture(parent, x, y, z, facing, w, h, kind) {
  const g = new THREE.Group(); g.position.set(x, y, z); g.rotation.y = facing
  box(g, 'frame', w, h, 0.05, 0, 0, 0, C.trim, false)
  const art = canvasTexture(256, Math.round(256 * h / w), (c, cw, ch) => {
    c.fillStyle = '#fbf6ea'; c.fillRect(0, 0, cw, ch)
    c.fillStyle = kind === 'arch' ? '#e9d2a8' : '#7fa07a'
    if (kind === 'circle') { c.beginPath(); c.arc(cw / 2, ch / 2, cw * 0.28, 0, Math.PI * 2); c.fill() }
    else if (kind === 'arch') { c.beginPath(); c.moveTo(cw * 0.25, ch * 0.75); c.lineTo(cw * 0.25, ch * 0.45); c.arc(cw / 2, ch * 0.45, cw * 0.25, Math.PI, 0); c.lineTo(cw * 0.75, ch * 0.75); c.fill(); c.fillStyle = '#7fa07a'; c.fillRect(cw * 0.25, ch * 0.62, cw * 0.5, ch * 0.13) }
    else { c.fillRect(cw * 0.22, ch * 0.22, cw * 0.56, ch * 0.56) }
  })
  const face = new THREE.Mesh(new THREE.PlaneGeometry(w - 0.1, h - 0.1), new THREE.MeshStandardMaterial({ map: art, roughness: 0.9 }))
  face.position.z = 0.03; g.add(face)
  parent.add(g)
}

/** Shelving with rows of books, `w` wide along its x, facing +z. */
function bookcase(name, w, h, d) {
  const g = new THREE.Group(); g.name = name
  const shelves = 5, bays = Math.max(1, Math.round(w / 0.9))
  box(g, 'case back', w, h, 0.04, 0, h / 2, -d / 2 + 0.02, C.oakDark)
  for (const x of [-w / 2 + 0.03, w / 2 - 0.03]) box(g, 'case side', 0.06, h, d, x, h / 2, 0, C.oak)
  for (let i = 1; i < bays; i++) box(g, 'case divider', 0.04, h, d - 0.04, -w / 2 + i * w / bays, h / 2, 0, C.oak)
  for (let s = 0; s <= shelves; s++) box(g, 'shelf', w, 0.05, d, 0, 0.04 + s * (h - 0.08) / shelves, 0, C.oak)
  const spine = new THREE.BoxGeometry(1, 1, 1)
  const count = Math.floor(w / 0.075) * shelves
  const mesh = new THREE.InstancedMesh(spine, new THREE.MeshStandardMaterial({ roughness: 0.8 }), count)
  mesh.name = 'books'; mesh.castShadow = true; mesh.receiveShadow = true
  const m = new THREE.Matrix4(), color = new THREE.Color()
  let i = 0, seed = name.length * 97 + Math.round(w * 13)
  const random = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647 }
  for (let s = 0; s < shelves; s++) {
    const y0 = 0.065 + s * (h - 0.08) / shelves, gap = (h - 0.08) / shelves - 0.07
    let x = -w / 2 + 0.08
    while (x < w / 2 - 0.12 && i < count) {
      const bw = 0.045 + random() * 0.04, bh = gap * (0.62 + random() * 0.3)
      if (random() < 0.12) { x += 0.12; continue }
      m.compose(new THREE.Vector3(x + bw / 2, y0 + bh / 2, 0.02), new THREE.Quaternion(), new THREE.Vector3(bw * 0.92, bh, d * 0.72))
      mesh.setMatrixAt(i, m); mesh.setColorAt(i, color.copy(books[Math.floor(random() * books.length)])); i++
      x += bw
    }
  }
  mesh.count = i
  g.add(mesh)
  return g
}

/** An office chair (dark, five-star base) or a dining chair (sage), its seat facing +z. */
function officeChair(kind) {
  const g = new THREE.Group(); g.name = kind + ' chair'
  if (kind === 'desk') {
    const seat = 0.55
    for (let i = 0; i < 5; i++) {
      const a = i / 5 * Math.PI * 2
      const leg = box(g, 'chair leg', 0.05, 0.04, 0.3, Math.sin(a) * 0.15, 0.06, Math.cos(a) * 0.15, C.black)
      leg.rotation.y = a
      cylinder(g, 'caster', 0.03, 0.03, 0.04, Math.sin(a) * 0.29, 0.02, Math.cos(a) * 0.29, C.black, 8)
    }
    cylinder(g, 'chair column', 0.035, 0.035, seat - 0.1, 0, seat / 2, 0, C.steel, 12)
    box(g, 'chair seat', 0.5, 0.09, 0.48, 0, seat, 0, C.charcoal)
    box(g, 'chair back', 0.48, 0.5, 0.07, 0, seat + 0.32, -0.24, C.charcoal)
    for (const x of [-0.26, 0.26]) box(g, 'chair arm', 0.05, 0.05, 0.32, x, seat + 0.2, -0.02, C.black)
  } else {
    const seat = 0.55
    for (const x of [-0.18, 0.18]) for (const z of [-0.18, 0.18]) cylinder(g, 'chair leg', 0.022, 0.018, seat, x, seat / 2, z, C.oak, 8)
    box(g, 'chair seat', 0.46, 0.07, 0.46, 0, seat + 0.02, 0, C.sageLight)
    box(g, 'chair back', 0.44, 0.42, 0.06, 0, seat + 0.27, -0.21, C.sageLight)
  }
  return g
}

// MARK: Room

function buildRoom() {
  const root = new THREE.Group(); root.name = 'office-room'
  const f = Plan.floor
  // The sage plinth the office sits on, and the oak floor on top.
  box(root, 'plinth', f.w + 0.5, 0.5, f.h + 0.5, midX(f), -0.15, midY(f), C.sage)
  const floor = box(root, 'oak floor', f.w, 0.03, f.h, midX(f), floorTop - 0.015, midY(f), planks(f), false)
  floor.receiveShadow = true
  const back = f.y + 0.13, right = maxX(f) - 0.13, h = 2.9
  // Back and right walls: cream plaster, oak skirting and cornice.
  box(root, 'back wall', f.w, h, 0.22, midX(f), floorTop + h / 2, back - 0.02, C.cream)
  box(root, 'back cornice', f.w, 0.1, 0.28, midX(f), floorTop + h, back, C.trim)
  box(root, 'back skirting', f.w, 0.14, 0.26, midX(f), floorTop + 0.07, back, C.trim)
  box(root, 'right wall', 0.22, h, f.h, right + 0.02, floorTop + h / 2, midY(f), C.cream)
  box(root, 'right cornice', 0.28, 0.1, f.h, right, floorTop + h, midY(f), C.trim)
  box(root, 'right skirting', 0.26, 0.14, f.h, right, floorTop + 0.07, midY(f), C.trim)
  // A low edge along the open sides, so the floor reads as a tray.
  box(root, 'left edge', 0.2, 0.18, f.h, f.x + 0.1, floorTop + 0.09, midY(f), C.trim)
  box(root, 'front edge', f.w, 0.18, 0.2, midX(f), floorTop + 0.09, maxY(f) - 0.1, C.trim)
  // The window onto green hills, above the QA bench.
  const bench = area('tasting').footprint
  const hills = canvasTexture(512, 256, (g, w, hh) => {
    const sky = g.createLinearGradient(0, 0, 0, hh); sky.addColorStop(0, '#bfe0ea'); sky.addColorStop(1, '#e6f2ee')
    g.fillStyle = sky; g.fillRect(0, 0, w, hh)
    const hill = (y, color, phase) => { g.fillStyle = color; g.beginPath(); g.moveTo(0, hh); for (let x = 0; x <= w; x += 8) g.lineTo(x, y + Math.sin(x / 70 + phase) * 18 + Math.sin(x / 23 + phase) * 5); g.lineTo(w, hh); g.fill() }
    hill(hh * 0.55, '#a9c79b', 0.3); hill(hh * 0.68, '#86ad7f', 2.1); hill(hh * 0.82, '#6f9a6c', 4.0)
  })
  const window_ = new THREE.Group(); window_.name = 'window'; window_.position.set(midX(bench), floorTop + 1.8, back + 0.12)
  box(window_, 'window frame', bench.w, 1.3, 0.08, 0, 0, 0, C.charcoal, false)
  const glass = new THREE.Mesh(new THREE.PlaneGeometry(bench.w - 0.16, 1.14), new THREE.MeshStandardMaterial({ map: hills, roughness: 0.2, emissive: srgb(0.2, 0.22, 0.2), emissiveMap: hills }))
  glass.position.z = 0.045; window_.add(glass)
  for (const x of [-bench.w / 6, bench.w / 6]) box(window_, 'mullion', 0.06, 1.2, 0.04, x, 0, 0.06, C.charcoal, false)
  root.add(window_)
  // Pictures between the window and the shelves, and one on the right wall.
  picture(root, -0.3, floorTop + 1.75, back + 0.13, 0, 0.75, 0.9, 'circle')
  picture(root, 0.65, floorTop + 1.75, back + 0.13, 0, 0.75, 0.9, 'arch')
  picture(root, 1.6, floorTop + 1.75, back + 0.13, 0, 0.75, 0.9, 'square')
  picture(root, right - 0.13, floorTop + 1.7, 3.6, -Math.PI / 2, 0.75, 1.0, 'arch')
  for (const [x, z] of Plan.plants) plant(root, x, z, 1)
  // The library shelves not used as a station (behind the lounge).
  for (const shelf of Plan.shelves.filter((s) => !s.station)) root.add(placeShelf(shelf.rect))
  return root
}

function placeShelf(r) {
  const sideways = r.w < r.h, width = sideways ? r.h : r.w, depth = sideways ? r.w : r.h
  const node = bookcase('bookcase', width, 2.35, depth)
  node.position.set(midX(r), floorTop, midY(r)); node.rotation.y = sideways ? -Math.PI / 2 : 0
  return node
}

// MARK: Stations

function stationRoot(a) {
  const g = new THREE.Group(); g.name = a.id
  return g
}

/** The desks: pods of facing desks with a laptop (or monitor and keyboard at the terminals) and a chair per seat. */
function desks(a) {
  const root = stationRoot(a)
  const terminals = a.id === 'stove'
  root.userData.screens = {}; root.userData.chairs = {}
  for (const p of a.pods) {
    const pod = group('desk pod', midX(p), midY(p))
    const w = p.w, d = p.h
    box(pod, 'desk top', w, 0.05, d, 0, deskTop - 0.025, 0, C.oak)
    box(pod, 'desk divider', w - 0.1, 0.2, 0.03, 0, deskTop + 0.1, 0, C.sageLight)
    for (const x of [-w / 2 + 0.08, 0, w / 2 - 0.08]) for (const z of [-d / 2 + 0.08, d / 2 - 0.08]) box(pod, 'desk leg', 0.06, deskTop - 0.05, 0.06, x, (deskTop - 0.05) / 2, z, C.charcoal)
    smallPlant(pod, -w / 2 + 0.25, deskTop, 0.15)
    smallPlant(pod, w / 2 - 0.3, deskTop, -0.2)
    root.add(pod)
  }
  for (const slot of SceneLayout.chefSlots[a.id] ?? []) {
    const forward = [Math.sin(slot.facing), Math.cos(slot.facing)], reach = ChefMetrics.chefCounterFront * ChefMetrics.chefScale
    const at = (k) => [slot.stand[0] + forward[0] * k, slot.stand[1] + forward[1] * k]
    const [x, z] = at(reach + 0.32)
    const kit = group('computer', x, z, slot.facing)
    const screenMaterial = new THREE.MeshStandardMaterial({ color: srgb(0.16, 0.2, 0.28), emissive: srgb(0.05, 0.07, 0.1), roughness: 0.3 })
    let screen
    if (terminals) {
      box(kit, 'monitor foot', 0.22, 0.02, 0.16, 0, deskTop + 0.01, 0.12, C.charcoal)
      box(kit, 'monitor neck', 0.04, 0.2, 0.04, 0, deskTop + 0.11, 0.12, C.charcoal)
      box(kit, 'monitor', 0.62, 0.38, 0.04, 0, deskTop + 0.38, 0.12, C.charcoal)
      screen = box(kit, 'monitor screen', 0.57, 0.33, 0.01, 0, deskTop + 0.38, 0.097, screenMaterial, false)
      box(kit, 'keyboard', 0.42, 0.02, 0.14, 0, deskTop + 0.01, -0.14, C.white)
    } else {
      box(kit, 'laptop base', 0.42, 0.02, 0.3, 0, deskTop + 0.01, -0.06, C.silver)
      const lid = new THREE.Group(); lid.position.set(0, deskTop + 0.02, 0.09); lid.rotation.x = -0.28
      box(lid, 'laptop lid', 0.42, 0.29, 0.015, 0, 0.145, 0, C.silver)
      screen = box(lid, 'laptop screen', 0.38, 0.25, 0.004, 0, 0.145, -0.01, screenMaterial, false)
      kit.add(lid)
    }
    root.add(kit)
    root.userData.screens[slot.id] = screen
    const chair = officeChair('desk'), home = at(0.1)
    chair.position.set(home[0], floorTop, home[1]); chair.rotation.y = slot.facing
    root.add(chair)
    root.userData.chairs[slot.id] = { node: chair, home, away: at(-0.6), facing: slot.facing }
  }
  return root
}

/** The demo table: a long oak table on an oval rug, sage chairs, a planter and a pendant lamp. */
function demoTable(a) {
  const r = a.footprint, root = stationRoot(a)
  root.userData.chairs = {}
  const table = group('demo table', midX(r), midY(r))
  const rug = new THREE.Mesh(new THREE.CylinderGeometry(1, 1, 0.012, 48), C.rugCream)
  rug.scale.set(r.w / 2 + 1.0, 1, r.h / 2 + 1.3); rug.position.y = 0.006; rug.receiveShadow = true; table.add(rug)
  box(table, 'table top', r.w, 0.06, r.h, 0, deskTop - 0.03, 0, C.oak)
  for (const x of [-r.w / 2 + 0.2, r.w / 2 - 0.2]) for (const z of [-r.h / 2 + 0.15, r.h / 2 - 0.15]) box(table, 'table leg', 0.08, deskTop - 0.06, 0.08, x, (deskTop - 0.06) / 2, z, C.oakDark)
  box(table, 'planter', 0.9, 0.14, 0.24, 0, deskTop + 0.07, 0, C.oakDark)
  for (const x of [-0.3, 0, 0.3]) smallPlant(table, x, deskTop + 0.06, 0)
  cylinder(table, 'pendant cord', 0.01, 0.01, 1.2, 0, 2.6, 0, C.charcoal, 6)
  const shade = cylinder(table, 'pendant shade', 0.08, 0.28, 0.2, 0, 1.95, 0, C.white)
  shade.castShadow = false
  const bulb = new THREE.Mesh(new THREE.SphereGeometry(0.07, 12, 8), C.glow); bulb.position.y = 1.84; table.add(bulb)
  root.add(table)
  for (const slot of SceneLayout.chefSlots[a.id] ?? []) {
    const forward = [Math.sin(slot.facing), Math.cos(slot.facing)]
    const at = (k) => [slot.stand[0] + forward[0] * k, slot.stand[1] + forward[1] * k]
    const chair = officeChair('dining'), home = at(0.15)
    chair.position.set(home[0], floorTop, home[1]); chair.rotation.y = slot.facing
    root.add(chair)
    root.userData.chairs[slot.id] = { node: chair, home, away: at(-0.6), facing: slot.facing }
  }
  return root
}

/** The ticket board: a cork board of pinned requests over a narrow ledge. */
function ticketBoard(a) {
  const r = a.footprint, root = group(a.id, midX(r), midY(r))
  box(root, 'ledge', r.w, 0.06, r.h, 0, deskTop - 0.03, 0, C.oak)
  for (const x of [-r.w / 2 + 0.1, r.w / 2 - 0.1]) box(root, 'ledge bracket', 0.05, deskTop - 0.06, r.h - 0.05, x, (deskTop - 0.06) / 2, 0, C.oakDark)
  const z = -r.h / 2 + 0.05
  box(root, 'board frame', r.w, 1.2, 0.05, 0, 1.75, z, C.trim)
  box(root, 'board', r.w - 0.12, 1.08, 0.03, 0, 1.75, z + 0.03, C.paper)
  const notes = [[-1.1, 1.95], [-0.6, 1.6], [-0.1, 1.98], [0.35, 1.62], [0.85, 1.9], [1.25, 1.55], [-1.25, 1.45], [0.6, 2.12]]
  notes.forEach(([x, y], i) => {
    const note = box(root, 'ticket', 0.3, 0.36, 0.01, x, y, z + 0.05, i % 3 === 0 ? C.sageLight : i % 3 === 1 ? C.cork : C.cream, false)
    note.rotation.z = ((i * 37) % 11 - 5) / 60
    cylinder(root, 'pin', 0.02, 0.02, 0.02, x, y + 0.15, z + 0.065, C.sageDark, 8).rotation.x = Math.PI / 2
  })
  for (const x of [-0.6, 0.5]) smallPlant(root, x, deskTop, 0)
  return root
}

/** The QA bench: a long oak counter under the window, with a test rig and a few plants. */
function qaBench(a) {
  const r = a.footprint, root = group(a.id, midX(r), midY(r))
  box(root, 'bench top', r.w, 0.06, r.h, 0, deskTop - 0.03, 0, C.oak)
  box(root, 'bench body', r.w - 0.1, deskTop - 0.2, r.h - 0.1, 0, (deskTop - 0.2) / 2 + 0.06, 0, C.cream)
  const cubbies = Math.round(r.w / 0.9)
  for (let i = 0; i < cubbies; i++) box(root, 'cubby', r.w / cubbies - 0.1, deskTop - 0.32, 0.02, -r.w / 2 + (i + 0.5) * r.w / cubbies, (deskTop - 0.2) / 2 + 0.06, r.h / 2 - 0.04, C.oakDark)
  box(root, 'plinth', r.w - 0.2, 0.06, r.h - 0.2, 0, 0.03, 0, C.oakDark)
  smallPlant(root, -r.w / 2 + 0.3, deskTop, -0.1)
  smallPlant(root, r.w / 2 - 0.3, deskTop, -0.1)
  smallPlant(root, 0.4, deskTop, -0.2)
  // Two phones on stands being tested.
  for (const x of [-1.2, 1.4]) {
    box(root, 'device stand', 0.14, 0.04, 0.12, x, deskTop + 0.02, -0.1, C.charcoal)
    const phone = box(root, 'test device', 0.12, 0.22, 0.012, x, deskTop + 0.14, -0.12, C.charcoal)
    phone.rotation.x = -0.2
  }
  return root
}

function shelfStation(a) {
  const root = stationRoot(a)
  root.add(placeShelf(a.footprint))
  return root
}

/** The manager's side table: a lamp, a stack of books, a plant and the desk bell. */
function bellTable(a) {
  const r = a.footprint, root = group(a.id, midX(r), midY(r))
  const top = 0.78
  box(root, 'side table', r.w, 0.05, r.h, 0, top, 0, C.sageLight)
  for (const x of [-r.w / 2 + 0.07, r.w / 2 - 0.07]) for (const z of [-r.h / 2 + 0.07, r.h / 2 - 0.07]) cylinder(root, 'table leg', 0.025, 0.025, top, x, top / 2, z, C.oak, 8)
  cylinder(root, 'lamp base', 0.08, 0.1, 0.05, -0.55, top + 0.05, -0.05, C.oak)
  const lamp = new THREE.Mesh(new THREE.SphereGeometry(0.17, 20, 14), C.glow); lamp.position.set(-0.55, top + 0.25, -0.05); root.add(lamp)
  for (let i = 0; i < 3; i++) box(root, 'book', 0.32 - i * 0.03, 0.05, 0.24, 0.05, top + 0.05 + i * 0.05, -0.05, i === 1 ? C.cream : C.sage)
  smallPlant(root, 0.55, top + 0.025, -0.1)
  const bell = new THREE.Group(); bell.name = 'desk bell'; bell.position.set(0.12, top + 0.025, 0.15)
  cylinder(bell, 'bell base', 0.09, 0.1, 0.03, 0, 0.015, 0, C.charcoal)
  const dome = new THREE.Mesh(new THREE.SphereGeometry(0.075, 16, 10, 0, Math.PI * 2, 0, Math.PI / 2), mat(srgb(0.85, 0.68, 0.35), 0.25, 0.85))
  dome.position.y = 0.03; dome.castShadow = true; bell.add(dome)
  cylinder(bell, 'bell button', 0.012, 0.012, 0.03, 0, 0.115, 0, C.charcoal, 8)
  root.add(bell)
  root.userData.bell = bell
  return root
}

/** The reading lounge in front of the corner shelves: a round rug, a sofa, two armchairs, a coffee table, and the coffee corner. */
async function loungeArea() {
  const L = BreakRoomLayout
  const root = new THREE.Group(); root.name = 'break'
  const rug = new THREE.Mesh(new THREE.CylinderGeometry(L.rug.radius, L.rug.radius, 0.012, 64), C.rug)
  rug.name = 'lounge rug'; rug.position.set(L.rug.center[0], floorTop + 0.006, L.rug.center[1]); rug.receiveShadow = true
  root.add(rug)
  const t = L.table, table = group('coffee table', midX(t), midY(t))
  box(table, 'coffee table top', t.w, 0.05, t.h, 0, 0.42, 0, C.oak)
  for (const x of [-t.w / 2 + 0.1, t.w / 2 - 0.1]) for (const z of [-t.h / 2 + 0.1, t.h / 2 - 0.1]) cylinder(table, 'table leg', 0.03, 0.03, 0.4, x, 0.2, z, C.oakDark, 8)
  box(table, 'book', 0.3, 0.05, 0.22, -0.25, 0.47, 0, C.sage)
  box(table, 'book', 0.26, 0.04, 0.2, -0.24, 0.515, 0.01, C.cream)
  cylinder(table, 'lamp stem', 0.015, 0.015, 0.3, 0.3, 0.6, -0.1, C.oak, 8)
  const shade = cylinder(table, 'lamp shade', 0.1, 0.14, 0.14, 0.3, 0.8, -0.1, C.glow)
  shade.castShadow = false
  root.add(table)
  const seatTop = 0.62
  const cushion = (parent, w, x) => {
    box(parent, 'seat cushion', w, 0.16, 0.6, x, seatTop - 0.08, 0.06, C.sageLight)
  }
  const s = L.sofa, sofa = group('sofa', s.center[0], s.center[1], s.facing)
  box(sofa, 'sofa base', s.width, seatTop - 0.18, s.depth, 0, (seatTop - 0.18) / 2 + 0.04, 0, C.sage)
  cushion(sofa, s.width / 2 - 0.2, -s.width / 4 + 0.05); cushion(sofa, s.width / 2 - 0.2, s.width / 4 - 0.05)
  box(sofa, 'sofa back', s.width, 0.55, 0.22, 0, seatTop + 0.15, -s.depth / 2 + 0.11, C.sage)
  for (const x of [-s.width / 2 + 0.1, s.width / 2 - 0.1]) box(sofa, 'sofa arm', 0.2, 0.32, s.depth, x, seatTop - 0.02, 0, C.sage)
  root.add(sofa)
  for (const a of L.armchairs) {
    const chair = group('armchair', a.center[0], a.center[1], a.facing)
    box(chair, 'armchair base', 0.82, seatTop - 0.18, 0.8, 0, (seatTop - 0.18) / 2 + 0.04, 0, C.sage)
    cushion(chair, 0.5, 0)
    box(chair, 'armchair back', 0.82, 0.55, 0.2, 0, seatTop + 0.15, -0.3, C.sage)
    for (const x of [-0.33, 0.33]) box(chair, 'armchair arm', 0.16, 0.3, 0.8, x, seatTop - 0.03, 0, C.sage)
    root.add(chair)
  }
  // The coffee corner.
  const c = L.cabinet, cabinet = group('coffee cabinet', midX(c), midY(c))
  box(cabinet, 'cabinet', c.w, 0.9, c.h, 0, 0.45, 0, C.oak)
  box(cabinet, 'cabinet top', c.w + 0.04, 0.04, c.h + 0.04, 0, 0.92, 0, C.cream)
  root.add(cabinet)
  // An espresso machine (facing the room) with two cups.
  const machine = L.machines[0], coffee = group('break machine:espresso', machine.center[0], machine.center[1], machine.facing)
  const y = 0.94
  box(coffee, 'espresso body', 0.42, 0.42, 0.36, 0, y + 0.21, -0.02, C.sageDark)
  box(coffee, 'espresso top', 0.44, 0.04, 0.38, 0, y + 0.44, -0.02, C.steel)
  box(coffee, 'espresso drip tray', 0.34, 0.03, 0.14, 0, y + 0.015, 0.2, C.steel)
  box(coffee, 'espresso head', 0.14, 0.05, 0.1, 0, y + 0.26, 0.18, C.steel)
  for (const x of [-0.18, 0.2]) cylinder(coffee, 'cup', 0.04, 0.035, 0.07, x, y + 0.035, 0.32, C.white, 12)
  root.add(coffee)
  smallPlant(root, midX(c), floorTop + 0.94, maxY(c) - 0.15)
  return root
}

/** The elevator on the right wall, its doors facing the room; they slide open for arrivals. */
function elevator(a) {
  const r = a.footprint, root = group(a.id, midX(r), midY(r), -Math.PI / 2)
  const w = r.h, d = r.w, h = 2.6
  // A cream alcove in the wall: a car with brushed walls, an oak-trimmed portal and sage steel doors.
  const frame = C.cream, door = mat(srgb(0.6, 0.66, 0.6), 0.35, 0.55), car = mat(srgb(0.78, 0.78, 0.75), 0.4, 0.4)
  box(root, 'elevator back', w, h, 0.1, 0, h / 2, -d / 2 + 0.05, car)
  for (const x of [-w / 2 + 0.06, w / 2 - 0.06]) box(root, 'elevator side', 0.12, h, d, x, h / 2, 0, frame)
  box(root, 'elevator ceiling', w, 0.08, d, 0, h - 0.04, 0, frame)
  box(root, 'elevator header', w, 0.36, 0.14, 0, h - 0.18, d / 2 - 0.07, frame)
  for (const x of [-w / 2 + 0.03, w / 2 - 0.03]) box(root, 'portal trim', 0.08, h, 0.18, x, h / 2, d / 2 - 0.07, C.trim)
  box(root, 'portal trim', w, 0.08, 0.18, 0, h - 0.04, d / 2 - 0.07, C.trim)
  const lamp = mat(srgb(1, 0.8, 0.45)); lamp.emissive = srgb(1, 0.72, 0.35)
  box(root, 'floor indicator', 0.4, 0.1, 0.02, 0, h - 0.18, d / 2 + 0.005, lamp)
  box(root, 'elevator floor', w - 0.24, 0.02, d - 0.1, 0, 0.01, 0, C.steel)
  box(root, 'call panel', 0.1, 0.22, 0.03, w / 2 + 0.12, 1.1, d / 2 - 0.02, C.steel)
  const mat_ = new THREE.Mesh(new THREE.PlaneGeometry(w * 0.8, 0.6), C.sageDark)
  mat_.rotation.x = -Math.PI / 2; mat_.position.set(0, 0.008, d / 2 + 0.35); mat_.receiveShadow = true; root.add(mat_)
  root.userData.doors = [['elevator door left', -w / 4 + 0.03, -1], ['elevator door right', w / 4 - 0.03, 1]].map(([name, x, direction]) => {
    const node = box(root, name, w / 2 - 0.12, h - 0.4, 0.05, x, (h - 0.36) / 2, d / 2 - 0.05, door)
    return { door: node, closed: x, slide: direction * (w / 2 - 0.2) }
  })
  return root
}

async function station(a) {
  switch (a.id) {
    case 'elevator': return elevator(a)
    case 'cooking': case 'stove': return desks(a)
    case 'serving': return demoTable(a)
    case 'order': return ticketBoard(a)
    case 'tasting': return qaBench(a)
    case 'prep': case 'pantry': return shelfStation(a)
    case 'bell': return bellTable(a)
    case 'break': return loungeArea()
  }
  return stationRoot(a)
}

// MARK: Light

function light(scene) {
  const k = Math.PI / 1000
  const ambient = new THREE.AmbientLight(srgb(1, 0.96, 0.9), 230 * k)
  const hemi = new THREE.HemisphereLight(srgb(1, 0.97, 0.92), srgb(0.75, 0.68, 0.58), 160 * k)
  scene.add(ambient, hemi)
  const sun = new THREE.DirectionalLight(srgb(1, 0.93, 0.82), 950 * k)
  sun.position.set(-9, 13, 6); sun.target.position.set(0, 0, 0)
  sun.castShadow = true
  sun.shadow.mapSize.set(4096, 4096)
  const s = sun.shadow.camera
  s.left = -20; s.right = 20; s.top = 20; s.bottom = -20; s.near = 0.5; s.far = 60
  sun.shadow.bias = -0.0004; sun.shadow.normalBias = 0.02; sun.shadow.intensity = 0.45; sun.shadow.radius = 5
  scene.add(sun, sun.target)
  const fill = new THREE.DirectionalLight(srgb(0.9, 0.93, 1), 260 * k)
  fill.position.set(10, 7, 10)
  scene.add(fill)
  return { ambient, sun, fill }
}

// MARK: Live details

/** Laptops light while a teammate types; terminals glow green and flicker while a command runs; chairs roll back from occupied seats. */
export class OfficeEffects {
  constructor(stations) {
    this.screens = { ...(stations.cooking?.userData.screens ?? {}) }
    this.terminals = { ...(stations.stove?.userData.screens ?? {}) }
    this.chairs = { ...(stations.cooking?.userData.chairs ?? {}), ...(stations.stove?.userData.chairs ?? {}), ...(stations.serving?.userData.chairs ?? {}) }
    for (const screen of [...Object.values(this.screens), ...Object.values(this.terminals)]) screen.material = screen.material.clone()
    this.lit = new Set(); this.running = new Set()
    for (const chair of Object.values(this.chairs)) chair.out = 0
  }
  update(chefs, reduced) {
    const at = (c) => c.station && Math.hypot(c.position[0] - c.station.stand[0], c.position[1] - c.station.stand[1]) < 0.6
    const seated = new Set(chefs.filter(at).map((c) => c.station.id))
    const typing = new Set(chefs.filter((c) => c.station?.area === 'cooking' && at(c)).map((c) => c.station.id))
    const running = new Set(chefs.filter((c) => c.station?.area === 'stove' && c.clip === 'waiting_tool').map((c) => c.station.id))
    for (const [id, screen] of Object.entries(this.screens)) {
      const on = typing.has(id)
      if (on === this.lit.has(id)) continue
      if (on) this.lit.add(id); else this.lit.delete(id)
      screen.material.color.copy(on ? srgb(0.75, 0.88, 1) : srgb(0.16, 0.2, 0.28))
      screen.material.emissive.copy(on ? srgb(0.45, 0.62, 0.85) : srgb(0.05, 0.07, 0.1))
    }
    const blink = reduced ? 1 : 0.75 + 0.25 * Math.sin(performance.now() / 90)
    for (const [id, screen] of Object.entries(this.terminals)) {
      const on = running.has(id)
      screen.material.color.copy(on ? srgb(0.2, 0.55, 0.3) : srgb(0.12, 0.16, 0.14))
      screen.material.emissive.copy(on ? srgb(0.2 * blink, 0.85 * blink, 0.4 * blink) : srgb(0.03, 0.06, 0.04))
    }
    // Chairs roll out of the way of a teammate at the seat, and back in once it leaves.
    for (const [id, chair] of Object.entries(this.chairs)) {
      const target = seated.has(id) ? 1 : 0
      chair.out = reduced ? target : chair.out + (target - chair.out) * 0.12
      const p = chair.out, side = Math.sin(chair.facing + Math.PI / 2) * 0.55 * p, sideZ = Math.cos(chair.facing + Math.PI / 2) * 0.55 * p
      chair.node.position.x = chair.home[0] + (chair.away[0] - chair.home[0]) * p + side
      chair.node.position.z = chair.home[1] + (chair.away[1] - chair.home[1]) * p + sideZ
      chair.node.rotation.y = chair.facing + p * 0.6
    }
  }
}

/** The desk bell hops and wobbles as a teammate who needs you reaches it. */
export function ringBell(bell, now) { bell.userData.ring = now }
export function hopBell(bell, now) {
  const start = bell.userData.ring
  if (start == null) return
  const t = now - start
  if (t > 0.5) { bell.position.y = bell.userData.y ?? bell.position.y; bell.rotation.z = 0; bell.userData.ring = null; return }
  bell.userData.y ??= bell.position.y
  bell.position.y = bell.userData.y + Math.max(0, Math.sin(Math.min(1, t / 0.2) * Math.PI)) * 0.07
  bell.rotation.z = Math.sin(t * 30) * 0.12 * (1 - t / 0.5)
}

// MARK: Building

export const deliverableIDs = ['box_butter', 'box_coral', 'box_lilac', 'box_mint', 'box_peach', 'box_sky']
const kitchenProps = ['chopped_board', 'cleaver_board', 'lightbulb', 'stove_pot']
const officeProps = { salsa_jar: 'binder', plugin_crate: 'toolbox', connector_object: 'device', plan_plate: 'plan_board' }

/** Everything that isn't a person: the room, the furniture, the light. Same shape as `buildKitchen`'s result. */
export async function buildOffice(scene) {
  scene.background = srgb(0.89, 0.87, 0.83)
  const [stationList, deliverables, props, borrowed] = await Promise.all([
    Promise.all(areas.map(station)),
    Promise.all(deliverableIDs.map((id) => model(`OfficeProps/${id}.glb`))),
    Promise.all(Object.values(officeProps).map((id) => model(`OfficeProps/${id}.glb`))),
    Promise.all(kitchenProps.map((id) => model(`KitchenProps/${id}.glb`))),
  ])
  scene.add(buildRoom())
  const stations = {}
  stationList.forEach((node, i) => { stations[areas[i].id] = node; scene.add(node) })
  const lights = light(scene)
  return {
    stations, seats: [], lights, workInProgress: false,
    food: Object.fromEntries(deliverableIDs.map((id, i) => [id, deliverables[i]])),
    props: {
      ...Object.fromEntries(kitchenProps.map((id, i) => [id, borrowed[i]])),
      ...Object.fromEntries(Object.keys(officeProps).map((id, i) => [id, props[i]])),
    },
    makeEffects: () => [new OfficeEffects(stations)],
    bell: stations.bell?.userData.bell ?? null,
  }
}
