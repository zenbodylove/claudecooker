#!/usr/bin/env bash
# PreToolUse(Agent) warn-only role nudge. Never blocks: always exit 0. Fails open on any parse error.
set -u
input=$(cat)
type=$(jq -r '.tool_input.subagent_type // empty' <<<"$input" 2>/dev/null) || exit 0
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
roster_dir="$cfg/agents"
shopt -s nullglob
roster=()
for f in "$roster_dir"/*.md; do
  n=$(basename "$f" .md)
  grep -q '^name:' "$f" 2>/dev/null && roster+=("$n")
done
[[ ${#roster[@]} -eq 0 ]] && exit 0
known=0
for r in "${roster[@]}"; do [[ "$type" == "$r" ]] && { known=1; break; }; done
if [[ $known -eq 1 ]]; then
  # Roster role: legal in every mode. In flow/chill, nudge toward the cheaper twin if one exists.
  mode=""
  if [[ -r "$cfg/.mode" ]]; then
    mode=$(head -c 64 "$cfg/.mode" 2>/dev/null | tr -d '[:space:]') || mode=""
  fi
  [[ -n "$mode" && "$mode" != "cook" ]] || exit 0
  twin=$(jq -r --arg m "$mode" --arg t "$type" '.modes[$m].roles[$t] // empty' "$cfg/modes.json" 2>/dev/null) || exit 0
  [[ -n "$twin" ]] || exit 0
  msg="Mode '${mode}': '${type}' is substituted by '${twin}' (modes.json). Dispatch ${twin} instead — same contract, cheaper tier. Cook-tier dispatch is still legal; this is a reminder, not a block."
  jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
  exit 0
fi
if [[ -z "$type" ]]; then
  msg="Dispatch policy: no subagent_type set, so this agent inherits the session model (Fable). Dispatch by role instead — roster: ${roster[*]}. Use scout for search, implementer for changes, reviewer/skeptic for judgement."
else
  msg="Dispatch policy: '${type}' is not a roster role, so its model/effort are not pinned. Roster: ${roster[*]}. Built-ins are allowed but prefer scout (search), implementer (changes), reviewer/skeptic (judgement)."
fi
jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
exit 0
