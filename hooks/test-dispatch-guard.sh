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
rdir=$(mktemp -d /tmp/dispatch-guard-cfg.XXXXXX)
mkdir -p "$rdir/agents"
printf -- '---\nname: scout\n---\nbody\n' >"$rdir/agents/scout.md"
printf -- '# Roster README\nno frontmatter here\n' >"$rdir/agents/README.md"
CLAUDE_CONFIG_DIR="$rdir" check roster-readme-skipped '{"tool_name":"Agent","tool_input":{"prompt":"x","subagent_type":"README"}}' yes
CLAUDE_CONFIG_DIR="$rdir" check roster-name-file      '{"tool_name":"Agent","tool_input":{"prompt":"x","subagent_type":"scout"}}' no
rm -rf "$rdir"

# --- mode substitution nudge (Task 5). Pinned to a temp CLAUDE_CONFIG_DIR so results
# --- never depend on the live ~/.claude/.mode.
mdir=$(mktemp -d /tmp/dispatch-guard-mode.XXXXXX)
mkdir -p "$mdir/agents"
cp "$(dirname "$0")/../agents/"*.md "$mdir/agents/" 2>/dev/null
cp "$(dirname "$0")/../modes.json" "$mdir/modes.json"
setmode() { printf '%s' "$1" >"$mdir/.mode"; }

setmode flow
CLAUDE_CONFIG_DIR="$mdir" check mode-flow-implementer     '{"tool_name":"Agent","tool_input":{"subagent_type":"implementer"}}' yes
CLAUDE_CONFIG_DIR="$mdir" check mode-flow-reviewer        '{"tool_name":"Agent","tool_input":{"subagent_type":"reviewer"}}' yes
CLAUDE_CONFIG_DIR="$mdir" check mode-flow-scout           '{"tool_name":"Agent","tool_input":{"subagent_type":"scout"}}' no
CLAUDE_CONFIG_DIR="$mdir" check mode-flow-planner         '{"tool_name":"Agent","tool_input":{"subagent_type":"planner"}}' no
CLAUDE_CONFIG_DIR="$mdir" check mode-flow-debugger        '{"tool_name":"Agent","tool_input":{"subagent_type":"debugger"}}' no
CLAUDE_CONFIG_DIR="$mdir" check mode-flow-twin-named      '{"tool_name":"Agent","tool_input":{"subagent_type":"reviewer-medium"}}' no

setmode chill
CLAUDE_CONFIG_DIR="$mdir" check mode-chill-reviewer       '{"tool_name":"Agent","tool_input":{"subagent_type":"reviewer"}}' yes
CLAUDE_CONFIG_DIR="$mdir" check mode-chill-branch-reviewer '{"tool_name":"Agent","tool_input":{"subagent_type":"branch-reviewer"}}' yes
CLAUDE_CONFIG_DIR="$mdir" check mode-chill-scout          '{"tool_name":"Agent","tool_input":{"subagent_type":"scout"}}' no
CLAUDE_CONFIG_DIR="$mdir" check mode-chill-planner        '{"tool_name":"Agent","tool_input":{"subagent_type":"planner"}}' yes
CLAUDE_CONFIG_DIR="$mdir" check mode-chill-debugger       '{"tool_name":"Agent","tool_input":{"subagent_type":"debugger"}}' yes

printf 'chill\n' >"$mdir/.mode"
CLAUDE_CONFIG_DIR="$mdir" check mode-chill-trailing-nl    '{"tool_name":"Agent","tool_input":{"subagent_type":"reviewer"}}' yes

setmode cook
CLAUDE_CONFIG_DIR="$mdir" check mode-cook-reviewer        '{"tool_name":"Agent","tool_input":{"subagent_type":"reviewer"}}' no
setmode banana
CLAUDE_CONFIG_DIR="$mdir" check mode-garbage-reviewer     '{"tool_name":"Agent","tool_input":{"subagent_type":"reviewer"}}' no
setmode ''
CLAUDE_CONFIG_DIR="$mdir" check mode-empty-reviewer       '{"tool_name":"Agent","tool_input":{"subagent_type":"reviewer"}}' no
rm -f "$mdir/.mode"
CLAUDE_CONFIG_DIR="$mdir" check mode-absent-reviewer      '{"tool_name":"Agent","tool_input":{"subagent_type":"reviewer"}}' no

# fail-open on a broken or missing modes.json
setmode chill
printf 'not json\n' >"$mdir/modes.json"
CLAUDE_CONFIG_DIR="$mdir" check mode-bad-modes-json       '{"tool_name":"Agent","tool_input":{"subagent_type":"reviewer"}}' no
rm -f "$mdir/modes.json"
CLAUDE_CONFIG_DIR="$mdir" check mode-no-modes-json        '{"tool_name":"Agent","tool_input":{"subagent_type":"reviewer"}}' no

# the nudge names mode, requested role and twin
cp "$(dirname "$0")/../modes.json" "$mdir/modes.json"
setmode chill
out=$(CLAUDE_CONFIG_DIR="$mdir" "$HOOK" <<<'{"tool_name":"Agent","tool_input":{"subagent_type":"reviewer"}}')
ctx=$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$out" 2>/dev/null)
if [[ "$ctx" == *chill* && "$ctx" == *"'reviewer'"* && "$ctx" == *reviewer-sonnet* && "$ctx" == *modes.json* ]]
then echo "ok   mode-message-content"; else echo "FAIL mode-message-content: $ctx"; fail=1; fi
# and it is never a blocking decision
if jq -e '.hookSpecificOutput.permissionDecision' <<<"$out" >/dev/null 2>&1
then echo "FAIL mode-no-permission-decision"; fail=1; else echo "ok   mode-no-permission-decision"; fi
rm -rf "$mdir"
exit $fail
