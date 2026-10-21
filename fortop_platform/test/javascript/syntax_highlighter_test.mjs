import { test } from "node:test"
import assert from "node:assert/strict"
import { tokenize, tokenizeDiff } from "../../app/javascript/syntax/tokenize.js"

const token = (line, content) => line.find(token => token.content.includes(content))

test("HTML uses VS Code Dark+ colors for delimiters, tags, attributes and quoted values", async () => {
  const [line] = await tokenize('<meta name="description" content="Fortop">', "html")
  assert.equal(token(line, "<").color, "#808080")
  assert.equal(token(line, "meta").color, "#569CD6")
  assert.equal(token(line, "name").color, "#9CDCFE")
  assert.equal(token(line, "description").color, "#CE9178")
  assert.equal(line.map(token => token.content).join(""), '<meta name="description" content="Fortop">')
})

test("ERB and HTML keep their embedded Ruby, JavaScript and CSS grammars", async () => {
  const source = '<style>body { color: red; }</style>\n<script>const count = 42; console.log(count)</script>\n<title><%= page_title || "Fortop" %></title>'
  const lines = await tokenize(source, "erb")
  assert.equal(token(lines[0], "color").color, "#9CDCFE")
  assert.equal(token(lines[1], "const").color, "#569CD6")
  assert.equal(token(lines[1], "42").color, "#B5CEA8")
  assert.equal(token(lines[2], "Fortop").color, "#CE9178")
  assert.equal(lines.map(line => line.map(token => token.content).join("")).join("\n"), source)
})

test("diff tokenizes the original and proposed versions independently with multiline lexical state", async () => {
  const rows = [
    { kind: "hunk", text: "@@ -1,3 +1,3 @@" },
    { kind: "context", text: "/* comment" },
    { kind: "deletion", text: "old */" },
    { kind: "addition", text: "new */" },
    { kind: "context", text: "const count = 42;" },
    { kind: "hunk", text: "@@ -20 +20 @@" },
    { kind: "addition", text: "const other = true;" }
  ]
  const tokens = await tokenizeDiff(rows, "javascript")
  assert.equal(tokens[2][0].color, "#6A9955")
  assert.equal(tokens[3][0].color, "#6A9955")
  assert.equal(token(tokens[4], "const").color, "#569CD6")
  assert.equal(token(tokens[6], "const").color, "#569CD6")
  assert.equal(tokens[0], undefined)
})

test("repository markup remains literal token content, including injection attempts", async () => {
  const source = '<img src=x onerror="alert(1)"><script>window.attack = true</script>'
  const lines = await tokenize(source, "html")
  assert.equal(lines[0].map(token => token.content).join(""), source)
  assert.equal((await tokenize("plain <text>", "text"))[0][0].content, "plain <text>")
  await assert.rejects(tokenize("test", "nonexistent-language"), /Unknown grammar/)
})
