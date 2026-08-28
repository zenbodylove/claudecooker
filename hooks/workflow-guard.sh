#!/usr/bin/env bash
# PreToolUse(Workflow) warn-only role nudge. Never blocks: always exit 0. Fails open on any parse error.
set -u
input=$(cat)
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Single exit path: every early return below still emits whatever messages accumulated so far.
msgs=()
finish() {
  if [[ ${#msgs[@]} -gt 0 ]]; then
    printf -v joined '%s ' "${msgs[@]}"
    jq -cn --arg m "${joined% }" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
  fi
  exit 0
}

# Mode nudge first: it is about args, not about the script, so it must survive an unresolvable script.
mode=""
if [[ -r "$cfg/.mode" ]]; then
  mode=$(head -c 64 "$cfg/.mode" 2>/dev/null | tr -d '[:space:]') || mode=""
fi
if [[ -n "$mode" && "$mode" != "cook" ]]; then
  # An unknown mode name, or a missing/malformed modes.json, resolves to cook: stay silent.
  known_mode=$(jq -r --arg m "$mode" 'if (.modes[$m]|type) == "object" then "1" else empty end' "$cfg/modes.json" 2>/dev/null) || known_mode=""
  if [[ "$known_mode" == "1" ]]; then
    # `args` may be a bare string (research-sweep), which makes `.args.mode` a jq error: fail open.
    args_mode=$(jq -r '.tool_input.args.mode // empty' <<<"$input" 2>/dev/null) || args_mode=""
    if [[ -z "$args_mode" ]]; then
      msgs+=("Mode '${mode}' is active but this Workflow call's args carry no mode. Workflow scripts cannot read the filesystem, so args.mode is the only way they learn it — without it this run uses cook roles and uncapped fan-out. Pass mode: \"${mode}\" in args.")
    fi
  fi
fi

script=$(jq -r '.tool_input.script // empty' <<<"$input" 2>/dev/null) || finish
if [[ -z "$script" ]]; then
  path=$(jq -r '.tool_input.scriptPath // empty' <<<"$input" 2>/dev/null) || finish
  if [[ -z "$path" ]]; then
    # Saved workflow invoked by name: resolve it under the config dir; stay silent if it isn't there.
    name=$(jq -r '.tool_input.name // empty' <<<"$input" 2>/dev/null) || finish
    [[ -n "$name" ]] || finish
    path="${cfg}/workflows/${name}.js"
  fi
  [[ -r "$path" ]] || finish
  script=$(cat "$path" 2>/dev/null) || finish
fi
[[ -z "$script" ]] && finish

roster_dir="${cfg}/agents"
shopt -s nullglob
roster=()
for f in "$roster_dir"/*.md; do
  n=$(basename "$f" .md)
  grep -q '^name:' "$f" 2>/dev/null && roster+=("$n")
done
[[ ${#roster[@]} -eq 0 ]] && finish

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
  # Two accepted forms: a quoted literal, and the mode-substitution helper `role('scout')`.
  # The helper's argument is the roster name written in the workflow, so it is checked the same way.
  role=""
  if [[ "$seg" =~ agentType:[[:space:]]*[\'\"]([A-Za-z0-9_-]+)[\'\"] ]]; then
    role="${BASH_REMATCH[1]}"
  elif [[ "$seg" =~ agentType:[[:space:]]*role\([[:space:]]*[\'\"]([A-Za-z0-9_-]+)[\'\"] ]]; then
    role="${BASH_REMATCH[1]}"
  fi
  if [[ -n "$role" ]]; then
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

[[ $violations -eq 0 ]] && finish

if [[ -n "$unknown" ]]; then
  detail="lack agentType (or use an unknown role: ${unknown// /, })"
else
  detail="lack agentType"
fi
msgs+=("Dispatch policy: ${violations} agent() call(s) in this workflow ${detail}. Roster: ${roster[*]}. Every Workflow agent() must set agentType to a roster role and never a bare model.")
finish
