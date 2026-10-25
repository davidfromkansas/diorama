// Small CPU particle bursts, like the app's SCNParticleSystems: burner flames and the sparkle puffs
// when a carried item appears or is set down. One Points mesh draws every particle.

import * as THREE from 'three'

const max = 4000
const vertex = `
attribute float size;
attribute float alpha;
attribute vec3 tint;
varying float vAlpha;
varying vec3 vTint;
uniform float scale;
void main() {
  vAlpha = alpha; vTint = tint;
  vec4 view = modelViewMatrix * vec4(position, 1.0);
  gl_PointSize = size * scale / -view.z;
  gl_Position = projectionMatrix * view;
}`
const fragment = `
varying float vAlpha;
varying vec3 vTint;
void main() {
  float d = length(gl_PointCoord - 0.5) * 2.0;
  float glow = clamp(1.0 - d, 0.0, 1.0);
  gl_FragColor = vec4(vTint * glow * vAlpha, 1.0);
}`

const curve = (keys, times, t) => {
  for (let i = 1; i < times.length; i++) {
    if (t <= times[i]) { const p = (t - times[i - 1]) / (times[i] - times[i - 1]); return keys[i - 1] + (keys[i] - keys[i - 1]) * p }
  }
  return keys[keys.length - 1]
}

export class Particles {
  constructor(scene) {
    this.geometry = new THREE.BufferGeometry()
    this.positions = new Float32Array(max * 3); this.sizes = new Float32Array(max); this.alphas = new Float32Array(max); this.tints = new Float32Array(max * 3)
    this.geometry.setAttribute('position', new THREE.BufferAttribute(this.positions, 3).setUsage(THREE.DynamicDrawUsage))
    this.geometry.setAttribute('size', new THREE.BufferAttribute(this.sizes, 1).setUsage(THREE.DynamicDrawUsage))
    this.geometry.setAttribute('alpha', new THREE.BufferAttribute(this.alphas, 1).setUsage(THREE.DynamicDrawUsage))
    this.geometry.setAttribute('tint', new THREE.BufferAttribute(this.tints, 3).setUsage(THREE.DynamicDrawUsage))
    this.material = new THREE.ShaderMaterial({ vertexShader: vertex, fragmentShader: fragment, uniforms: { scale: { value: 800 } },
      blending: THREE.AdditiveBlending, depthWrite: false, transparent: true })
    this.points = new THREE.Points(this.geometry, this.material)
    this.points.frustumCulled = false; this.points.renderOrder = 10
    scene.add(this.points)
    this.live = []
    this.emitters = new Set()
  }
  /** Scales point sizes to the view (`height` pixels for a 38° field of view). */
  resize(height) { this.material.uniforms.scale.value = height / (2 * Math.tan(19 * Math.PI / 180)) }

  /** A continuous emitter (a burner flame); set `rate` to 0 to stop it. */
  emitter(options) { const e = { carry: 0, rate: 0, ...options }; this.emitters.add(e); return e }
  remove(emitter) { this.emitters.delete(emitter) }

  /** A one-off burst: `count` particles at a world point. */
  burst(options) { this.emitters.add({ ...options, carry: 0, burst: options.duration }) }

  spawn(e, origin) {
    if (this.live.length >= max) return
    const spread = (e.spread ?? 0) * Math.PI / 180
    const theta = Math.random() * Math.PI * 2, phi = Math.acos(1 - Math.random() * (1 - Math.cos(spread)))
    const speed = e.velocity + (Math.random() * 2 - 1) * (e.velocityVariation ?? 0)
    const dir = [Math.sin(phi) * Math.cos(theta) * speed, Math.cos(phi) * speed, Math.sin(phi) * Math.sin(theta) * speed]
    let p = [origin.x, origin.y, origin.z]
    if (e.ring) { const a = Math.random() * Math.PI * 2; p = [p[0] + Math.cos(a) * e.ring, p[1], p[2] + Math.sin(a) * e.ring] }
    const c = e.color, v = e.colorVariation ?? [0, 0, 0]
    this.live.push({
      p, v: dir, age: 0, life: Math.max(0.05, e.life + (Math.random() * 2 - 1) * (e.lifeVariation ?? 0)),
      size: e.size + (Math.random() * 2 - 1) * (e.sizeVariation ?? 0), accel: e.acceleration ?? 0,
      tint: [c[0] + (Math.random() * 2 - 1) * v[0], c[1] + (Math.random() * 2 - 1) * v[1], c[2] + (Math.random() * 2 - 1) * v[2]],
      opacity: e.opacity, sizeCurve: e.sizeCurve,
    })
  }

  update(dt) {
    const origin = new THREE.Vector3()
    for (const e of [...this.emitters]) {
      if (e.wait > 0) { e.wait -= dt; continue }
      if (e.burst != null) {
        e.carry += e.rate * Math.min(dt, e.burst)
        e.burst -= dt
        if (e.burst <= 0) this.emitters.delete(e)
      } else e.carry += e.rate * dt
      if (e.carry < 1) continue
      if (e.object) e.object.getWorldPosition(origin); else origin.set(...e.position)
      while (e.carry >= 1) { e.carry -= 1; this.spawn(e, origin) }
    }
    const kept = []
    for (const q of this.live) {
      q.age += dt
      if (q.age >= q.life) continue
      q.v[1] += q.accel * dt
      q.p[0] += q.v[0] * dt; q.p[1] += q.v[1] * dt; q.p[2] += q.v[2] * dt
      kept.push(q)
    }
    this.live = kept
    kept.forEach((q, i) => {
      const t = q.age / q.life
      this.positions.set(q.p, i * 3)
      this.sizes[i] = q.size * (q.sizeCurve ? curve(q.sizeCurve[0], q.sizeCurve[1], t) : 1)
      this.alphas[i] = q.opacity ? curve(q.opacity[0], q.opacity[1], t) : 1 - t
      this.tints.set(q.tint, i * 3)
    })
    this.geometry.setDrawRange(0, kept.length)
    for (const name of ['position', 'size', 'alpha', 'tint']) this.geometry.attributes[name].needsUpdate = true
  }
}
