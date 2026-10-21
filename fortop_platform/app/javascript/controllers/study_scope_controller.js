import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["questions", "repetitions", "preview"]
  static values = { markets: Number }

  connect() { this.update() }

  update() {
    const samples = Number(this.questionsTarget.value) * Number(this.repetitionsTarget.value) * this.marketsValue
    const requests = 4 + this.marketsValue * 2 + samples * 2
    this.previewTarget.textContent = `${this.marketsValue} ${this.marketsValue === 1 ? "mercado" : "mercados"} · ${samples} respuestas previstas · al menos ${requests} solicitudes de IA, incluida la evaluación. Si reutilizas un panel se conserva su número de preguntas.`
  }
}
