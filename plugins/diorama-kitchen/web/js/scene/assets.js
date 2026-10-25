// Loads the kitchen's models once (the same GLBs the Mac app bundles) and hands out clones:
// stations, props, food, the break room's machines and chair, the restaurant, and the chef rigs
// with their characters (every character shares the original chef's skeleton and clips).

import * as THREE from 'three'
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js'
import { OBJLoader } from 'three/addons/loaders/OBJLoader.js'
import * as SkeletonUtils from 'three/addons/utils/SkeletonUtils.js'

const base = '/assets/'
const gltf = new GLTFLoader()
const cache = new Map()

/** A colour given in sRGB components, as the app's NSColors are. */
export const srgb = (r, g, b) => new THREE.Color().setRGB(r, g, b, THREE.SRGBColorSpace)

/** Three's glTF materials made to read like the app's: SceneKit took factors as sRGB, and an embedded texture won over its factor. */
const adapted = new WeakSet()
function adapt(material) {
  if (!material.isMeshStandardMaterial || adapted.has(material)) return
  adapted.add(material)
  if (material.map) material.color.setRGB(1, 1, 1)
  else material.color.setRGB(material.color.r, material.color.g, material.color.b, THREE.SRGBColorSpace)
  if (material.metalnessMap) { material.metalness = 1; material.roughness = 1 }
  if (material.emissive && (material.emissive.r || material.emissive.g || material.emissive.b)) {
    const k = material.emissiveIntensity || 1
    material.emissive.setRGB(Math.min(1, material.emissive.r * k), Math.min(1, material.emissive.g * k), Math.min(1, material.emissive.b * k), THREE.SRGBColorSpace)
    material.emissiveIntensity = 1
  }
  if (material.name === 'status_light') material.emissive = srgb(0.35, 1, 0.62)
}

const kept = new WeakSet()
/** SceneKit lights both sides of a double-sided surface with its stored normal; three flips it for back faces. */
export function keepNormals(material) {
  if (material.side !== THREE.DoubleSide || kept.has(material)) return
  kept.add(material)
  const previous = material.onBeforeCompile
  material.onBeforeCompile = (shader, renderer) => {
    previous?.call(material, shader, renderer)
    shader.fragmentShader = shader.fragmentShader.replace('#include <normal_fragment_begin>',
      THREE.ShaderChunk.normal_fragment_begin.replace('float faceDirection = gl_FrontFacing ? 1.0 : - 1.0;', 'float faceDirection = 1.0;'))
  }
  const key = material.customProgramCacheKey.bind(material)
  material.customProgramCacheKey = () => key() + '|keepNormals'
}

function prepare(object) {
  object.traverse((node) => {
    if (!node.isMesh) return
    node.castShadow = true; node.receiveShadow = true
    for (const material of [].concat(node.material)) { adapt(material); keepNormals(material) }
  })
}

export function load(path) {
  if (!cache.has(path)) {
    cache.set(path, gltf.loadAsync(base + path).then((result) => { prepare(result.scene); return result }))
  }
  return cache.get(path)
}

/** A static GLB's top-level nodes by name (as the app's GLBStaticMeshes reads them). */
export async function roots(path) {
  const result = await load(path)
  return Object.fromEntries(result.scene.children.map((child) => [child.userData.name ?? child.name, child]))
}

/** Every top-level node of a model folder's GLB, grouped as one template (the app's KitchenFood.models). */
export async function model(path) {
  const result = await load(path)
  const group = new THREE.Group()
  for (const child of result.scene.children) group.add(child.clone())
  return group
}

/** Finds a node by its glTF name (three sanitizes "hand.L" to "handL"). */
export function named(root, name) {
  const clean = THREE.PropertyBinding.sanitizeNodeName(name)
  let found = null
  root.traverse((node) => { if (!found && (node.userData.name === name || node.name === clean || node.name === name)) found = node })
  return found
}

// MARK: The lounge chair

