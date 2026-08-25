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
json() { jq -cn --arg s "$1" '{tool_name:"Workflow",tool_input:{script:$s}}'; }

check roster-roles "$(json "const a = await agent('go', { agentType: 'scout', label: 's' })
const b = await agent('review it', { agentType: 'reviewer', phase: 'Review' })")" no

check missing-type "$(json "const a = await agent('go', { agentType: 'scout' })
const b = await agent('do the thing', { label: 'b', phase: 'Work' })")" yes

check unknown-role "$(json "const a = await agent('go', { agentType: 'general-purpose', label: 'g' })")" yes

check bare-model "$(json "const a = await agent('go', { model: 'sonnet', label: 'm' })")" yes

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

exit $fail
