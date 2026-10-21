import { tokenize, tokenizeDiff } from "./tokenize.js"

self.onmessage = async ({ data: { id, source, rows, language } }) => {
  try {
    const tokens = rows ? await tokenizeDiff(rows, language) : await tokenize(source, language)
    self.postMessage({ id, tokens })
  } catch (error) {
    self.postMessage({ id, error: error.message })
  }
}
