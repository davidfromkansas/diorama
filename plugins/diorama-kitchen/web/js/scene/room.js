// The kitchen's room and stations, built as the Mac app builds them (KitchenTheme, KitchenRoomGeometry,
// KitchenFloor, KitchenStationGeometry, KitchenFixtures, KitchenIsland, KitchenStove,
// KitchenRestaurant, KitchenFood): modelled fixtures where the app has them, its procedural
// pieces elsewhere, the restaurant around it, and its lights.

import * as THREE from 'three'
import { load, roots, model, named, loungeChair, srgb } from './assets.js'
import { isOffice } from './theme.js'
import { buildOffice } from './office.js'
import { ChefMetrics, KitchenLayout, BreakRoomLayout, SceneLayout, areas, area, rect, midX, midY, maxX, maxY, minX, minY } from './layout.js'

const floorTop = ChefMetrics.floorTop

export function material(color, metal = 0, roughness) {
  return new THREE.MeshStandardMaterial({ color, roughness: roughness ?? (metal > 0 ? 0.32 : 0.62), metalness: metal })
}

function box(parent, name, w, h, d, x, y, z, mat) {
  const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat)
  mesh.name = name; mesh.position.set(x, y, z)
  mesh.castShadow = true; mesh.receiveShadow = true
  parent.add(mesh)
  return mesh
}
function cylinder(parent, name, radius, h, x, y, z, mat, segments = 24) {
  const mesh = new THREE.Mesh(new THREE.CylinderGeometry(radius, radius, h, segments), mat)
  mesh.name = name; mesh.position.set(x, y, z)
  mesh.castShadow = true; mesh.receiveShadow = true
  parent.add(mesh)
  return mesh
}

// MARK: Floor

const loader = new THREE.TextureLoader()
const textures = new Map()
function texture(name, color) {
  if (!textures.has(name)) {
    const t = loader.load(`/assets/KitchenStations/${name}.jpg`)
    t.wrapS = t.wrapT = THREE.RepeatWrapping
    t.colorSpace = color ? THREE.SRGBColorSpace : THREE.NoColorSpace
    t.anisotropy = 8
    textures.set(name, t)
  }
  return textures.get(name)
}
function floorMaterial(name, repeat, roughness = 0.58) {
  const map = texture(name, true).clone(), normalMap = texture(name + '_normal', false).clone()
  for (const t of [map, normalMap]) { t.repeat.set(repeat[0], repeat[1]); t.needsUpdate = true }
  return new THREE.MeshStandardMaterial({ map, normalMap, normalScale: new THREE.Vector2(0.8, 0.8), roughness, metalness: 0 })
}

