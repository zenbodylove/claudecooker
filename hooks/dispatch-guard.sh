#!/usr/bin/env bash
# PreToolUse(Agent) warn-only role nudge. Never blocks: always exit 0. Fails open on any parse error.
set -u
input=$(cat)
type=$(jq -r '.tool_input.subagent_type // empty' <<<"$input" 2>/dev/null) || exit 0
roster_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/agents"
shopt -s nullglob
roster=()
for f in "$roster_dir"/*.md; do
  n=$(basename "$f" .md)
  grep -q '^name:' "$f" 2>/dev/null && roster+=("$n")
done
[[ ${#roster[@]} -eq 0 ]] && exit 0
for r in "${roster[@]}"; do [[ "$type" == "$r" ]] && exit 0; done
if [[ -z "$type" ]]; then
  msg="Dispatch policy: no subagent_type set, so this agent inherits the session model (Fable). Dispatch by role instead — roster: ${roster[*]}. Use scout for search, implementer for changes, reviewer/skeptic for judgement."
else
  msg="Dispatch policy: '${type}' is not a roster role, so its model/effort are not pinned. Roster: ${roster[*]}. Built-ins are allowed but prefer scout (search), implementer (changes), reviewer/skeptic (judgement)."
fi
jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
exit 0
