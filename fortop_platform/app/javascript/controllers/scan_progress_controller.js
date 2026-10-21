import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["content", "error"]
  static values = { url: String, active: Boolean }

  connect() {
    this.stopped = false
    this.failures = 0
    if (this.activeValue) this.schedule(1500)
  }

  disconnect() {
    this.stopped = true
    clearTimeout(this.timer)
    this.abortController?.abort()
  }

  schedule(delay = 2500) {
    if (!this.stopped && this.activeValue) this.timer = setTimeout(() => this.refresh(), delay)
  }

  async refresh() {
    if (document.hidden) {
      this.schedule(5000)
      return
    }

    this.abortController = new AbortController()
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "application/json" }, credentials: "same-origin",
        signal: this.abortController.signal
      })
      if (response.redirected) {
        window.location.assign(response.url)
        return
      }
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const result = await response.json()
      if (this.stopped) return
      const openFindings = Array.from(this.contentTarget.querySelectorAll("details[open]")).map((element) => element.querySelector("summary")?.textContent)
      const template = document.createElement("template")
      template.innerHTML = result.html
      Turbo.morphChildren(this.contentTarget, template.content)
      this.contentTarget.querySelectorAll("details").forEach((element) => {
        if (openFindings.includes(element.querySelector("summary")?.textContent)) element.open = true
      })
      this.activeValue = result.active
      this.errorTarget.hidden = true
      this.failures = 0
    } catch (error) {
      if (error.name === "AbortError" || this.stopped) return
      this.failures += 1
      if (this.failures >= 2) this.errorTarget.hidden = false
    }
    this.schedule(Math.min(2500 * (this.failures + 1), 15000))
  }
}
