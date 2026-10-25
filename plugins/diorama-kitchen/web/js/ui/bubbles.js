// A small speech bubble over a chef in the break room (the app's ChefBubbleView): one emoji in a
// white rounded bubble with a tail. It pops in, holds, then fades.

export const bubbleSize = { w: 38, h: 36 }
const hold = 2.6

export class ChefBubble {
  constructor(parent) {
    this.root = document.createElement('div'); this.root.className = 'bubble'
    this.root.setAttribute('aria-hidden', 'true')
    this.body = document.createElement('div'); this.body.className = 'bubble-body'; this.root.appendChild(this.body)
    this.label = document.createElement('span'); this.body.appendChild(this.label)
    parent.appendChild(this.root)
    this.until = 0
  }
  get emoji() { return this.label.textContent }
  show(emoji, now, reducedMotion) {
    this.label.textContent = emoji
    this.until = now + hold
    this.root.style.opacity = 1
    if (reducedMotion) return
    this.body.animate([{ transform: 'scale(0.2)' }, { transform: 'scale(1.15)', offset: 0.5 }, { transform: 'scale(0.95)', offset: 0.8 }, { transform: 'scale(1)' }],
      { duration: 350 })
  }
  /** Fades over the last half second; false once it is gone. */
  update(now) {
    const left = this.until - now
    if (left <= 0) return false
    this.root.style.opacity = Math.min(1, left / 0.5)
    return true
  }
  place(x, y) { this.root.style.transform = `translate(${Math.round(x)}px, ${Math.round(y)}px)` }
  remove() { this.root.remove() }
}
