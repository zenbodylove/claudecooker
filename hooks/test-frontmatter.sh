#!/usr/bin/env bash
# Lints the YAML frontmatter of every agents/*.md. test-modes.sh reads frontmatter with
# awk/sed line matching, so the suite was blind to frontmatter that is not valid YAML at
# all — an unquoted colon-space in a description shipped green. Six assertions per role:
# a well-formed block, no unquoted colon-space, no unquoted ` #`, no unquoted leading YAML
# indicator, no tabs, and name == basename. A strict yaml.safe_load runs as a bonus when
# python3 and PyYAML happen to be present; the repo depends on bash/jq/node only, so its
# absence is a visible skip, never a failure. Runnable from any cwd.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
ok()   { echo "ok   $1"; }
bad()  { echo "FAIL $1"; fail=1; }
skip() { echo "skip $1"; }

# frontmatter = lines strictly between the first and second `---`
fm() { awk '/^---$/{c++; next} c==1{print} c>=2{exit}' "$1"; }

# a value is quoted when it opens and closes with the same quote character
quoted() {
  case "$1" in
    \"*\") [[ ${#1} -ge 2 ]] ;;
    \'*\') [[ ${#1} -ge 2 ]] ;;
    *) false ;;
  esac
}

# characters that change how YAML parses the rest of a plain scalar
INDICATORS='*&!%@`[{>|'

shopt -s nullglob
files=("$ROOT"/agents/*.md)
shopt -u nullglob
[[ ${#files[@]} -gt 0 ]] || bad "agents/: no .md roster files found"

for f in "${files[@]}"; do
  rel="agents/$(basename "$f")"
  base="$(basename "$f" .md)"

  # 1. exactly one well-formed frontmatter block: `---` on line 1, and a closing `---`
  if [[ $(head -1 "$f") != "---" ]]; then
    bad "$rel: no '---' on line 1 — frontmatter block is not well formed"
    continue
  elif [[ $(grep -c '^---$' "$f") -lt 2 ]]; then
    bad "$rel: opening '---' has no closing '---'"
    continue
  else
    ok "$rel: well-formed frontmatter block"
  fi

  block="$(fm "$f")"

  # 2/3/4. scalar hygiene on every unquoted `key: value` line
  colon=""; hash=""; indic=""
  while IFS= read -r line; do
    [[ $line =~ ^([A-Za-z][A-Za-z0-9_-]*):\ (.*)$ ]] || continue
    key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
    [[ -n $val ]] || continue
    quoted "$val" && continue
    [[ $val == *": "* ]] && colon="$colon $key"
    [[ $val == *" #"* ]] && hash="$hash $key"
    first="${val:0:1}"
    [[ $INDICATORS == *"$first"* ]] && indic="$indic $key"
  done <<< "$block"

  if [[ -z $colon ]]; then
    ok "$rel: no unquoted value contains ': '"
  else
    for key in $colon; do
      bad "$rel: unquoted '$key' contains ': ' — invalid YAML: $(sed -n "s/^$key: //p" <<< "$block" | head -1)"
    done
  fi

  if [[ -z $hash ]]; then
    ok "$rel: no unquoted value contains ' #'"
  else
    for key in $hash; do
      bad "$rel: unquoted '$key' contains ' #' — YAML truncates it as a comment: $(sed -n "s/^$key: //p" <<< "$block" | head -1)"
    done
  fi

  if [[ -z $indic ]]; then
    ok "$rel: no unquoted value opens with a YAML indicator"
  else
    for key in $indic; do
      bad "$rel: unquoted '$key' opens with a YAML indicator character: $(sed -n "s/^$key: //p" <<< "$block" | head -1)"
    done
  fi

  # 5. no tabs anywhere in the frontmatter
  if printf '%s\n' "$block" | grep -q "$(printf '\t')"; then
    bad "$rel: frontmatter contains a tab character — YAML forbids tabs"
  else
    ok "$rel: frontmatter has no tab characters"
  fi

  # 6. name matches the basename, or the role is not dispatchable under the name it claims
  got="$(sed -n 's/^name: //p' <<< "$block" | head -1)"
  [[ $got == "$base" ]] && ok "$rel: name matches basename" \
    || bad "$rel: name is '$got', expected '$base'"
done

# ---------------------------------------------------------------------------
# Bonus: strict parse. Optional by design — bash, jq and node are the declared
# dependencies and none of them parses YAML.
# ---------------------------------------------------------------------------
if ! command -v python3 >/dev/null 2>&1; then
  skip "strict YAML parse: python3 not installed"
elif ! python3 -c 'import yaml' >/dev/null 2>&1; then
  skip "strict YAML parse: python3 has no yaml module (pip install PyYAML)"
else
  for f in "${files[@]}"; do
    rel="agents/$(basename "$f")"
    if err=$(fm "$f" | python3 -c '
import sys, yaml
try:
    yaml.safe_load(sys.stdin.read())
except Exception as e:
    sys.stderr.write(str(e))
    sys.exit(1)
' 2>&1); then
      ok "$rel: frontmatter parses as YAML"
    else
      bad "$rel: frontmatter does not parse as YAML — $(tr '\n' ' ' <<< "$err")"
    fi
  done
fi

exit $fail