const tile = 0.8, band = 0.8, top = 0.119, thickness = 0.018
export const KitchenFloor = {
  get inner() { const f = KitchenLayout.floor; return rect(f.x + 0.28, f.y + 0.24, f.w - 0.56, f.h - 0.24) },
  get breakRoom() {
    const [long, short] = KitchenLayout.breakRoomWalls, inner = this.inner
    return rect(inner.x, maxY(long), minX(short) - inner.x, maxY(inner) - maxY(long))
  },
  parquet: [8 * 0.11 * Math.SQRT2, 4 * 0.11 * Math.SQRT2],
  rug: rect(-10.6, 4.5, 6.8, 3.3),
  borderLayout() {
    const order = area('order').footprint, elevator = area('elevator').footprint, tasting = area('tasting').footprint, serving = area('serving').footprint
    const [breakTop, breakSide] = KitchenLayout.breakRoomWalls, b = band
    const back = maxY(order), left = this.inner.x, right = minX(tasting), breakFront = minY(breakTop), breakEdge = maxX(breakSide)
    const front = maxY(KitchenLayout.floor), serveFront = minY(serving), serveLeft = minX(serving)
    const runs = [
      rect(maxX(elevator), back, right - b - maxX(elevator), b),
      rect(right - b, back + b, b, serveFront - b - back - b),
      rect(serveLeft, serveFront - b, right - b - serveLeft, b),
      rect(serveLeft - b, serveFront, b, front - b - serveFront),
      rect(breakEdge + b, front - b, serveLeft - b - breakEdge - b, b),
      rect(breakEdge, breakFront, b, front - b - breakFront),
      rect(left + b, breakFront - b, breakEdge - left - b, b),
      rect(left, maxY(elevator), b, breakFront - b - maxY(elevator)),
    ]
    const corners = [[right - b, back], [right - b, serveFront - b], [serveLeft - b, serveFront - b], [serveLeft - b, front - b],
      [breakEdge, front - b], [breakEdge, breakFront - b], [left, breakFront - b]]
    return { runs, corners }
  },
  make() {
    const root = new THREE.Group(); root.name = 'kitchen floor stone'
    const slab = (r, mat, name, lift, sideways = false) => {
      const [w, d] = sideways ? [r.h, r.w] : [r.w, r.h]
      const mesh = box(root, name, w, thickness, d, midX(r), top - thickness / 2 + lift, midY(r), mat)
      mesh.castShadow = false
      if (sideways) mesh.rotation.y = Math.PI / 2
    }
    const inner = this.inner
    slab(inner, floorMaterial('floor_field', [inner.w / (tile * 4), inner.h / (tile * 4)]), 'stone field', 0)
    const { runs, corners } = this.borderLayout()
    for (const run of runs) {
      const sideways = run.h > run.w, length = sideways ? run.h : run.w
      slab(run, floorMaterial('floor_border', [length / (band * 2), 1]), 'stone border', 0.0015, sideways)
    }
    const corner = floorMaterial('floor_border', [0.5, 1])
    for (const [x, z] of corners) slab(rect(x, z, band, band), corner, 'stone border corner', 0.002)
    const lounge = this.breakRoom
    slab(lounge, floorMaterial('floor_parquet', [lounge.w / this.parquet[0], lounge.h / this.parquet[1]], 0.45), 'break room parquet', 0.001)
    slab(this.rug, floorMaterial('floor_rug', [1, 1], 0.95), 'break room rug', 0.006)
    return root
  },
}

// MARK: Room

async function buildRoom() {
  const root = new THREE.Group(); root.name = 'kitchen-room'
  const m = (r, g, b) => new THREE.MeshStandardMaterial({ color: srgb(r, g, b), roughness: 0.85, metalness: 0 })
  const plaster = m(0.63, 0.65, 0.55), trim = m(0.16, 0.25, 0.21), stone = m(0.76, 0.73, 0.61), glass = m(0.47, 0.65, 0.69)
  const connectors = (await roots('KitchenStations/connectors.glb')).connectors
  if (connectors) {
    const node = connectors.clone(); node.name = 'connecting cabinets'; node.position.set(0, floorTop, 0)
    root.add(node)
  }
  root.add(KitchenFloor.make())
  const f = KitchenLayout.floor, back = f.y + 0.13
  box(root, 'back wall', f.w, 2.9, 0.22, midX(f), 1.55, back, plaster)
  box(root, 'back cornice', f.w, 0.14, 0.28, midX(f), 3.04, back + 0.02, trim)
  box(root, 'back skirting', f.w, 0.2, 0.28, midX(f), 0.24, back + 0.02, trim)
  const tiles = new THREE.InstancedMesh(new THREE.BoxGeometry(0.97, 0.34, 0.025), stone, 4 * f.w)
  tiles.name = 'backsplash tiles'; tiles.receiveShadow = true
  const matrix = new THREE.Matrix4()
  let i = 0
  for (let row = 0; row < 4; row++) for (let col = 0; col < f.w; col++) {
    tiles.setMatrixAt(i++, matrix.makeTranslation(f.x + 0.5 + col, 0.55 + row * 0.37, back + 0.125))
  }
  root.add(tiles)
  for (const x of [f.x + 0.15, maxX(f) - 0.15]) {
    box(root, 'low side wall', 0.26, 0.75, f.h - 0.3, x, 0.49, midY(f), plaster)
    box(root, 'side coping', 0.3, 0.09, f.h - 0.3, x, 0.91, midY(f), trim)
  }
  const window = 3.4
  box(root, 'window frame', 2.65, 1.8, 0.12, window, 1.96, back + 0.19, trim)
  box(root, 'window glass', 2.39, 1.54, 0.035, window, 1.96, back + 0.275, glass)
  box(root, 'window mullion', 0.075, 1.58, 0.06, window, 1.96, back + 0.31, trim)
  box(root, 'window crossbar', 2.42, 0.065, 0.06, window, 1.96, back + 0.31, trim)
  for (const wall of KitchenLayout.breakRoomWalls) {
    box(root, 'break room wall', wall.w, 1.0, wall.h, midX(wall), 0.6, midY(wall), plaster)
    box(root, 'break room coping', wall.w + 0.04, 0.07, wall.h + 0.04, midX(wall), 1.12, midY(wall), trim)
  }
  return root
}

