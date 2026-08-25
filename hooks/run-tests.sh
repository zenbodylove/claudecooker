#!/usr/bin/env bash
# Runs every hooks/test-*.sh and syntax-checks every workflows/*.js. Non-zero if anything fails.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

for t in "$root"/hooks/test-*.sh; do
  [[ -e "$t" ]] || continue
  name=$(basename "$t")
  if bash "$t"; then echo "PASS $name"; else echo "FAIL $name"; fail=1; fi
done

for w in "$root"/workflows/*.js; do
  [[ -e "$w" ]] || continue
  name="workflows/$(basename "$w")"
  # Workflow scripts use `export const meta`, top-level await and top-level return, so `node --check`
  # rejects them. Strip the leading `export ` and construct (never call) an AsyncFunction instead.
  if node -e '
      const fs = require("fs");
      const src = fs.readFileSync(process.argv[1], "utf8").replace(/^export\s+/gm, "");
      const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
      new AsyncFunction("args", "agent", "parallel", "pipeline", "phase", "log", src);
    ' "$w" 2>&1; then echo "PASS syntax $name"; else echo "FAIL syntax $name"; fail=1; fi
done

[[ $fail -eq 0 ]] && echo "all checks passed" || echo "checks failed"
exit $fail
