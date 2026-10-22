import { Controller } from "@hotwired/stimulus"

const HELP = "PNG, JPG o WebP · máximo 2 MB. Si no subes un logo, usamos el icono de tu web."

export default class extends Controller {
  static targets = ["image", "fallback", "file", "website", "remove", "reset", "message"]
  static values = { uploadedSource: String }

  connect() {
    if (this.hasFileTarget && this.fileTarget.files.length) this.choose()
    else if (this.imageTarget.complete) this.imageTarget.naturalWidth ? this.loaded() : this.failed()
  }

  disconnect() {
    clearTimeout(this.timer)
    this.releasePreview()
  }

  loaded() {
    this.imageTarget.hidden = false
    this.fallbackTarget.hidden = true
  }

  failed() {
    this.imageTarget.hidden = true
    this.fallbackTarget.hidden = false
  }

  choose() {
    const file = this.fileTarget.files[0]
    if (!file) return this.restore()
    if (!["image/png", "image/jpeg", "image/webp"].includes(file.type) || !file.size || file.size > 2 * 1024 * 1024) {
      this.fileTarget.value = ""
      this.restore()
      this.messageTarget.textContent = "Elige una imagen PNG, JPG o WebP de hasta 2 MB."
      this.messageTarget.classList.add("is-error")
      return
    }
    this.releasePreview()
    this.previewURL = URL.createObjectURL(file)
    this.removeTarget.value = "0"
    this.setSource(this.previewURL)
    this.resetTarget.hidden = false
    this.messageTarget.textContent = `${file.name} · Se guardará con la marca.`
    this.messageTarget.classList.remove("is-error")
  }

  reset() {
    this.fileTarget.value = ""
    this.removeTarget.value = "1"
    this.restore()
  }

  restore() {
    this.releasePreview()
    const uploaded = this.removeTarget.value !== "1" && this.uploadedSourceValue
    this.setSource(uploaded || this.websiteSource())
    this.resetTarget.hidden = !uploaded
    this.messageTarget.textContent = HELP
    this.messageTarget.classList.remove("is-error")
  }

  websiteChanged() {
    clearTimeout(this.timer)
    if (this.fileTarget.files.length || (this.uploadedSourceValue && this.removeTarget.value !== "1")) return
    this.timer = setTimeout(() => this.setSource(this.websiteSource()), 400)
  }

  websiteSource() {
    const value = this.websiteTarget.value.trim()
    if (!value) return ""
    try {
      const url = new URL(/^https?:\/\//i.test(value) ? value : `https://${value}`)
      if (!["http:", "https:"].includes(url.protocol) || !/^[a-z0-9.-]+\.[a-z]{2,}$/i.test(url.hostname)) return ""
      return `https://www.google.com/s2/favicons?${new URLSearchParams({ domain: url.hostname, sz: "128" })}`
    } catch { return "" }
  }

  setSource(source) {
    if (source === this.imageTarget.getAttribute("src")) return
    this.failed()
    source ? this.imageTarget.src = source : this.imageTarget.removeAttribute("src")
  }

  releasePreview() {
    if (this.previewURL) URL.revokeObjectURL(this.previewURL)
    this.previewURL = null
  }
}
