#!/usr/bin/env bash
# Tests for schemas/: every schema file is valid JSON, and every inline schema
# constant in workflows/*.js still deep-matches the canonical file its
# `// canonical:` comment names. Runnable from any cwd.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
ok()   { echo "ok   $1"; }
bad()  { echo "FAIL $1"; fail=1; }

# 1. every canonical schema parses and carries the draft-07 marker + title
shopt -s nullglob
schemas=("$ROOT"/schemas/*.json)
[[ ${#schemas[@]} -gt 0 ]] || bad "schemas/: no schema files found"
for f in "${schemas[@]}"; do
  name="schemas/$(basename "$f")"
  if ! jq -e . "$f" >/dev/null 2>&1; then bad "$name: not valid JSON"; continue; fi
  if [[ $(jq -r '."$schema" // empty' "$f") != "https://json-schema.org/draft-07/schema#" ]]; then
    bad "$name: missing draft-07 \$schema"; continue
  fi
  if [[ -z $(jq -r '.title // empty' "$f") ]]; then bad "$name: missing title"; continue; fi
  if [[ $(jq -r '.type // empty' "$f") != object ]]; then bad "$name: type is not object"; continue; fi
  if [[ $(jq -r 'has("required") and has("properties")' "$f") != true ]]; then
    bad "$name: missing required/properties"; continue
  fi
  ok "$name parses"
done

# 2. inline workflow copies match their canonical file
node -e "$(cat <<'JS'
const fs = require('fs'), path = require('path')
const root = process.argv[1]
const MARK = /^\s*\/\/ canonical: (schemas\/[a-z0-9-]+\.json) — keep in sync \(hooks\/test-schemas\.sh\)\s*$/
const sortDeep = v => Array.isArray(v) ? v.map(sortDeep)
  : (v && typeof v === 'object')
    ? Object.fromEntries(Object.keys(v).filter(k => k !== '$schema' && k !== 'title').sort().map(k => [k, sortDeep(v[k])]))
    : v
const norm = v => JSON.stringify(sortDeep(v))
let fail = 0
const ok = m => console.log('ok   ' + m)
const bad = m => { console.log('FAIL ' + m); fail = 1 }
const wfDir = path.join(root, 'workflows')
const files = fs.existsSync(wfDir) ? fs.readdirSync(wfDir).filter(f => f.endsWith('.js')) : []
if (!files.length) bad('workflows/: no .js files found')
for (const f of files) {
  const src = fs.readFileSync(path.join(wfDir, f), 'utf8')
  const lines = src.split('\n')
  const used = new Set([...src.matchAll(/schema:\s*([A-Za-z_$][\w$]*)/g)].map(m => m[1]))
  for (const name of used) {
    const start = lines.findIndex(l => new RegExp('^const ' + name + ' = \\{').test(l))
    if (start < 0) { bad(`workflows/${f}: cannot locate 'const ${name} = {'`); continue }
    const prev = lines[start - 1] === undefined ? '' : lines[start - 1]
    const mark = prev.match(MARK)
    if (!mark) { bad(`workflows/${f}: ${name} has no '// canonical: …' comment above it`); continue }
    let end = -1
    for (let i = start; i < lines.length; i++) if (lines[i] === '}') { end = i; break }
    if (end < 0) { bad(`workflows/${f}: ${name} literal has no terminating '}' at column 0`); continue }
    const literal = lines.slice(start, end + 1).join('\n').replace(/^const \w+ = /, '')
    let inline
    try { inline = new Function('return ' + literal)() }
    catch (e) { bad(`workflows/${f}: ${name} literal does not evaluate: ${e.message}`); continue }
    const canonPath = path.join(root, mark[1])
    if (!fs.existsSync(canonPath)) { bad(`workflows/${f}: ${name} names missing ${mark[1]}`); continue }
    let canon
    try { canon = JSON.parse(fs.readFileSync(canonPath, 'utf8')) }
    catch (e) { bad(`${mark[1]}: not valid JSON`); continue }
    if (norm(inline) !== norm(canon)) {
      bad(`workflows/${f}: ${name} drifted from ${mark[1]}`)
      console.log('     inline: ' + norm(inline))
      console.log('     canon : ' + norm(canon))
      continue
    }
    ok(`workflows/${f}: ${name} == ${mark[1]}`)
  }
}
process.exit(fail)
JS
)" "$ROOT" || fail=1

exit $fail
