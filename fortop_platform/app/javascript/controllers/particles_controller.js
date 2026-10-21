import { Controller } from "@hotwired/stimulus"

// Decorative particles sampled from the approved Fortop mark; no external service.
export default class extends Controller {
  static targets = ["canvas", "toggle"]
  static values = { source: String }

  connect() {
    this.canvasContext = this.canvasTarget.getContext("2d")
    if (!this.canvasContext) return
    this.points = []
    this.stars = []
    this.pointer = { x: 0, y: 0, active: false }
    this.time = 0
    this.paused = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.tick = this.tick.bind(this)
    this.visibility = () => {
      this.clearPointer()
      this.schedule()
    }
    document.addEventListener("visibilitychange", this.visibility)
    this.observer = new ResizeObserver(() => this.resize())
    this.observer.observe(this.element)
    this.image = new Image()
    this.image.onload = () => {
      this.sampleMark()
      this.resize()
      this.updateToggle()
      this.schedule()
    }
    this.image.src = this.sourceValue
  }

  sampleMark() {
    const mask = document.createElement("canvas")
    mask.width = 272
    mask.height = 240
    const context = mask.getContext("2d", { willReadFrequently: true })
    context.drawImage(this.image, 0, 0, 272, 240)
    const pixels = context.getImageData(0, 0, 272, 240).data
    let seed = 29
    const random = () => ((seed = (seed * 16807) % 2147483647) - 1) / 2147483646
    for (let y = 0; y < 240; y += 3) {
      for (let x = 0; x < 272; x += 3) {
        if (pixels[(y * 272 + x) * 4 + 3] > 120) {
          this.points.push({ x: (x - 136) / 136, y: (y - 120) / 136, z: (random() - .5) * .2,
            phase: random() * Math.PI * 2, brightness: .35 + random() * .65,
            offsetX: 0, offsetY: 0, ease: .04 + random() * .055 })
        }
      }
    }
    this.stars = Array.from({ length: 190 }, () => ({ x: random(), y: random(), phase: random() * Math.PI * 2,
      size: .3 + random() * 1.1, offsetX: 0, offsetY: 0, ease: .04 }))
  }

  resize() {
    this.width = this.element.clientWidth
    this.height = this.element.clientHeight
    const ratio = Math.min(window.devicePixelRatio || 1, 2)
    this.canvasTarget.width = this.width * ratio
    this.canvasTarget.height = this.height * ratio
    this.canvasContext.setTransform(ratio, 0, 0, ratio, 0, 0)
    this.clearPointer()
    this.points.forEach(point => { point.offsetX = 0; point.offsetY = 0 })
    this.stars.forEach(star => { star.offsetX = 0; star.offsetY = 0 })
    this.draw()
    if (this.image?.complete) this.schedule()
  }

  trackPointer(event) {
    if (this.paused || event.pointerType === "touch" || !this.pointer) return
    const rect = this.element.getBoundingClientRect()
    this.pointer.x = event.clientX - rect.left
    this.pointer.y = event.clientY - rect.top
    this.pointer.active = true
  }

  clearPointer() {
    if (this.pointer) this.pointer.active = false
  }

  // Oryon Flow's local repulsion: move away within 95px, then ease home.
  // Use elapsed frame time so the response feels the same at 60Hz and 144Hz.
  displace(point, x, y, step, strength = 1) {
    let targetX = 0, targetY = 0
    if (this.pointer.active) {
      const dx = x + point.offsetX - this.pointer.x
      const dy = y + point.offsetY - this.pointer.y
      const distanceSquared = dx * dx + dy * dy
      if (distanceSquared < 9000) {
        const force = (1 - distanceSquared / 9000) * 36 * strength / Math.sqrt(distanceSquared + 1)
        targetX = dx * force
        targetY = dy * force
      }
    }
    const response = 1 - Math.pow(1 - point.ease, step)
    point.offsetX += (targetX - point.offsetX) * response
    point.offsetY += (targetY - point.offsetY) * response
  }

  draw(step = 0) {
    const ctx = this.canvasContext
    const width = this.width || 0
    const height = this.height || 0
    ctx.clearRect(0, 0, width, height)
    const t = this.time
    const scale = Math.min(width * .32, height * .255)
    const cx = width * .5
    const cy = height * .43
    const turn = Math.sin(t * .22) * .18
    const breathe = 1 + Math.sin(t * .6) * .018
    this.stars.forEach(star => {
      const x = star.x * width
      const y = (star.y * height * .7 + t * 2) % (height * .7)
      this.displace(star, x, y, step, .4)
      const alpha = .08 + (Math.sin(t * .5 + star.phase) + 1) * .08
      ctx.fillStyle = `rgba(62,157,237,${alpha})`
      ctx.fillRect(x + star.offsetX, y + star.offsetY, star.size, star.size)
    })
    this.points.forEach(point => {
      const drift = Math.sin(t * .8 + point.phase) * 1.3
      const x = cx + (point.x * Math.cos(turn) + point.z * Math.sin(turn)) * scale * breathe + drift
      const y = cy + point.y * scale * breathe + drift * .4
      this.displace(point, x, y, step)
      const alpha = Math.min(1, point.brightness * (.95 + Math.sin(t * .7 + point.phase) * .15))
      const size = point.brightness > .8 ? 2 : 1.3
      ctx.fillStyle = `rgba(${point.brightness > .76 ? "175,220,255" : "38,152,242"},${alpha})`
      ctx.fillRect(x + point.offsetX, y + point.offsetY, size, size)
    })
  }

  tick(timestamp) {
    this.frame = null
    if (this.paused || document.hidden || !this.width || !this.height) return
    const elapsed = this.previous == null ? 0 : Math.min((timestamp - this.previous) / 1000, .05)
    this.time += elapsed
    this.previous = timestamp
    this.draw(elapsed * 60)
    this.frame = requestAnimationFrame(this.tick)
  }

  schedule() {
    cancelAnimationFrame(this.frame)
    this.previous = null
    if (!this.paused && !document.hidden && this.width && this.height) this.frame = requestAnimationFrame(this.tick)
  }

  toggle() {
    this.paused = !this.paused
    this.clearPointer()
    this.updateToggle()
    this.schedule()
  }

  updateToggle() {
    if (!this.hasToggleTarget) return
    this.toggleTarget.setAttribute("aria-label", this.paused ? "Reanudar animación" : "Pausar animación")
    this.toggleTarget.setAttribute("aria-pressed", String(this.paused))
    this.toggleTarget.querySelector("path").setAttribute("d", this.paused ? "m8 5 11 7-11 7V5Z" : "M9 5v14M15 5v14")
  }

  disconnect() {
    cancelAnimationFrame(this.frame)
    this.observer?.disconnect()
    document.removeEventListener("visibilitychange", this.visibility)
    if (this.image) this.image.onload = null
  }
}
