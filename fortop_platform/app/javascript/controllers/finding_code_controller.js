import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() { this.highlight() }

  async highlight() {
    if (!this.element.open) return
    const frames = Array.from(this.element.querySelectorAll("[data-code-language]"))
      .filter(frame => frame.dataset.codeHighlighted !== "true" && frame.dataset.codeHighlighted !== "loading")
    if (!frames.length) return
    const { highlight, renderTokens } = await import("code-highlighter")
    await Promise.all(frames.map(async frame => {
      frame.dataset.codeHighlighted = "loading"
      const lines = Array.from(frame.querySelectorAll(".finding-source-text"))
      const language = frame.dataset.codeLanguage
      const request = frame.classList.contains("finding-diff")
        ? { language, rows: lines.map(line => ({ text: line.textContent, kind: line.closest("[data-diff-kind]").dataset.diffKind })) }
        : { language, source: lines.map(line => line.textContent).join("\n") }
      try {
        const tokens = await highlight(request)
        if (!frame.isConnected) return
        lines.forEach((line, index) => { if (tokens[index]) renderTokens(line, tokens[index]) })
        frame.dataset.codeHighlighted = "true"
      } catch {
        // The escaped source remains readable if the worker or a static asset cannot load.
        frame.dataset.codeHighlighted = "error"
      }
    }))
  }
}
