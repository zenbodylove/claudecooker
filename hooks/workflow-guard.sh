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
shopt -s nullglob
roster=()
for f in "$roster_dir"/*.md; do
  n=$(basename "$f" .md)
  grep -q '^name:' "$f" 2>/dev/null && roster+=("$n")
done
[[ ${#roster[@]} -eq 0 ]] && exit 0

# Mask `(` inside string literals and comments, so text like "call agent( with care" in a prompt
# is not read as a call. Option values (agentType: 'scout') survive untouched.
masked=$(awk '
{
  line = $0; out = ""; i = 1; n = length(line)
  while (i <= n) {
    c = substr(line, i, 1)
    if (inblock) {
      if (c == "*" && substr(line, i + 1, 1) == "/") { out = out "*/"; i += 2; inblock = 0; continue }
      out = out (c == "(" ? "\001" : c); i++; continue
    }
    if (instr) {
      if (c == "\\") { out = out c substr(line, i + 1, 1); i += 2; continue }
      if (c == q) { instr = 0; out = out c; i++; continue }
      out = out (c == "(" ? "\001" : c); i++; continue
    }
    if (c == "/" && substr(line, i + 1, 1) == "/") { r = substr(line, i); gsub(/\(/, "\001", r); out = out r; break }
    if (c == "/" && substr(line, i + 1, 1) == "*") { inblock = 1; out = out "/*"; i += 2; continue }
    if (c == "\"" || c == "'"'"'" || c == "`") { instr = 1; q = c; out = out c; i++; continue }
    out = out c; i++
  }
  if (instr && q != "`") instr = 0
  print out
}' <<<"$script" 2>/dev/null) || masked="$script"

# Word boundary: only count `agent(` at the start of an identifier, and never `.agent(`.
masked=$(sed -E 's/([A-Za-z0-9_$.])agent\(/\1agent\x01/g' <<<"$masked" 2>/dev/null) || true

violations=0
unknown=""
rest="$masked"
while [[ "$rest" == *"agent("* ]]; do
  rest="${rest#*agent(}"
  seg="${rest%%agent(*}"   # options text up to the next agent( call — heuristic, not a JS parse
  if [[ "$seg" =~ agentType:[[:space:]]*[\'\"]([A-Za-z0-9_-]+)[\'\"] ]]; then
    role="${BASH_REMATCH[1]}"
    known=0
    for r in "${roster[@]}"; do [[ "$role" == "$r" ]] && known=1; done
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
msg="Dispatch policy: ${violations} agent() call(s) in this workflow ${detail}. Roster: ${roster[*]}. Every Workflow agent() must set agentType to a roster role and never a bare model."
jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
exit 0