// MARK: Stations

const marble = (() => {
  const canvas = document.createElement('canvas'); canvas.width = canvas.height = 512
  const g = canvas.getContext('2d')
  g.fillStyle = 'rgb(240,237,224)'; g.fillRect(0, 0, 512, 512)
  g.strokeStyle = 'rgba(133,135,122,0.16)'
  for (let i = 0; i < 12; i++) {
    const y = 512 - (i * 52 - 65)
    g.lineWidth = i % 3 === 0 ? 2.5 : 0.7
    g.beginPath(); g.moveTo(0, y); g.bezierCurveTo(150, y - 130, 340, y - 20, 512, y - 170); g.stroke()
  }
  const map = new THREE.CanvasTexture(canvas); map.colorSpace = THREE.SRGBColorSpace
  return new THREE.MeshStandardMaterial({ map, roughness: 0.38, metalness: 0 })
})()

/** The procedural counter (the app's stand-in, and the serving window's pass). */
function counter(a) {
  const root = new THREE.Group(); root.name = a.id
  root.scale.y = 1.25 * ChefMetrics.heightScale
  root.position.set(midX(a.footprint), floorTop, midY(a.footprint))
  const sideways = a.wall === 'left' || a.wall === 'right'
  const width = sideways ? a.footprint.h : a.footprint.w, depth = sideways ? a.footprint.w : a.footprint.h
  if (a.wall === 'left') root.rotation.y = Math.PI / 2
  if (a.wall === 'right') root.rotation.y = -Math.PI / 2
  const green = material(srgb(0.15, 0.25, 0.23)), ivory = material(srgb(0.84, 0.82, 0.74))
  const brass = material(srgb(0.66, 0.47, 0.23), 0.7), dark = material(srgb(0.055, 0.065, 0.06))
  const ceramic = material(srgb(0.96, 0.94, 0.86))
  const paint = ['stove', 'cooking', 'serving'].includes(a.id) ? green : ivory
  box(root, 'recessed plinth', width - 0.3, 0.18, depth - 0.3, 0, 0.07, 0, dark)
  box(root, 'cabinet carcass', width - 0.18, 0.7, depth - 0.18, 0, 0.51, 0, paint)
  box(root, 'stone worktop', width, 0.16, depth, 0, 0.92, 0, marble)
  const count = Math.max(2, Math.floor(width / 0.85)), bay = (width - 0.16) / count
  for (const side of a.wall === 'island' ? [-1, 1] : [1]) {
    const face = side * (depth / 2 - 0.08)
    for (let i = 0; i < count; i++) {
      const x = -width / 2 + 0.08 + bay * (i + 0.5)
      box(root, 'framed door', bay - 0.035, 0.66, 0.035, x, 0.51, face, paint)
      box(root, 'inset panel', bay - 0.15, 0.47, 0.025, x, 0.49, face - side * 0.012, paint === green ? ivory : paint)
      box(root, 'brass pull', 0.28, 0.055, 0.075, x, 0.76, face + side * 0.043, brass)
    }
  }
  if (a.id === 'serving') {
    const platters = Math.max(2, Math.floor(width / 1.5))
    for (let i = 0; i < platters; i++) cylinder(root, 'serving platter', 0.3, 0.03, -width / 2 + (i + 0.5) * width / platters, 1.025, 0.15, ceramic, 32)
  }
  return root
}

