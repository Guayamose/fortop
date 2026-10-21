import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["content", "error", "filters", "dialog", "evidence"]
  static values = { url: String, active: Boolean }

  connect() {
    this.stopped = false
    this.failures = 0
    this.schedule(1800)
    this.onClose = () => { if (this.opener?.isConnected) this.opener.focus() }
    this.dialogTarget.addEventListener("close", this.onClose)
  }

  disconnect() {
    this.stopped = true
    clearTimeout(this.timer)
    this.request?.abort()
    this.dialogTarget.removeEventListener("close", this.onClose)
    if (this.dialogTarget.open) this.dialogTarget.close()
  }

  schedule(delay = 2500) {
    clearTimeout(this.timer)
    if (!this.stopped && this.activeValue) this.timer = setTimeout(() => this.refresh(), delay)
  }

  filter(event) {
    event.preventDefault()
    this.refresh(true)
  }

  async refresh(filtered = false) {
    clearTimeout(this.timer)
    if (!filtered && (document.hidden || this.dialogTarget.open)) return this.schedule(5000)
    this.request?.abort()
    const request = new AbortController()
    this.request = request
    const url = new URL(this.urlValue, window.location.origin)
    if (this.hasFiltersTarget) {
      for (const [key, value] of new FormData(this.filtersTarget)) {
        if (key !== "commit" && key !== "study_id") url.searchParams.set(key, value)
      }
    }
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" }, credentials: "same-origin", signal: request.signal })
      if (response.redirected) { window.location.assign(response.url); return }
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const result = await response.json()
      if (this.stopped || request.signal.aborted) return
      const open = Array.from(this.contentTarget.querySelectorAll("details[open][id]")).map(node => node.id)
      const template = document.createElement("template")
      template.innerHTML = result.html
      this.dispatch("before-render", { prefix: "scan-progress", detail: { content: this.contentTarget } })
      Turbo.morphChildren(this.contentTarget, template.content)
      this.dispatch("after-render", { prefix: "scan-progress", detail: { content: this.contentTarget } })
      open.forEach(id => { const node = document.getElementById(id); if (node) node.open = true })
      this.activeValue = result.active
      if (result.study_id) url.searchParams.set("study_id", result.study_id)
      this.urlValue = url.toString()
      if (filtered) {
        const browser = new URL(window.location.href)
        browser.search = url.search
        browser.searchParams.delete("follow_restart")
        window.history.replaceState({}, "", browser)
      }
      this.failures = 0
      this.errorTarget.hidden = true
    } catch (error) {
      if (error.name === "AbortError" || this.stopped) return
      this.failures++
      if (this.failures >= 2 || filtered) this.errorTarget.hidden = false
    }
    this.schedule(Math.min(2500 * (this.failures + 1), 15000))
  }

  openEvidence(event) {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    event.preventDefault()
    this.opener = event.currentTarget
    this.evidenceTarget.innerHTML = '<p class="visibility-empty-note">Cargando respuesta…</p>'
    if (this.evidenceTarget.src === event.currentTarget.href) this.evidenceTarget.reload()
    else this.evidenceTarget.src = event.currentTarget.href
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
  }

  closeEvidence() { this.dialogTarget.close() }
  backdrop(event) { if (event.target === this.dialogTarget) this.closeEvidence() }
}
