#!/usr/bin/env bash
# Tests for dispatch-guard.sh: always exit 0; nudge on absent/unknown role; silent on roster role or garbage.
set -u
HOOK="$(dirname "$0")/dispatch-guard.sh"
fail=0
check() { # name, stdin json, expect-context (yes|no)
  out=$("$HOOK" <<<"$2"); code=$?
  [[ $code -eq 0 ]] || { echo "FAIL $1: exit $code"; fail=1; return; }
  has=$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$out" 2>/dev/null)
  if [[ "$3" == yes && -z "$has" ]]; then echo "FAIL $1: expected additionalContext"; fail=1
  elif [[ "$3" == no && -n "$has" ]]; then echo "FAIL $1: unexpected additionalContext: $has"; fail=1
  else echo "ok   $1"; fi
}
check absent   '{"tool_name":"Agent","tool_input":{"prompt":"x"}}' yes
check unknown  '{"tool_name":"Agent","tool_input":{"prompt":"x","subagent_type":"general-purpose"}}' yes
check valid    '{"tool_name":"Agent","tool_input":{"prompt":"x","subagent_type":"scout"}}' no
check garbage  'not json' no
exit $fail
