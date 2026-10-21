import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["output", "latest", "unread", "search", "filterButton", "empty", "expandButton", "copyButton", "feedback", "followLabel"]

  connect() {
    this.pinned = true
    this.expanded = false
    this.category = "all"
    this.query = ""
    this.unread = 0
    this.copied = false
    this.feedback = ""
    this.known = new Set(this.entries.map((entry) => entry.id))
    this.resizeObserver = new ResizeObserver(() => {
      if (this.pinned && !this.rendering) this.follow()
    })
    this.resizeObserver.observe(this.outputTarget)
    this.applyState()
    this.follow()
  }

  disconnect() {
    this.resizeObserver?.disconnect()
    clearTimeout(this.copyTimer)
  }

  get entries() {
    return Array.from(this.element.querySelectorAll("[data-console-event]"))
  }

  beforeRender(event) {
    if (!event.detail.content.contains(this.element)) return
    this.rendering = true
    this.previousScroll = this.outputTarget.scrollTop
    const top = this.outputTarget.getBoundingClientRect().top
    const anchor = this.entries.find((entry) => !entry.hidden && entry.getBoundingClientRect().bottom > top)
    this.anchor = anchor ? { id: anchor.id, offset: anchor.getBoundingClientRect().top - top } : null
  }

  afterRender(event) {
    if (!event.detail.content.contains(this.element)) return
    const added = this.entries.filter((entry) => !this.known.has(entry.id))
    this.known = new Set(this.entries.map((entry) => entry.id))
    added.forEach((entry) => entry.classList.add("is-arriving"))
    if (!this.pinned) this.unread += added.length
    this.applyState()
    if (this.pinned) this.follow()
    else {
      this.outputTarget.scrollTop = this.previousScroll
      const anchor = this.anchor && document.getElementById(this.anchor.id)
      if (anchor && !anchor.hidden) {
        this.outputTarget.scrollTop += anchor.getBoundingClientRect().top - this.outputTarget.getBoundingClientRect().top - this.anchor.offset
      }
    }
    this.rendering = false
  }

  applyState() {
    this.copyButtonTarget.classList.toggle("is-copied", this.copied)
    this.feedbackTarget.textContent = this.feedback
    this.element.classList.toggle("is-expanded", this.expanded)
    this.expandButtonTarget.setAttribute("aria-expanded", String(this.expanded))
    this.expandButtonTarget.setAttribute("aria-label", this.expanded ? "Reducir consola" : "Ampliar consola")
    this.expandButtonTarget.title = this.expanded ? "Reducir consola" : "Ampliar consola"
    this.searchTarget.value = this.query
    this.filterButtonTargets.forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.filter === this.category)))
    const query = this.normalize(this.query)
    this.entries.forEach((entry) => {
      entry.hidden = (this.category !== "all" && entry.dataset.category !== this.category) || !this.normalize(entry.textContent).includes(query)
    })
    this.element.querySelectorAll("[data-console-group]").forEach((group) => {
      group.hidden = !Array.from(group.querySelectorAll("[data-console-event]")).some((entry) => !entry.hidden)
    })
    this.emptyTarget.hidden = this.entries.length === 0 || this.entries.some((entry) => !entry.hidden)
    this.copyButtonTarget.disabled = !this.entries.some((entry) => !entry.hidden)
    this.updateFollow()
  }

  normalize(value) {
    return value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("es")
  }

  filter(event) {
    this.category = event.currentTarget.dataset.filter
    this.applyState()
    this.follow()
  }

  search() {
    this.query = this.searchTarget.value
    this.applyState()
    this.follow()
  }

  reset() {
    this.category = "all"
    this.query = ""
    this.applyState()
    this.follow()
  }

  expand() {
    this.expanded = !this.expanded
    this.applyState()
    if (this.pinned) this.follow()
  }

  keyboard(event) {
    const typing = event.target.matches("input, textarea, [contenteditable='true']")
    if (event.key === "/" && !typing && !event.ctrlKey && !event.metaKey && !event.altKey) {
      event.preventDefault()
      this.searchTarget.focus()
    } else if (event.key === "Escape") {
      if (this.query) {
        event.preventDefault()
        this.query = ""
        this.applyState()
        this.follow()
      } else if (this.expanded) this.expand()
    }
  }

  async copy() {
    const text = this.entries.filter((entry) => !entry.hidden).map((entry) => {
      const messageElement = entry.querySelector("[data-console-message]")
      const message = messageElement.dataset.originalMessage || messageElement.textContent
      const path = entry.querySelector(".console-file code")?.textContent
      return `[${entry.querySelector("time").textContent}] ${message}${path && !message.includes(path) ? `\n  ${path}` : ""}`
    }).join("\n")
    try {
      await navigator.clipboard.writeText(text)
      this.copied = true
      this.feedback = "Actividad copiada"
    } catch {
      this.feedback = "No se ha podido copiar. Puedes seleccionar el texto de la consola."
    }
    this.applyState()
    clearTimeout(this.copyTimer)
    this.copyTimer = setTimeout(() => {
      this.copied = false
      this.feedback = ""
      this.applyState()
    }, 3000)
  }

  track() {
    if (this.rendering) return
    const output = this.outputTarget
    this.pinned = output.scrollHeight - output.scrollTop - output.clientHeight < 32
    if (this.pinned) this.unread = 0
    this.updateFollow()
  }

  updateFollow() {
    this.latestTarget.hidden = this.pinned || !this.entries.some((entry) => !entry.hidden)
    this.unreadTarget.textContent = this.unread ? `${this.unread} ${this.unread === 1 ? "nueva acción" : "nuevas acciones"}` : "Volver al directo"
    this.followLabelTarget.textContent = this.pinned ? "Siguiendo actividad" : "Leyendo el historial"
  }

  follow() {
    this.outputTarget.scrollTop = this.outputTarget.scrollHeight
    this.pinned = true
    this.unread = 0
    this.updateFollow()
  }
}
