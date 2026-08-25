#!/usr/bin/env bash
# PreToolUse(Workflow) warn-only role nudge. Never blocks: always exit 0. Fails open on any parse error.
set -u
input=$(cat)
script=$(jq -r '.tool_input.script // empty' <<<"$input" 2>/dev/null) || exit 0
if [[ -z "$script" ]]; then
  path=$(jq -r '.tool_input.scriptPath // empty' <<<"$input" 2>/dev/null) || exit 0
  if [[ -z "$path" ]]; then
    # Saved workflow invoked by name: resolve it under the config dir; stay silent if it isn't there.
    name=$(jq -r '.tool_input.name // empty' <<<"$input" 2>/dev/null) || exit 0
    [[ -n "$name" ]] || exit 0
    path="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/workflows/${name}.js"
  fi
  [[ -r "$path" ]] || exit 0
  script=$(cat "$path" 2>/dev/null) || exit 0
fi
[[ -z "$script" ]] && exit 0

roster_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/agents"
roster=$(ls "$roster_dir"/*.md 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/\.md$//' | tr '\n' ' ')
[[ -z "$roster" ]] && exit 0

violations=0
unknown=""
rest="$script"
while [[ "$rest" == *"agent("* ]]; do
  rest="${rest#*agent(}"
  seg="${rest%%agent(*}"   # options text up to the next agent( call — heuristic, not a JS parse
  if [[ "$seg" =~ agentType:[[:space:]]*[\'\"]([A-Za-z0-9_-]+)[\'\"] ]]; then
    role="${BASH_REMATCH[1]}"
    known=0
    for r in $roster; do [[ "$role" == "$r" ]] && known=1; done
    if [[ $known -eq 0 ]]; then
      violations=$((violations + 1))
      case " $unknown " in *" $role "*) ;; *) unknown="${unknown:+$unknown }$role";; esac
    fi
  elif [[ "$seg" != *agentType:* ]]; then
    violations=$((violations + 1))   # no agentType at all; a bare model: counts here too
  fi
done

[[ $violations -eq 0 ]] && exit 0

if [[ -n "$unknown" ]]; then
  detail="lack agentType (or use an unknown role: ${unknown// /, })"
else
  detail="lack agentType"
fi
msg="Dispatch policy: ${violations} agent() call(s) in this workflow ${detail}. Roster: ${roster}. Every Workflow agent() must set agentType to a roster role and never a bare model."
jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
exit 0