/** Elevator car opening onto the kitchen; its doors slide open for arrivals. */
function elevator(a) {
  const root = new THREE.Group(); root.name = a.id
  root.position.set(midX(a.footprint), floorTop, midY(a.footprint))
  const w = a.footprint.w, d = a.footprint.h, h = 2.9
  const frame = material(srgb(0.25, 0.27, 0.3), 0.5), steel = material(srgb(0.66, 0.66, 0.66), 0.85)
  const lamp = material(srgb(1, 0.78, 0.4)); lamp.emissive = srgb(1, 0.7, 0.3)
  box(root, 'elevator back', w, h, 0.12, 0, h / 2, -d / 2 + 0.06, frame)
  for (const x of [-w / 2 + 0.06, w / 2 - 0.06]) box(root, 'elevator side', 0.12, h, d, x, h / 2, 0, frame)
  box(root, 'elevator header', w, 0.42, 0.16, 0, h - 0.21, d / 2 - 0.08, frame)
  box(root, 'floor indicator', 0.5, 0.12, 0.03, 0, h - 0.2, d / 2 + 0.01, lamp)
  box(root, 'elevator floor', w - 0.24, 0.03, d - 0.12, 0, 0.015, 0, steel)
  root.userData.doors = [['elevator door left', -w / 4 + 0.03, -1], ['elevator door right', w / 4 - 0.03, 1]].map(([name, x, direction]) => {
    const door = box(root, name, w / 2 - 0.12, h - 0.46, 0.06, x, (h - 0.42) / 2, d / 2 - 0.05, steel)
    return { door, closed: x, slide: direction * (w / 2 - 0.2) }
  })
  return root
}

/** The break room: arcade cabinets, the vending machine and two lounge chairs across a walnut side table. */
async function breakTable(a) {
  const root = new THREE.Group(); root.name = a.id
  root.position.set(midX(a.footprint), floorTop, midY(a.footprint))
  const center = [midX(a.footprint), midY(a.footprint)]
  const walnut = material(srgb(0.34, 0.2, 0.1)), ceramic = material(srgb(0.96, 0.94, 0.86))
  const tableTop = 0.5, radius = a.footprint.w / 2
  cylinder(root, 'side table', radius, 0.05, 0, tableTop, 0, walnut, 32)
  cylinder(root, 'stem', 0.04, tableTop, 0, tableTop / 2, 0, walnut)
  cylinder(root, 'foot', radius * 0.6, 0.03, 0, 0.015, 0, walnut, 32)
  for (const x of [-0.09, 0.1]) cylinder(root, 'cup', 0.05, 0.09, x, tableTop + 0.07, x * 0.6, ceramic)
  const place = (node, point, facing, y = 0) => {
    node.rotation.y = facing
    node.position.set(point[0] - center[0], y, point[1] - center[1])
    root.add(node)
  }
  await Promise.all(BreakRoomLayout.machines.map(async (machine) => {
    const node = await model(`BreakRoom/${machine.asset}.glb`)
    node.name = 'break machine:' + machine.asset
    node.scale.setScalar(machine.scale)
    place(node, machine.center, machine.facing)
  }))
  const chair = await loungeChair()
  const bounds = new THREE.Box3().setFromObject(chair), scale = 1.45
  for (const seat of BreakRoomLayout.chairs) {
    const forward = [Math.sin(seat.facing), Math.cos(seat.facing)]
    const node = chair.clone(); node.name = 'lounge chair'; node.scale.setScalar(scale)
    place(node, [seat.stand[0] - forward[0] * 0.12, seat.stand[1] - forward[1] * 0.12], seat.facing, -bounds.min.y * scale)
  }
  return root
}

/** A modelled wall station (order, prep, tasting, pantry, the gong) at its footprint's centre. */
async function fixture(a) {
  const template = (await roots(`KitchenStations/${a.id}.glb`))[a.id]
  const root = new THREE.Group(); root.name = a.id
  root.position.set(midX(a.footprint), floorTop, midY(a.footprint))
  const node = template.clone()
  if (a.wall === 'right') node.rotation.y = -Math.PI / 2
  if (a.wall === 'left') node.rotation.y = Math.PI / 2
  root.add(node)
  if (a.id === 'bell') hangGong(node, root)
  return root
}

/** Moves the gong's meshes under a pivot at its `gong_pivot` anchor, so it can swing when struck. */
function hangGong(model, root) {
  const anchor = named(model, 'gong_pivot')
  if (!anchor) return
  const pivot = new THREE.Group(); pivot.name = 'gong pivot'
  pivot.position.copy(anchor.position)
  anchor.parent.add(pivot)
  root.updateMatrixWorld(true)
  const parts = []
  model.traverse((node) => { if (node.isMesh && [].concat(node.material).some((m) => m.name.startsWith('gong_'))) parts.push(node) })
  for (const part of parts) pivot.attach(part)
  root.userData.gong = pivot
}