let chair = null
export async function loungeChair() {
  if (chair) return chair
  const object = await new OBJLoader().loadAsync(base + 'BreakRoom/EamesLoungeLow.obj')
  object.traverse((node) => {
    if (!node.isMesh) return
    node.castShadow = true; node.receiveShadow = true
    const make = (source) => {
      const part = source?.name || node.name || ''
      const upholstery = part.includes('FABRIC'), shell = part.includes('SHELL')
      const m = new THREE.MeshStandardMaterial({
        name: part, color: shell ? srgb(0.34, 0.2, 0.1) : srgb(0.07, 0.07, 0.07),
        roughness: upholstery ? 0.92 : 0.65, metalness: !upholstery && !shell ? 0.3 : 0, side: THREE.DoubleSide,
      })
      keepNormals(m)
      return m
    }
    node.material = Array.isArray(node.material) ? node.material.map(make) : make(node.material)
  })
  chair = object
  return chair
}

// MARK: Chefs

export class ChefAssets {
  static async load() {
    const json = (path) => fetch(base + path).then((r) => r.json())
    const [manifest, variants, staff, guests, rig, props] = await Promise.all([
      json('Chef/chef-manifest.json'), json('Chef/chef-variants.json'), json('Chef/staff-list.json'),
      json('Restaurant/guest-list.json'), load('Chef/chef-animated.glb'), roots('Chef/chef-props.glb'),
    ])
    return new ChefAssets(manifest, variants, staff, guests, rig, props)
  }
  constructor(manifest, variants, staff, guests, rig, props) {
    this.manifest = manifest
    this.base = rig
    this.clips = Object.fromEntries(rig.animations.map((clip) => [clip.name, clip]))
    this.props = props
    this.characters = [{ id: 'classic', path: 'Chef/chef-animated.glb' }, ...variants.characters.map((c) => ({ id: c.id, path: 'Chef/' + c.asset }))]
    this.guests = guests.characters.map((c) => ({ id: 'guest:' + c.id, path: 'Restaurant/' + c.asset }))
    this.staff = staff.characters.map((c) => ({ id: 'staff:' + c.id, path: 'Chef/' + c.asset }))
    this.loaded = new Map([['classic', Promise.resolve(rig)]]); this.ready = new Map([['classic', rig]])
  }
  /** Loads every character in the background, so a new chef rarely waits on its file. */
  preload() {
    for (const c of [...this.characters, ...this.guests, ...this.staff]) this.rig(c.id)
  }
  /** A character's model (its own mesh and textures on the chef's skeleton); the original chef stands in for one that can't load. */
  rig(id) {
    if (!this.loaded.has(id)) {
      const entry = [...this.characters, ...this.guests, ...this.staff].find((c) => c.id === id)
      const loading = entry ? load(entry.path).catch(() => this.base) : Promise.resolve(this.base)
      this.loaded.set(id, loading.then((result) => { this.ready.set(id, result); return result }))
    }
    return this.loaded.get(id)
  }
  /** Loads every character and waits for them, so chefs can be made without waiting. */
  async preloadAll() { await Promise.all([...this.characters, ...this.guests, ...this.staff].map((c) => this.rig(c.id))) }
  /** A fresh skinned instance of a loaded character (the original chef until its own has loaded), with its own skeleton. */
  instance(id) {
    if (!this.ready.has(id)) this.rig(id)
    const source = this.ready.get(id) ?? this.base
    const root = SkeletonUtils.clone(source.scene)
    root.traverse((node) => {
      if (!node.isMesh) return
      node.castShadow = true; node.receiveShadow = true; node.frustumCulled = false
      // Each chef fades on its own (selection dims the others).
      node.material = [].concat(node.material).map((m) => { const copy = m.clone(); copy.side = THREE.DoubleSide; keepNormals(copy); return copy })
      if (node.material.length === 1) node.material = node.material[0]
    })
    return root
  }
}
