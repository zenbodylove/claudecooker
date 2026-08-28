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


# ---------------------------------------------------------------------------
# 3. hooks/mode-context.sh — SessionStart mode announcement
# ---------------------------------------------------------------------------
HOOK="$ROOT/hooks/mode-context.sh"
if [[ ! -x $HOOK ]]; then
  bad "mode-context.sh: not found or not executable at $HOOK"
else
  ok "mode-context.sh: exists and is executable"

  # Drive the hook against a throwaway CLAUDE_CONFIG_DIR. $1 = .mode contents
  # ("__absent__" writes no .mode at all); $2 = good|bad|none for modes.json.
  # Sets mc_out and mc_status; never uses a subshell, so both survive.
  mc_run() {
    local dot="$1" modes_state="${2:-good}" tmp
    tmp=$(mktemp -d)
    case "$modes_state" in
      good) cp "$MODES" "$tmp/modes.json" ;;
      bad)  printf 'not json\n' > "$tmp/modes.json" ;;
      none) : ;;
    esac
    [[ $dot == "__absent__" ]] || printf '%s' "$dot" > "$tmp/.mode"
    mc_out=$(CLAUDE_CONFIG_DIR="$tmp" bash "$HOOK" </dev/null 2>/dev/null)
    mc_status=$?
    rm -rf "$tmp"
  }

  # 3a. silent cases: exit 0, no stdout at all (cook must cost no context)
  #   case                         .mode        modes.json
  while read -r case dot modes_state; do
    [[ -n ${case:-} ]] || continue
    [[ $dot == "__empty__" ]] && dot=""
    mc_run "$dot" "$modes_state"
    if [[ $mc_status -ne 0 ]]; then
      bad "$case: exit $mc_status, expected 0"
    elif [[ -n $mc_out ]]; then
      bad "$case: expected no stdout, got: $mc_out"
    else
      ok "$case: silent, exit 0"
    fi
  done <<'SILENT'
mode-context-absent          __absent__ good
mode-context-empty           __empty__  good
mode-context-cook            cook       good
mode-context-garbage         banana     good
mode-context-no-modes-json   chill      none
mode-context-bad-modes-json  chill      bad
SILENT

  # 3b. speaking cases: additionalContext naming the mode, its subs and its fan-out
  #   case                       .mode   required substrings
  while read -r case dot want; do
    [[ -n ${case:-} ]] || continue
    mc_run "$dot" good
    if [[ $mc_status -ne 0 ]]; then
      bad "$case: exit $mc_status, expected 0"; continue
    fi
    if ! ctx=$(jq -re '.hookSpecificOutput.additionalContext' <<<"$mc_out" 2>/dev/null); then
      bad "$case: no .hookSpecificOutput.additionalContext in: $mc_out"; continue
    fi
    miss=""
    for w in $want; do [[ $ctx == *"$w"* ]] || miss="$miss $w"; done
    [[ -z $miss ]] && ok "$case: announces ${want// /, }" \
      || bad "$case: additionalContext missing:$miss — got: $ctx"
  done <<'SPEAK'
mode-context-flow   flow  flow implementer-medium reviewer-medium skeptic-sonnet docs-writer-sonnet branch-reviewer-high full
mode-context-chill  chill chill implementer-medium reviewer-sonnet skeptic-sonnet docs-writer-sonnet branch-reviewer-high capped
SPEAK

  # 3c. a trailing newline in .mode must not change a thing
  mc_run 'chill' good; bare="$mc_out"
  mc_run 'chill
' good
  [[ $mc_status -eq 0 && $mc_out == "$bare" && -n $bare ]] \
    && ok "mode-context-trailing-newline: output identical to bare 'chill'" \
    || bad "mode-context-trailing-newline: got '$mc_out', expected '$bare'"

  # 3d. hookEventName
  mc_run 'chill' good
  [[ $(jq -r '.hookSpecificOutput.hookEventName // empty' <<<"$mc_out" 2>/dev/null) == SessionStart ]] \
    && ok "mode-context-event-name: hookEventName == SessionStart" \
    || bad "mode-context-event-name: hookEventName is not SessionStart — got: $mc_out"

  # 3e. warn-only contract: no permissionDecision key, ever
  for dot in flow chill cook banana; do
    mc_run "$dot" good
    if [[ -z $mc_out ]]; then
      ok "mode-context-no-permission-decision/$dot: no output at all"
    elif [[ $(jq -r '[paths | .[-1]] | map(select(. == "permissionDecision")) | length' <<<"$mc_out" 2>/dev/null) == 0 ]]; then
      ok "mode-context-no-permission-decision/$dot: warn-only, no permissionDecision key"
    else
      bad "mode-context-no-permission-decision/$dot: emitted a permissionDecision — got: $mc_out"
    fi
  done
  grep -q 'permissionDecision' "$HOOK" \
    && bad "mode-context.sh: source mentions permissionDecision" \
    || ok "mode-context.sh: source never mentions permissionDecision"
fi

# ---------------------------------------------------------------------------
# 3f. settings.json registers mode-context.sh on SessionStart
# ---------------------------------------------------------------------------
SETTINGS="$ROOT/settings.json"
if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
  bad "settings.json: not valid JSON"
else
  ok "settings.json parses"
  cmd=$(jq -r '.hooks.SessionStart[0].hooks[0].command // empty' "$SETTINGS")
  [[ $cmd == '$HOME/.claude/hooks/mode-context.sh' ]] \
    && ok "settings.json: SessionStart runs mode-context.sh" \
    || bad "settings.json: SessionStart command is '$cmd', expected \$HOME/.claude/hooks/mode-context.sh"
  [[ $(jq -r '.hooks.SessionStart[0].hooks[0].timeout // empty' "$SETTINGS") =~ ^[0-9]+$ ]] \
    && ok "settings.json: SessionStart hook has a numeric timeout" \
    || bad "settings.json: SessionStart hook has no numeric timeout"
  [[ $(jq -r '.hooks.SessionStart[0].matcher // "none"' "$SETTINGS") == none ]] \
    && ok "settings.json: SessionStart has no matcher (fires on start/resume/clear/compact)" \
    || bad "settings.json: SessionStart should have no matcher"
  [[ $(jq -r '[.hooks.PreToolUse[].matcher] | sort | join(",")' "$SETTINGS") == "Agent,Workflow" ]] \
    && ok "settings.json: PreToolUse Agent+Workflow hooks intact" \
    || bad "settings.json: PreToolUse hooks disturbed"
fi

exit $fail
