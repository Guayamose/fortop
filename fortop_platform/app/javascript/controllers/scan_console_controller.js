import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["output", "latest"]

  connect() {
    this.pinned = true
    this.observer = new MutationObserver(() => {
      if (this.pinned) this.follow()
      else this.latestTarget.hidden = false
    })
    this.observer.observe(this.outputTarget, { childList: true, subtree: true, characterData: true })
    this.follow()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  track() {
    const output = this.outputTarget
    this.pinned = output.scrollHeight - output.scrollTop - output.clientHeight < 32
    this.latestTarget.hidden = this.pinned
  }

  follow() {
    this.outputTarget.scrollTop = this.outputTarget.scrollHeight
    this.pinned = true
    this.latestTarget.hidden = true
  }
}
