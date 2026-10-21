import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["output", "event", "latest", "unread"]

  connect() {
    this.pinned = true
    this.unread = 0
    this.known = new Set(this.eventTargets.map(event => event.id))
    this.resizeObserver = new ResizeObserver(() => {
      if (this.pinned && !this.rendering) this.follow()
    })
    this.resizeObserver.observe(this.outputTarget)
    this.follow()
  }

  disconnect() {
    this.resizeObserver?.disconnect()
  }

  beforeRender(event) {
    if (!event.detail.content.contains(this.element)) return
    this.rendering = true
    this.previousScroll = this.outputTarget.scrollTop
    const top = this.outputTarget.getBoundingClientRect().top
    const anchor = this.eventTargets.find(entry => entry.getBoundingClientRect().bottom > top)
    this.anchor = anchor ? { id: anchor.id, offset: anchor.getBoundingClientRect().top - top } : null
  }

  afterRender(event) {
    if (!event.detail.content.contains(this.element)) return
    const added = this.eventTargets.filter(entry => !this.known.has(entry.id))
    this.known = new Set(this.eventTargets.map(entry => entry.id))
    if (this.pinned) this.follow()
    else {
      this.unread += added.length
      this.outputTarget.scrollTop = this.previousScroll
      const anchor = this.anchor && document.getElementById(this.anchor.id)
      if (anchor) {
        this.outputTarget.scrollTop += anchor.getBoundingClientRect().top - this.outputTarget.getBoundingClientRect().top - this.anchor.offset
      }
      this.updateFollow()
    }
    this.rendering = false
  }

  track() {
    if (this.rendering) return
    const output = this.outputTarget
    this.pinned = output.scrollHeight - output.scrollTop - output.clientHeight < 32
    if (this.pinned) this.unread = 0
    this.updateFollow()
  }

  updateFollow() {
    this.latestTarget.hidden = this.pinned || this.eventTargets.length === 0
    this.unreadTarget.textContent = this.unread ? `${this.unread} ${this.unread === 1 ? "nueva acción" : "nuevas acciones"}` : "Últimas acciones"
    this.latestTarget.setAttribute("aria-label", "Ir a las últimas acciones")
  }

  follow() {
    this.outputTarget.scrollTop = this.outputTarget.scrollHeight
    this.pinned = true
    this.unread = 0
    this.updateFollow()
  }
}
