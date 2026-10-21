import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "dropzone", "status", "documents", "template", "retry", "undo"]
  static values = { url: String, storageKey: String }

  connect() {
    this.fieldNames = ["name", "website", "aliases_text", "brief", "markets_text", "known_competitors"]
    this.stopped = false
    const url = this.rememberedURL()
    if (url && /^\/brand_imports\/\d+$/.test(url)) {
      this.previousFields = this.fields()
      this.pollURL = url
      this.setBusy(true)
      this.poll()
    }
  }

  disconnect() {
    this.stopped = true
    clearTimeout(this.timer)
    this.abortController?.abort()
  }

  fields() { return Object.fromEntries(this.fieldNames.map(name => [name, this.element.elements.namedItem(`brand[${name}]`).value])) }
  remember(url) { try { url ? sessionStorage.setItem(this.storageKeyValue, url) : sessionStorage.removeItem(this.storageKeyValue) } catch {} }
  rememberedURL() { try { return sessionStorage.getItem(this.storageKeyValue) } catch { return null } }
  keyboard(event) { if (["Enter", " "].includes(event.key)) { event.preventDefault(); if (!this.busy) this.inputTarget.click() } }
  dragEnter(event) { event.preventDefault(); if (!this.busy) this.dropzoneTarget.classList.add("is-dragging") }
  dragOver(event) { event.preventDefault(); event.dataTransfer.dropEffect = this.busy ? "none" : "copy" }
  dragLeave(event) { if (!this.dropzoneTarget.contains(event.relatedTarget)) this.dropzoneTarget.classList.remove("is-dragging") }
  drop(event) { event.preventDefault(); this.dropzoneTarget.classList.remove("is-dragging"); if (!this.busy) this.upload(Array.from(event.dataTransfer.files)) }
  choose() { if (!this.busy) this.upload(Array.from(this.inputTarget.files)); this.inputTarget.value = "" }

  async upload(files) {
    if (!files.length) return
    const selected = Array.from(this.documentsTarget.querySelectorAll("input[name='brand[document_ids][]']"))
    const existing = selected.length
    const existingSize = selected.reduce((total, input) => total + Number(input.closest(".brand-document").dataset.documentSize || 0), 0)
    if (files.length + existing > 10) return this.message("Puedes añadir hasta 10 documentos al brief.", true)
    if (files.some(file => !/\.(pdf|docx|pptx|txt|md|csv|json)$/i.test(file.name))) return this.message("Usa archivos PDF, DOCX, PPTX, TXT, MD, CSV o JSON.", true)
    if (files.some(file => !file.size || file.size > 20 * 1024 * 1024) || files.reduce((total, file) => total + file.size, existingSize) > 50 * 1024 * 1024) return this.message("Cada archivo debe ocupar menos de 20 MB; el total no puede superar 50 MB.", true)
    this.failures = 0
    this.clearPending()
    this.previousFields = this.fields()
    const body = new FormData()
    files.forEach(file => body.append("files[]", file))
    Object.entries(this.previousFields).forEach(([key, value]) => body.append(`fields[${key}]`, value))
    this.setBusy(true)
    this.message(`Subiendo ${files.length === 1 ? "tu documento" : `${files.length} documentos`}…`)
    try {
      const data = await this.request(this.urlValue, { method: "POST", body })
      if (this.stopped) return
      this.pollURL = data.url
      this.remember(data.url)
      this.receive(data)
    } catch (error) { this.fail(error.message) }
  }

  async poll() {
    if (this.stopped) return
    try {
      const data = await this.request(this.pollURL)
      if (this.stopped) return
      this.failures = 0
      this.receive(data)
    } catch (error) {
      if (this.stopped) return
      this.failures = (this.failures || 0) + 1
      this.message("No hemos podido actualizar la lectura. Reconectando…", true)
      if (this.failures < 5) this.timer = setTimeout(() => this.poll(), 2500)
      else {
        this.message("Se ha perdido la conexión. Pulsa Reconectar para recuperar la lectura antes de guardar.", true)
        this.retryTarget.hidden = false
        this.retryTarget.textContent = "Reconectar"
        this.reconnect = true
      }
    }
  }

  receive(data) {
    this.lastResult = data
    this.showDocuments(data.documents, data.status === "completed")
    if (data.status === "completed") {
      this.remember(null)
      this.setBusy(false)
      this.undoFields = {}
      let filled = 0
      for (const name of this.fieldNames) {
        const input = this.element.elements.namedItem(`brand[${name}]`)
        const value = data.fields[name]
        // Respect edits made while the worker was reading the files.
        if (typeof value === "string" && value.trim() && input.value === this.previousFields[name] && input.value !== value) {
          this.undoFields[name] = { before: input.value, after: value }
          input.value = value
          input.classList.remove("is-autofilled")
          void input.offsetWidth
          input.classList.add("is-autofilled")
          input.dispatchEvent(new Event("input", { bubbles: true }))
          filled++
        }
      }
      this.undoTarget.hidden = filled === 0
      this.message(`${filled ? `${filled} ${filled === 1 ? "campo completado" : "campos completados"}.` : "Documentos incorporados al contexto."} Revisa el brief y guarda la marca.${data.warnings.length ? ` ${data.warnings.join(" ")}` : ""}`)
    } else if (data.status === "failed") {
      this.remember(null)
      this.fail(data.error || "No se ha podido leer la documentación.")
      this.documentsTarget.querySelectorAll("[data-pending='true']").forEach(row => {
        row.querySelector("small").textContent = "Lectura interrumpida"
        row.querySelector("button").disabled = false
      })
      this.retryTarget.hidden = !data.retryable
      this.retryTarget.textContent = "Reintentar lectura"
      this.reconnect = false
    } else {
      const status = { queued: "Documentos recibidos. Preparando la lectura…", extracting: "Leyendo el contenido de tus documentos…", interpreting: "Entendiendo tu negocio y completando el brief…" }
      this.message(status[data.status] || "Leyendo documentos…")
      this.timer = setTimeout(() => this.poll(), 1400)
    }
  }

  showDocuments(documents, ready) {
    for (const source of documents) {
      let row = this.documentsTarget.querySelector(`[data-document-id='${source.id}']`)
      if (!row) {
        row = this.templateTarget.content.firstElementChild.cloneNode(true)
        row.dataset.documentId = source.id
        this.documentsTarget.append(row)
      }
      row.dataset.documentSize = source.size
      row.dataset.pending = ready ? "false" : "true"
      const link = row.querySelector("a")
      link.textContent = source.name
      link.href = source.url
      row.querySelector("small").textContent = `${this.size(source.size)} · ${ready ? "Contexto de la marca" : "Leyendo documento"}`
      const remove = row.querySelector("button")
      remove.disabled = !ready
      remove.setAttribute("aria-label", `Quitar ${source.name} del contexto`)
      if (ready && !row.querySelector("input")) {
        const input = document.createElement("input")
        input.type = "hidden"; input.name = "brand[document_ids][]"; input.value = source.id
        row.append(input)
      }
    }
    this.documentsTarget.hidden = !this.documentsTarget.children.length
  }

  remove(event) {
    event.currentTarget.closest(".brand-document").remove()
    this.documentsTarget.hidden = !this.documentsTarget.children.length
    this.message("Documento retirado del próximo brief. Guarda los cambios para confirmar.")
  }

  clearPending() { this.documentsTarget.querySelectorAll("[data-pending='true']").forEach(row => row.remove()) }

  async retry() {
    this.setBusy(true)
    if (this.reconnect) { this.reconnect = false; this.failures = 0; this.poll(); return }
    this.previousFields = this.fields()
    try {
      const data = await this.request(this.lastResult.retry_url, { method: "POST" })
      if (this.stopped) return
      this.pollURL = data.url
      this.remember(data.url)
      this.receive(data)
    } catch (error) { this.fail(error.message) }
  }

  undo() {
    for (const [name, values] of Object.entries(this.undoFields || {})) {
      const input = this.element.elements.namedItem(`brand[${name}]`)
      if (input.value === values.after) input.value = values.before
    }
    this.undoTarget.hidden = true
    this.message("Autocompletado deshecho. Los documentos siguen añadidos al contexto.")
  }

  setBusy(busy) {
    this.busy = busy
    this.dropzoneTarget.classList.toggle("is-busy", busy)
    this.dropzoneTarget.setAttribute("aria-busy", busy)
    this.inputTarget.disabled = busy
    this.element.querySelectorAll("[type='submit']").forEach(button => button.disabled = busy)
    this.retryTarget.hidden = true
    if (busy) this.undoTarget.hidden = true
  }

  fail(message) { if (!this.stopped) { this.setBusy(false); this.message(message, true) } }
  message(text, error = false) { this.statusTarget.textContent = text; this.statusTarget.classList.toggle("is-error", error) }
  size(bytes) { return bytes >= 1024 * 1024 ? `${(bytes / 1024 / 1024).toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1024))} KB` }

  async request(url, options = {}) {
    this.abortController = new AbortController()
    const response = await fetch(url, { ...options, credentials: "same-origin", signal: this.abortController.signal,
      headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || "" } })
    if (response.redirected) { window.location.assign(response.url); throw new Error("Vuelve a iniciar sesión.") }
    const data = await response.json()
    if (!response.ok) throw new Error(data.error || "No se ha podido subir el archivo. Vuelve a intentarlo.")
    return data
  }
}
