---
description: Show or set the orchestration mode (cook | flow | chill) that selects the roster tier and workflow fan-out
argument-hint: [cook|flow|chill]
allowed-tools: Bash, Read
---

# Mode

Requested mode: `$ARGUMENTS` (may be empty).

The mode file is `~/.claude/.mode` — the **live** config directory, never `~/claude/.mode`. One word. Absent, empty or unrecognised means `cook`. The substitution table is `~/.claude/modes.json`.

## No argument — report

1. Read the mode: `cat ~/.claude/.mode 2>/dev/null || echo cook`
2. Read `~/.claude/modes.json`.
3. Report three lines: the active mode; the role substitutions it applies, as `role -> twin` pairs, or `none`; and its workflow fan-out (`full` or `capped`).
4. Change nothing.

## Argument is `cook`, `flow` or `chill` — set

1. Write it: `printf '%s\n' "<mode>" > ~/.claude/.mode`
2. Read the file back to confirm.
3. Report the new mode and its substitutions from `~/.claude/modes.json`.
4. State the two rules that now apply: dispatch the twin rather than the parent for every substituted role, and pass `mode` in `args` on every `Workflow` call.

## Argument is anything else

Say the argument is not a mode, list the three valid modes, and change nothing.

## Notes

- `~/.claude/.mode` is untracked by design: it is machine state, not repo state, and the two checkouts of this repo must not disagree about it.
- Never edit `modes.json` from this command — it is the substitution table, not the state.
- Modes are advisory. Setting one changes what the guards remind you about; it blocks nothing.
