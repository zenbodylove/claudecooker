#!/usr/bin/env bash
# Tests for workflow-guard.sh: always exit 0; nudge when an agent() call lacks agentType or names a non-roster role.
set -u
HOOK="$(dirname "$0")/workflow-guard.sh"
fail=0
check() { # name, stdin json, expect-context (yes|no)
  out=$("$HOOK" <<<"$2"); code=$?
  [[ $code -eq 0 ]] || { echo "FAIL $1: exit $code"; fail=1; return; }
  has=$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$out" 2>/dev/null)
  if [[ "$3" == yes && -z "$has" ]]; then echo "FAIL $1: expected additionalContext"; fail=1
  elif [[ "$3" == no && -n "$has" ]]; then echo "FAIL $1: unexpected additionalContext: $has"; fail=1
  else echo "ok   $1"; fi
}
check_contains() { # name, stdin json, substring...
  local name="$1" in="$2"; shift 2
  out=$("$HOOK" <<<"$in"); code=$?
  [[ $code -eq 0 ]] || { echo "FAIL $name: exit $code"; fail=1; return; }
  has=$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$out" 2>/dev/null)
  for sub in "$@"; do
    case "$has" in *"$sub"*) ;; *) echo "FAIL $name: expected context containing '$sub', got: $has"; fail=1; return;; esac
  done
  echo "ok   $name"
}
json() { jq -cn --arg s "$1" '{tool_name:"Workflow",tool_input:{script:$s}}'; }
json_args() { jq -cn --arg s "$1" --argjson a "$2" '{tool_name:"Workflow",tool_input:{script:$s,args:$a}}'; }

