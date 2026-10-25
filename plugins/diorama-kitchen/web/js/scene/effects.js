// The stations' live details (the app's BurnerFlames and IdleBoards): a burner lights under a chef
// watching its command cook, and each cutting board shows the resting cleaver until a chef reaches it.

import * as THREE from 'three'
import { SceneLayout, ChefMetrics } from './layout.js'
import { dist } from './layout.js'

/** One flame per stove slot, on the range's burner crowns. */
export class BurnerFlames {
  constructor(scene, stove, particles) {
    this.flames = new Map()
    const burners = stove?.userData.burners ?? []
    const hot = new THREE.MeshBasicMaterial({ color: new THREE.Color().setRGB(1, 0.5, 0.11, THREE.SRGBColorSpace), transparent: true, opacity: 0.85,
      blending: THREE.AdditiveBlending, depthWrite: false })
    const footprint = SceneLayout.areas.find((a) => a.id === 'stove').footprint
    ;(SceneLayout.chefSlots.stove ?? []).forEach((slot, index) => {
      const at = burners[index] ?? new THREE.Vector3(slot.stand[0], ChefMetrics.worktopHeight + 0.04, footprint.y + footprint.h / 2)
      const node = new THREE.Group(); node.name = 'burner flame'; node.visible = false
      node.position.copy(at)
      // A steady glow (also shown under reduced motion) plus rising sparks.
      const cone = new THREE.Mesh(new THREE.ConeGeometry(0.17, 0.3, 24, 1, true), hot)
      cone.position.y = 0.16; cone.renderOrder = 9
      node.add(cone); scene.add(node)
      const fire = particles.emitter({ object: node, rate: 0, life: 0.45, lifeVariation: 0.15, size: 0.11, sizeVariation: 0.04,
        velocity: 0.9, velocityVariation: 0.3, spread: 18, ring: 0.155, color: [1, 0.52, 0.12], colorVariation: [0.04, 0.1, 0],
        opacity: [[0, 1, 0.6, 0], [0, 0.15, 0.6, 1]], sizeCurve: [[1, 0.8, 0.2], [0, 0.5, 1]] })
      this.flames.set(slot.id, { node, fire })
    })
  }
  update(chefs, reduced) {
    const lit = new Set(chefs.filter((c) => c.station?.area === 'stove' && c.clip === 'waiting_tool').map((c) => c.station.id))
    for (const [id, flame] of this.flames) {
      const on = lit.has(id)
      flame.node.visible = on
      flame.fire.rate = on && !reduced ? 140 : 0
    }
  }
}

/** Per cooking slot: the plain board a chef chops on, and the cleaver-on-board model while nobody is there. */
export class IdleBoards {
  constructor(island, template) {
    this.boards = new Map()
    if (!island || !template) return
    const slots = SceneLayout.chefSlots.cooking ?? []
    island.updateMatrixWorld(true)
    for (const plain of island.children.filter((n) => n.userData.board)) {
      const x = plain.getWorldPosition(new THREE.Vector3()).x
      let slot = null
      for (const s of slots) if (!slot || Math.abs(s.stand[0] - x) < Math.abs(slot.stand[0] - x)) slot = s
      if (!slot || this.boards.has(slot.id)) continue
      const box = plain.geometry.parameters
      const idle = template.clone(); idle.name = 'idle cutting board'
      idle.traverse((n) => { if (n.isMesh) { n.castShadow = true; n.receiveShadow = true } })
      idle.scale.setScalar(box.width)
      idle.position.set(plain.position.x, plain.position.y - box.height / 2, plain.position.z)
      island.add(idle)
      plain.visible = false
      this.boards.set(slot.id, { plain, idle })
    }
  }
  update(chefs) {
    const busy = new Set(), chopped = new Set()
    for (const chef of chefs) {
      if (chef.station?.area !== 'cooking' || dist(chef.position, chef.station.stand) >= 0.35) continue
      busy.add(chef.station.id)
      if (chef.choppingOnBoard) chopped.add(chef.station.id)
    }
    for (const [id, board] of this.boards) {
      const used = busy.has(id)
      board.plain.visible = used && !chopped.has(id)
      board.idle.visible = !used
    }
  }
}
