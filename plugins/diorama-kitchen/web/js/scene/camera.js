// The kitchen's camera (the app's KitchenCameraController and DioramaSceneView framing): a home
// view fitted to the stations, scroll to zoom up to 3×, arrow keys to move while zoomed in, Q/W
// to turn, R to go home, and a follow pose for the selected chef.

import { isOffice } from './theme.js'

export const elevationDegrees = 40
/** The home view's angle: the kitchen is seen square on; the office from its front-left corner, like a diorama. */
export const homeView = isOffice ? { yaw: -38 * Math.PI / 180, elevation: 33 } : { yaw: 0, elevation: elevationDegrees }
const maxZoom = 3, zoomSensitivity = 0.012, maxZoomStep = 0.25, moveSpeed = 8, turnSpeed = Math.PI / 4, maxStep = 0.05
export const cameraEase = 0.35

export class CameraController {
  constructor() {
    this.homeCenter = [0, 0]; this.homeDistance = 30
    this.elevation = homeView.elevation * Math.PI / 180
    this.homeYaw = homeView.yaw
    this.lookHeight = 0.65
    this.bounds = { minX: -20, maxX: 20, minZ: -9, maxZ: 15.5 }
    this.pose = { center: [0, 0], zoom: 1, yaw: this.homeYaw }
    this.held = new Set()
  }
  get isHome() { return this.pose.zoom <= 1.0001 && this.pose.yaw === this.homeYaw && this.pose.center[0] === this.homeCenter[0] && this.pose.center[1] === this.homeCenter[1] }
  get isZoomedIn() { return this.pose.zoom > 1.0001 }
  get look() { return [this.pose.center[0], this.lookHeight, this.pose.center[1]] }
  get eye() {
    const d = this.homeDistance / this.pose.zoom, look = this.look, e = this.elevation, y = this.pose.yaw
    return [look[0] + Math.sin(y) * Math.cos(e) * d, look[1] + Math.sin(e) * d, look[2] + Math.cos(y) * Math.cos(e) * d]
  }
  setHome(center, distance) {
    const wasHome = !this.isZoomedIn && this.pose.center[0] === this.homeCenter[0] && this.pose.center[1] === this.homeCenter[1]
    this.homeCenter = center; this.homeDistance = distance
    if (wasHome) this.pose.center = [...center]
    this.validate()
  }
  scroll(delta) {
    const step = Math.max(-maxZoomStep, Math.min(maxZoomStep, delta * zoomSensitivity))
    const zoom = Math.min(maxZoom, Math.max(1, this.pose.zoom * Math.exp(step)))
    this.pose.zoom = zoom
    if (zoom <= 1.0001) { this.pose.zoom = 1; this.pose.center = [...this.homeCenter]; this.held.clear() }
    this.validate()
  }
  step(delta) {
    const dt = Math.min(maxStep, Math.max(0, delta))
    if (!(dt > 0) || !this.held.size) return
    if (this.held.has('turnLeft')) this.pose.yaw -= turnSpeed * dt
    if (this.held.has('turnRight')) this.pose.yaw += turnSpeed * dt
    if (this.isZoomedIn) {
      const input = [0, 0]
      if (this.held.has('up')) input[1] -= 1
      if (this.held.has('down')) input[1] += 1
      if (this.held.has('left')) input[0] -= 1
      if (this.held.has('right')) input[0] += 1
      const length = Math.hypot(input[0], input[1])
      if (length > 0) {
        const d = [input[0] / length, input[1] / length], y = this.pose.yaw
        const world = [d[0] * Math.cos(y) + d[1] * Math.sin(y), -d[0] * Math.sin(y) + d[1] * Math.cos(y)]
        const b = this.bounds
        this.pose.center = [
          Math.min(b.maxX, Math.max(b.minX, this.pose.center[0] + world[0] * moveSpeed * dt)),
          Math.min(b.maxZ, Math.max(b.minZ, this.pose.center[1] + world[1] * moveSpeed * dt)),
        ]
      }
    }
    this.validate()
  }
  reset() { this.pose = { center: [...this.homeCenter], zoom: 1, yaw: this.homeYaw }; this.held.clear() }
  validate() {
    const values = [this.pose.center[0], this.pose.center[1], this.pose.zoom, this.pose.yaw, this.homeDistance]
    if (values.some((v) => !Number.isFinite(v)) || this.homeDistance <= 0) {
      if (!Number.isFinite(this.homeDistance) || this.homeDistance <= 0) this.homeDistance = 30
      this.reset()
    }
  }
}

/** The follow camera keeps the overview's angle, closer in, aimed at the chef's chest. */
export function followPose(position) {
  const e = homeView.elevation * Math.PI / 180, d = 8.5, y = homeView.yaw
  const look = [position.x, position.y + 1.2, position.z]
  return { eye: [look[0] + Math.sin(y) * d * Math.cos(e), look[1] + d * Math.sin(e), look[2] + Math.cos(y) * d * Math.cos(e)], look }
}

/** The home distance that fits every point (world [x, y, z]) in a `width`×`height` view. */
export function fitDistance(points, width, height) {
  const e = homeView.elevation * Math.PI / 180, yaw = homeView.yaw
  const tangentY = Math.tan(19 * Math.PI / 180), tangentX = tangentY * width / height
  const availableX = Math.max(0.1, 1 - 20 / width), availableY = Math.max(0.1, 1 - 56 / height)
  return points.reduce((distance, [wx, py, wz]) => {
    // Into the home view's frame: x across the screen, z toward the camera.
    const x = wx * Math.cos(yaw) - wz * Math.sin(yaw), z = wx * Math.sin(yaw) + wz * Math.cos(yaw)
    const y = py - 0.65
    const cameraY = y * Math.cos(e) - z * Math.sin(e), towardCamera = y * Math.sin(e) + z * Math.cos(e)
    return Math.max(distance, towardCamera + Math.abs(x) / (tangentX * availableX), towardCamera + Math.abs(cameraY) / (tangentY * availableY))
  }, 5)
}