/** A struck gong swings back on its cords and settles (first away from the mallet). */
export function strikeGong(pivot, now) {
  pivot.userData.swing = { start: now }
}
const swings = [0.16, -0.11, 0.07, -0.045, 0.025, -0.012, 0]
export function swingGong(pivot, now) {
  const swing = pivot.userData.swing
  if (!swing) return
  let t = now - swing.start, from = pivot.userData.from ?? 0
  for (let i = 0; i < swings.length; i++) {
    const duration = i === 0 ? 0.12 : 0.34
    if (t < duration) {
      const p = t / duration, ease = p < 0.5 ? 2 * p * p : 1 - (-2 * p + 2) ** 2 / 2
      pivot.rotation.x = from + (swings[i] - from) * ease
      return
    }
    t -= duration; from = swings[i]
  }
  pivot.rotation.x = 0; pivot.userData.swing = null
}

async function island(a) {
  const roots_ = await roots('KitchenStations/island.glb'), template = roots_.island
  const root = new THREE.Group(); root.name = a.id
  root.position.set(midX(a.footprint), floorTop, midY(a.footprint))
  root.add(template.clone())
  const oak = material(srgb(0.43, 0.26, 0.13), 0, 0.62)
  for (let i = 0; i < 6; i++) {
    const anchor = named(template, 'board_' + i)
    if (!anchor) continue
    const board = box(root, 'cutting board', 0.9, 0.035, 0.55, anchor.position.x, anchor.position.y + 0.0175, anchor.position.z, oak)
    board.userData.board = true
  }
  return root
}

async function stove(a) {
  const template = (await roots('KitchenStations/stove.glb')).stove
  const node = template.clone(); node.name = 'stove'
  node.position.set(midX(a.footprint), floorTop, midY(a.footprint))
  node.userData.burners = Array.from({ length: 6 }, (_, i) => named(template, 'burner_' + i)?.position.clone()).filter(Boolean)
    .map((p) => p.add(node.position))
  return node
}

async function station(a) {
  switch (a.id) {
    case 'elevator': return elevator(a)
    case 'break': return breakTable(a)
    case 'stove': return stove(a)
    case 'cooking': return island(a)
    case 'order': case 'prep': case 'tasting': case 'pantry': case 'bell': return fixture(a)
    default: return counter(a)
  }
}

// MARK: Restaurant and food

/** The dish for a task key: FNV-1a 64 plus a MurmurHash3 finalizer, so it's stable everywhere. */
export function dishFor(key, ids) {
  if (!ids.length) return null
  const m = (1n << 64n) - 1n
  let hash = 0xcbf29ce484222325n
  for (const byte of new TextEncoder().encode(key)) hash = ((hash ^ BigInt(byte)) * 0x100000001b3n) & m
  hash ^= hash >> 33n; hash = (hash * 0xff51afd7ed558ccdn) & m
  hash ^= hash >> 33n; hash = (hash * 0xc4ceb9fe1a85ec53n) & m
  hash ^= hash >> 33n
  return ids[Number(hash % BigInt(ids.length))]
}

export const foodIDs = ['cheeseburger', 'peking_duck', 'pizza', 'spaghetti']
export const propIDs = ['chopped_board', 'cleaver_board', 'connector_object', 'lightbulb', 'plan_plate', 'plugin_crate', 'salsa_jar', 'stove_pot']

