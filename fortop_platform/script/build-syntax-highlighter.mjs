import { build } from "esbuild"
import { bundledLanguagesInfo } from "shiki/langs"
import { mkdir, readFile, rm, writeFile } from "node:fs/promises"

const outdir = "public/syntax/v4.5.0"
await rm(outdir, { recursive: true, force: true })
const options = {
  outdir, bundle: true, splitting: true, format: "esm", platform: "browser", target: "es2022",
  supported: { "template-literal": false },
  minify: true, chunkNames: "chunks/[name]-[hash]", entryNames: "[name]-[hash]", legalComments: "linked", metafile: true
}
const worker = await build({ ...options, entryPoints: ["app/javascript/syntax/worker.js"] })
const workerFile = Object.entries(worker.metafile.outputs).find(([, output]) => output.entryPoint === "app/javascript/syntax/worker.js")[0].split("/").at(-1)
const client = await build({
  ...options, entryPoints: ["app/javascript/syntax/highlighter.js"],
  define: { SYNTAX_WORKER_FILE: JSON.stringify(`./${workerFile}`) }
})
const entrypoint = Object.entries(client.metafile.outputs).find(([, output]) => output.entryPoint === "app/javascript/syntax/highlighter.js")[0].replace(/^public/, "")
const importmap = await readFile("config/importmap.rb", "utf8")
await writeFile("config/importmap.rb", importmap.replace(/^pin "code-highlighter".*$/m, `pin "code-highlighter", to: "${entrypoint}", preload: false`))
// Rails uses the same language IDs and names as the browser's installed grammars.
const languages = []
for (const info of bundledLanguagesInfo) {
  const { default: grammars } = await import(`@shikijs/langs/${info.id}`)
  const grammar = grammars.find(grammar => grammar.name === info.id) || grammars.at(-1)
  languages.push({ id: info.id, name: info.name, aliases: info.aliases || [], extensions: grammar.fileTypes || [] })
}
await writeFile("config/syntax_languages.json", JSON.stringify(languages, null, 2) + "\n")
await mkdir(outdir, { recursive: true })
await writeFile(`${outdir}/LICENSE.txt`, await readFile("node_modules/shiki/LICENSE", "utf8"))
console.log(`Built Shiki 4.5.0 · ${languages.length} languages · VS Code Dark+ · Oniguruma`)
