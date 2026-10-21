import { createHighlighterCore } from "shiki/core"
import { createOnigurumaEngine } from "shiki/engine/oniguruma"
import { bundledLanguages } from "shiki/langs"
import darkPlus from "@shikijs/themes/dark-plus"

const highlighter = createHighlighterCore({
  themes: [darkPlus], langs: [], engine: createOnigurumaEngine(import("shiki/wasm"))
})
const loading = new Map()
const cache = new Map()

export async function tokenize(source, language) {
  const key = `${language}\0${source}`
  if (cache.has(key)) return cache.get(key)
  const engine = await highlighter
  if (language !== "text" && !engine.getLoadedLanguages().includes(language)) {
    if (!bundledLanguages[language]) throw new Error(`Unknown grammar: ${language}`)
    if (!loading.has(language)) loading.set(language, engine.loadLanguage(bundledLanguages[language]))
    await loading.get(language)
  }
  const tokens = engine.codeToTokens(source, { lang: language, theme: "dark-plus" }).tokens
  cache.set(key, tokens)
  // Token trees can be large; retain only the most recent snippets between live renders.
  if (cache.size > 80) cache.delete(cache.keys().next().value)
  return tokens
}

export async function tokenizeDiff(rows, language) {
  const highlighted = new Array(rows.length)
  let start = 0
  while (start < rows.length) {
    let end = start + 1
    while (end < rows.length && rows[end].kind !== "hunk") end++
    const hunk = rows.slice(start, end)
    const before = hunk.filter(row => ["context", "deletion"].includes(row.kind))
    const after = hunk.filter(row => ["context", "addition"].includes(row.kind))
    // Each side has its own multiline lexical state. Never tokenize a combined patch as source.
    const [original, proposed] = await Promise.all([
      tokenize(before.map(row => row.text).join("\n"), language),
      tokenize(after.map(row => row.text).join("\n"), language)
    ])
    let oldIndex = 0, newIndex = 0
    hunk.forEach((row, index) => {
      if (row.kind === "deletion") highlighted[start + index] = original[oldIndex++]
      if (row.kind === "addition") highlighted[start + index] = proposed[newIndex++]
      if (row.kind === "context") { oldIndex++; highlighted[start + index] = proposed[newIndex++] }
    })
    start = end
  }
  return highlighted
}
