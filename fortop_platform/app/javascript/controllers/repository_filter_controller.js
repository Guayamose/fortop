import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["search", "filter", "row", "empty"]

  connect() {
    this.status = this.filterTargets.find(button => button.getAttribute("aria-pressed") === "true")?.dataset.filter || "all"
    this.filter()
  }

  select(event) {
    this.status = event.currentTarget.dataset.filter
    this.filterTargets.forEach(button => button.setAttribute("aria-pressed", String(button === event.currentTarget)))
    this.filter()
  }

  filter() {
    const query = this.searchTarget.value.trim().toLocaleLowerCase("es")
    let visible = 0
    this.rowTargets.forEach(row => {
      const matches = row.dataset.search.includes(query) && (this.status === "all" || row.dataset.status === this.status)
      row.hidden = !matches
      if (matches) visible += 1
    })
    this.emptyTarget.hidden = visible > 0
  }

  reset() {
    this.searchTarget.value = ""
    this.status = "all"
    this.filterTargets.forEach(button => button.setAttribute("aria-pressed", String(button.dataset.filter === "all")))
    this.filter()
    this.searchTarget.focus()
  }
}
