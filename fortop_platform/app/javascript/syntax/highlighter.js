let worker
let nextId = 0
const pending = new Map()

export function highlight(request) {
  if (!worker) {
    worker = new Worker(new URL(SYNTAX_WORKER_FILE, import.meta.url), { type: "module" })
    worker.onmessage = ({ data }) => {
      const job = pending.get(data.id)
      if (!job) return
      pending.delete(data.id)
      data.error ? job.reject(new Error(data.error)) : job.resolve(data.tokens)
    }
    worker.onerror = (event) => {
      pending.forEach(job => job.reject(new Error(event.message)))
      pending.clear()
      worker.terminate()
      worker = undefined
    }
  }
  return new Promise((resolve, reject) => {
    const id = ++nextId
    pending.set(id, { resolve, reject })
    worker.postMessage({ id, ...request })
  })
}

export function renderTokens(element, tokens) {
  const fragment = document.createDocumentFragment()
  for (const token of tokens || []) {
    const span = document.createElement("span")
    span.textContent = token.content
    span.style.color = token.color
    if (token.fontStyle & 1) span.style.fontStyle = "italic"
    if (token.fontStyle & 2) span.style.fontWeight = "bold"
    if (token.fontStyle & 4) span.style.textDecoration = "underline"
    fragment.append(span)
  }
  element.replaceChildren(fragment)
}
