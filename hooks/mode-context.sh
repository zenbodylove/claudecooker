#!/usr/bin/env bash
# SessionStart mode announcement. Warn-only: always exit 0, and the only key it
# ever emits is additionalContext — it can neither block nor allow a tool call.
# Silent in cook and on any error — an unreadable .mode or an unreadable or
# malformed modes.json means cook, which behaves as it did before modes existed.
# Reads nothing from stdin; SessionStart's JSON payload is simply ignored.
set -u
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
mode=""
if [[ -r "$cfg/.mode" ]]; then
  # head -c bounds a .mode that is accidentally a large or binary file
  mode=$(head -c 64 "$cfg/.mode" 2>/dev/null | tr -d '[:space:]') || mode=""
fi
[[ -n "$mode" && "$mode" != "cook" ]] || exit 0
[[ -r "$cfg/modes.json" ]] || exit 0
entry=$(jq -ec --arg m "$mode" '.modes[$m]' "$cfg/modes.json" 2>/dev/null) || exit 0
subs=$(jq -r 'if (.roles | length) == 0 then "none" else (.roles | to_entries | map("\(.key) -> \(.value)") | join(", ")) end' <<<"$entry" 2>/dev/null) || exit 0
fanout=$(jq -r '.fanout // "full"' <<<"$entry" 2>/dev/null) || exit 0
msg="Orchestration mode: ${mode}. Role substitutions (modes.json): ${subs}. Workflow fan-out: ${fanout}. Dispatch the twin, not the parent, for every substituted role, and pass mode: \"${mode}\" in args to every Workflow call."
jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
exit 0
