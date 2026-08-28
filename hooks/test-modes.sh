#!/usr/bin/env bash
# Tests for modes.json and the cost-tier agent twins: the mode table is well
# formed and names only agents that exist, every (role, mode) cell resolves to
# an agent whose model/effort match the spec §2 tier table, and every twin is a
# faithful copy of its parent (identical body, identical frontmatter apart from
# name/description/model/effort). Runnable from any cwd.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODES="$ROOT/modes.json"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

# frontmatter = lines strictly between the first and second `---`
fm()   { awk '/^---$/{c++; next} c==1{print}' "$1"; }
# body   = everything after the second `---`
body() { awk '/^---$/{c++; next} c>=2{print}' "$1"; }
# value of a single frontmatter key
fmval() { fm "$1" | sed -n "s/^$2: //p" | head -1; }
fmkeys() { fm "$1" | sed -n 's/^\([A-Za-z][A-Za-z0-9_-]*\):.*/\1/p'; }

# ---------------------------------------------------------------------------
# 1. modes.json structure
# ---------------------------------------------------------------------------
if [[ ! -f $MODES ]]; then
  bad "modes.json: file not found"
elif ! jq -e . "$MODES" >/dev/null 2>&1; then
  bad "modes.json: not valid JSON"
else
  ok "modes.json parses"

  if [[ $(jq -r '.modes | type' "$MODES") != object ]]; then
    bad "modes.json: .modes is not an object"
  elif [[ $(jq -r '.modes | keys_unsorted | sort | join(",")' "$MODES") != "chill,cook,flow" ]]; then
    bad "modes.json: .modes keys are $(jq -rc '.modes | keys_unsorted' "$MODES"), expected cook/flow/chill"
  else
    ok "modes.json: .modes has exactly cook, flow, chill"
  fi

  for mode in $(jq -r '.modes | keys_unsorted[]' "$MODES" 2>/dev/null); do
    [[ $(jq -r --arg m "$mode" '.modes[$m].roles | type' "$MODES") == object ]] \
      || { bad "modes.json: $mode.roles is not an object"; continue; }
    fanout=$(jq -r --arg m "$mode" '.modes[$m].fanout // empty' "$MODES")
    case "$fanout" in
      full|capped) ;;
      *) bad "modes.json: $mode.fanout is '$fanout', expected full or capped"; continue;;
    esac
    ok "modes.json: $mode has object roles and fanout=$fanout"
  done

  # per-mode specifics
  [[ $(jq -r '.modes.cook.roles | length' "$MODES") == 0 ]] \
    && ok "modes.json: cook.roles is empty" || bad "modes.json: cook.roles is not empty"
  for pair in cook:full flow:full chill:capped; do
    mode=${pair%%:*}; want=${pair##*:}
    got=$(jq -r --arg m "$mode" '.modes[$m].fanout // empty' "$MODES")
    [[ $got == "$want" ]] && ok "modes.json: $mode.fanout == $want" \
      || bad "modes.json: $mode.fanout is '$got', expected '$want'"
  done

  # every role key and every twin value names an existing agent file
  while read -r mode key val; do
    [[ -n ${mode:-} ]] || continue
    [[ -f "$ROOT/agents/$key.md" ]] && ok "modes.json: $mode role key '$key' has agents/$key.md" \
      || bad "modes.json: $mode role key '$key' has no agents/$key.md"
    [[ -f "$ROOT/agents/$val.md" ]] && ok "modes.json: $mode role '$key' -> agents/$val.md exists" \
      || bad "modes.json: $mode role '$key' names missing agents/$val.md"
  done < <(jq -r '.modes | to_entries[] | .key as $m | .value.roles | to_entries[]
                  | "\($m) \(.key) \(.value)"' "$MODES")
fi

# ---------------------------------------------------------------------------
# 2. the spec §2 tier table, and twin fidelity
# ---------------------------------------------------------------------------
# role            cook           flow            chill
TIERS='scout            haiku:medium   haiku:medium    haiku:medium
transcriber      haiku:medium   haiku:medium    haiku:medium
planner          opus:high      opus:high       opus:high
debugger         opus:high      opus:high       opus:high
implementer      opus:high      opus:medium     opus:medium
reviewer         opus:high      opus:medium     sonnet:high
skeptic          opus:medium    sonnet:high     sonnet:high
docs-writer      opus:medium    sonnet:medium   sonnet:medium
branch-reviewer  opus:xhigh     opus:high       opus:high'

while read -r role c f ch; do
  [[ -n ${role:-} ]] || continue
  cells=("$c" "$f" "$ch"); modes=(cook flow chill)
  for i in 0 1 2; do
    mode=${modes[$i]}; cell=${cells[$i]}
    agent=$(jq -r --arg m "$mode" --arg r "$role" '.modes[$m].roles[$r] // $r' "$MODES" 2>/dev/null)
    file="$ROOT/agents/$agent.md"
    if [[ ! -f $file ]]; then bad "tier $role/$mode: agents/$agent.md not found"; continue; fi
    got="$(fmval "$file" model):$(fmval "$file" effort)"
    [[ $got == "$cell" ]] && ok "tier $role/$mode -> $agent is $got" \
      || bad "tier $role/$mode -> $agent is $got, expected $cell"
  done
done <<< "$TIERS"

# twin fidelity, once per unique twin
while read -r parent twin; do
  [[ -n ${twin:-} ]] || continue
  tf="$ROOT/agents/$twin.md"; pf="$ROOT/agents/$parent.md"
  if [[ ! -f $tf || ! -f $pf ]]; then bad "twin $twin: twin or parent file missing"; continue; fi

  [[ $(fmval "$tf" name) == "$twin" ]] && ok "twin $twin: name matches basename" \
    || bad "twin $twin: name is '$(fmval "$tf" name)', expected '$twin'"

  if diff -q <(body "$pf") <(body "$tf") >/dev/null; then ok "twin $twin: body == $parent body"
  else bad "twin $twin: body drifted from $parent"; diff <(body "$pf") <(body "$tf") | head -20; fi

  if [[ $(fmkeys "$pf" | sort | tr '\n' ' ') == $(fmkeys "$tf" | sort | tr '\n' ' ') ]]; then
    ok "twin $twin: frontmatter key set == $parent"
  else
    bad "twin $twin: frontmatter key set differs from $parent"
  fi

  drift=""
  while read -r k; do
    case "$k" in name|description|model|effort) continue;; esac
    [[ $(fmval "$pf" "$k") == $(fmval "$tf" "$k") ]] || drift="$drift $k"
  done < <(fmkeys "$pf")
  [[ -z $drift ]] && ok "twin $twin: shared frontmatter keys == $parent" \
    || bad "twin $twin: frontmatter drifted from $parent in:$drift"

  [[ $(fmval "$tf" description) != $(fmval "$pf" description) ]] \
    && ok "twin $twin: description differs from $parent" \
    || bad "twin $twin: description is identical to $parent's"
done < <(jq -r '[.modes[].roles | to_entries[] | "\(.key) \(.value)"] | unique[]' "$MODES" 2>/dev/null)

exit $fail