async function restaurant(clock) {
  const template = (await roots('Restaurant/restaurant.glb')).restaurant
  const root = template.clone()
  root.updateMatrixWorld(true)
  const stands = {}, dishes = {}
  root.traverse((node) => {
    const name = node.userData.name ?? node.name
    if (name.startsWith('seat_')) stands[name.slice(5)] = node.getWorldPosition(new THREE.Vector3())
    if (name.startsWith('dish_')) dishes[name.slice(5)] = node.getWorldPosition(new THREE.Vector3())
    if (node.isMesh && (name === 'water' || name.startsWith('lily'))) node.castShadow = false
    if (name === 'water') node.traverse((mesh) => { if (mesh.isMesh) { mesh.castShadow = false; mesh.material = shimmer(mesh.material, clock) } })
  })
  const seats = Object.keys(stands).sort().filter((id) => dishes[id]).map((id) => {
    const stand = [stands[id].x, stands[id].z], dish = [dishes[id].x, dishes[id].y, dishes[id].z]
    return { id, stand, dish, facing: Math.atan2(dish[0] - stand[0], dish[2] - stand[1]) }
  })
  return { root, seats }
}

/** Gentle ripples of light on the canal. */
function shimmer(source, clock) {
  const m = source.clone()
  m.roughness = 0.38; m.metalness = 0
  m.onBeforeCompile = (shader) => {
    shader.uniforms.shimmerTime = clock
    shader.vertexShader = shader.vertexShader.replace('#include <common>', '#include <common>\nvarying vec2 vShimmer;')
      .replace('#include <uv_vertex>', '#include <uv_vertex>\nvShimmer = uv;')
    shader.fragmentShader = shader.fragmentShader.replace('#include <common>', '#include <common>\nvarying vec2 vShimmer;\nuniform float shimmerTime;')
      .replace('#include <color_fragment>', `#include <color_fragment>
        vec2 p = vShimmer * 140.0;
        float t = shimmerTime;
        float wave = sin(p.x * 0.9 + t * 0.8) * sin(p.y * 0.7 - t * 0.6) + 0.5 * sin((p.x + p.y) * 1.7 + t * 1.3);
        diffuseColor.rgb *= 0.94 + 0.08 * wave;
        diffuseColor.rgb += vec3(0.05, 0.08, 0.08) * smoothstep(0.9, 1.4, wave);`)
  }
  return m
}

// MARK: Light

function light(scene) {
  const k = Math.PI / 1000
  const ambient = new THREE.AmbientLight(srgb(1, 0.97, 0.91), 180 * k)
  scene.add(ambient)
  const sun = new THREE.DirectionalLight(0xffffff, 1100 * k)
  sun.position.set(-8, 12, -5); sun.target.position.set(0, 0, 0)
  sun.castShadow = true
  sun.shadow.mapSize.set(4096, 4096)
  const s = sun.shadow.camera
  s.left = -24; s.right = 24; s.top = 24; s.bottom = -24; s.near = 0.5; s.far = 60
  sun.shadow.bias = -0.0004; sun.shadow.normalBias = 0.02
  sun.shadow.intensity = 0.62
  sun.shadow.radius = 4
  scene.add(sun, sun.target)
  const fill = new THREE.DirectionalLight(srgb(0.82, 0.89, 1), 240 * k)
  fill.position.set(8, 6, 8)
  scene.add(fill)
  return { ambient, sun, fill }
}

/** Everything that isn't a person: the room, the stations, the restaurant, the light. */
export async function buildKitchen(scene, clock) {
  if (isOffice) return buildOffice(scene)
  scene.background = srgb(0.55, 0.78, 0.86)
  const floor = new THREE.Mesh(new THREE.BoxGeometry(KitchenLayout.floor.w, 0.2, KitchenLayout.floor.h),
    new THREE.MeshStandardMaterial({ color: srgb(0.71, 0.71, 0.71), roughness: 0.9 }))
  floor.name = 'Kitchen floor'; floor.receiveShadow = true
  scene.add(floor)
  const [room, outside, stationList, food, props] = await Promise.all([
    buildRoom(), restaurant(clock), Promise.all(areas.map(station)),
    Promise.all(foodIDs.map((id) => model(`Food/${id}.glb`))), Promise.all(propIDs.map((id) => model(`KitchenProps/${id}.glb`))),
  ])
  scene.add(room, outside.root)
  const stations = {}
  stationList.forEach((node, i) => { stations[areas[i].id] = node; scene.add(node) })
  const lights = light(scene)
  return {
    stations, seats: outside.seats, lights,
    food: Object.fromEntries(foodIDs.map((id, i) => [id, food[i]])),
    props: Object.fromEntries(propIDs.map((id, i) => [id, props[i]])),
  }
}

export { SceneLayout, load }