# Pin every case to a temp config dir: the guard reads .mode from CLAUDE_CONFIG_DIR, so the
# machine's live ~/.claude/.mode would otherwise change the expected output of every assertion.
basecfg=$(mktemp -d /tmp/wf-guard-base.XXXXXX)
mkdir -p "$basecfg/agents" "$basecfg/workflows"
cp "$(dirname "$0")/../agents"/*.md "$basecfg/agents/" 2>/dev/null || true
cp "$(dirname "$0")/../modes.json" "$basecfg/" 2>/dev/null || true
trap 'rm -rf "$basecfg"' EXIT
export CLAUDE_CONFIG_DIR="$basecfg"

check roster-roles "$(json "const a = await agent('go', { agentType: 'scout', label: 's' })
const b = await agent('review it', { agentType: 'reviewer', phase: 'Review' })")" no

check missing-type "$(json "const a = await agent('go', { agentType: 'scout' })
const b = await agent('do the thing', { label: 'b', phase: 'Work' })")" yes

check unknown-role "$(json "const a = await agent('go', { agentType: 'general-purpose', label: 'g' })")" yes

check bare-model "$(json "const a = await agent('go', { model: 'sonnet', label: 'm' })")" yes

check subagent-word "$(json "const a = await subagent('go', { label: 'x' })
const b = await agent('go', { agentType: 'scout', label: 's' })")" no

check in-string "$(json "const a = await agent('call agent( with care', { agentType: 'scout', label: 's' })")" no

check no-agent-calls "$(json "const x = 1
return { ok: true }")" no

check name-only '{"tool_name":"Workflow","tool_input":{"name":"no-such-workflow-xyz"}}' no

wfdir=$(mktemp -d /tmp/wf-guard-cfg.XXXXXX)
mkdir -p "$wfdir/workflows" "$wfdir/agents"
cp "$(dirname "$0")/../agents"/*.md "$wfdir/agents/" 2>/dev/null || true
printf '%s\n' "const b = await agent('do it', { label: 'b' })" >"$wfdir/workflows/named-wf.js"
CLAUDE_CONFIG_DIR="$wfdir" check name-resolved '{"tool_name":"Workflow","tool_input":{"name":"named-wf"}}' yes
rm -rf "$wfdir"
check garbage 'not json' no

tmp=$(mktemp /tmp/wf-guard-test.XXXXXX.js)
printf '%s\n' "const b = await agent('do it', { label: 'b' })" >"$tmp"
check scriptPath "$(jq -cn --arg p "$tmp" '{tool_name:"Workflow",tool_input:{scriptPath:$p}}')" yes
rm -f "$tmp"

check scriptPath-missing '{"tool_name":"Workflow","tool_input":{"scriptPath":"/nonexistent/nope.js"}}' no

# --- mode nudge (spec §5): a workflow that never learns the mode runs at cook tiers ---
modecfg=$(mktemp -d /tmp/wf-guard-mode.XXXXXX)
mkdir -p "$modecfg/agents" "$modecfg/workflows"
cp "$(dirname "$0")/../agents"/*.md "$modecfg/agents/" 2>/dev/null || true
cp "$(dirname "$0")/../modes.json" "$modecfg/" 2>/dev/null || true
set_mode() { if [[ -z "${1:-}" ]]; then rm -f "$modecfg/.mode"; else printf '%s\n' "$1" >"$modecfg/.mode"; fi; }
clean="const a = await agent('go', { agentType: 'scout', label: 's' })"

set_mode chill
CLAUDE_CONFIG_DIR="$modecfg" check mode-chill-no-args "$(json "$clean")" yes
CLAUDE_CONFIG_DIR="$modecfg" check mode-chill-args-no-mode "$(json_args "$clean" '{"base":"dev"}')" yes
CLAUDE_CONFIG_DIR="$modecfg" check mode-chill-args-mode "$(json_args "$clean" '{"mode":"chill"}')" no
CLAUDE_CONFIG_DIR="$modecfg" check mode-chill-args-string "$(json_args "$clean" '"how does X work"')" yes
CLAUDE_CONFIG_DIR="$modecfg" check mode-chill-unresolvable-name '{"tool_name":"Workflow","tool_input":{"name":"no-such-workflow-xyz"}}' yes
CLAUDE_CONFIG_DIR="$modecfg" check_contains mode-chill-plus-violation \
  "$(json "const a = await agent('go', { agentType: 'scout', label: 's' })
const b = await agent('x', { label: 'b' })")" agentType args

set_mode flow
CLAUDE_CONFIG_DIR="$modecfg" check mode-flow-args-mode "$(json_args "$clean" '{"mode":"flow"}')" no
CLAUDE_CONFIG_DIR="$modecfg" check mode-flow-no-args "$(json "$clean")" yes

set_mode cook
CLAUDE_CONFIG_DIR="$modecfg" check mode-cook-no-args "$(json "$clean")" no
# Task 7 form: agentType: role('x') is resolved and validated exactly like a quoted literal —
# silent because 'reviewer' is on the roster, not because role() is exempt from the check.
CLAUDE_CONFIG_DIR="$modecfg" check role-helper \
  "$(json "const a = await agent('review it', { agentType: role('reviewer'), phase: 'Review' })")" no
# The counterpart: an unknown name inside role() must nudge, with the same message shape as the literal form.
CLAUDE_CONFIG_DIR="$modecfg" check_contains role-helper-unknown \
  "$(json "const a = await agent('go', { agentType: role('bogus-role'), label: 's' })")" \
  'unknown role: bogus-role' 'Roster:'
# Double-quoted and whitespaced variants of the helper call resolve too.
CLAUDE_CONFIG_DIR="$modecfg" check role-helper-dq \
  "$(json "const a = await agent('go', { agentType: role( \"scout\" ), label: 's' })")" no
CLAUDE_CONFIG_DIR="$modecfg" check_contains role-helper-dq-unknown \
  "$(json "const a = await agent('go', { agentType: role( \"nope-role\" ), label: 's' })")" \
  'unknown role: nope-role'
# A quoted literal still works alongside the helper form in the same script.
CLAUDE_CONFIG_DIR="$modecfg" check_contains role-mixed \
  "$(json "const a = await agent('go', { agentType: 'scout', label: 's' })
const b = await agent('go', { agentType: role('nope2'), label: 'b' })")" 'unknown role: nope2'

set_mode ''
CLAUDE_CONFIG_DIR="$modecfg" check mode-absent-no-args "$(json "$clean")" no

set_mode banana
CLAUDE_CONFIG_DIR="$modecfg" check mode-garbage-no-args "$(json "$clean")" no

set_mode chill
rm -f "$modecfg/modes.json"
CLAUDE_CONFIG_DIR="$modecfg" check mode-no-modes-json "$(json "$clean")" no
printf '%s\n' 'not json' >"$modecfg/modes.json"
CLAUDE_CONFIG_DIR="$modecfg" check mode-bad-modes-json "$(json "$clean")" no
rm -rf "$modecfg"

exit $fail
