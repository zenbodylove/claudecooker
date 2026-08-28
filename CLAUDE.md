# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

This repo **is** Claude Code's user config directory. It has two checkouts of the same remote (`zenbodylove/claudecooker`):

- `~/.claude/` — the **live** config. Claude Code reads roles, hooks, workflows and this file from here. Changes only take effect once they land here.
- `~/claude/` — a working checkout for editing the config as a codebase.

Edits made in `~/claude` do nothing until pulled into `~/.claude`; the two can drift (check `git log --oneline -3` in both). `CLAUDE.md` here is served as the *global* instruction file for every repo on this machine, so its §Dispatch rules are written machine-wide, not repo-specific.

`.gitignore` is an allowlist: `*` is ignored and only policy directories (`agents/ hooks/ workflows/ schemas/ specs/ plans/ commands/ skills/`) plus `CLAUDE.md` and `settings.json` are un-ignored. Runtime state (`projects/`, `sessions/`, `history.jsonl`, `plugins/`, credentials) is never tracked. A new policy directory needs a `!dir/` + `!dir/**` pair added or it is invisible to git.

## Commands

```bash
hooks/run-tests.sh          # the whole test suite: every hooks/test-*.sh + syntax-check of every workflows/*.js
bash hooks/test-schemas.sh  # run one test file directly (same for test-dispatch-guard.sh, test-workflow-guard.sh)
git config core.hooksPath hooks   # once per clone: run-tests.sh becomes the pre-commit hook
```

There is no build, no package manager, no lint. Dependencies are `bash`, `jq` and `node`. Workflow scripts cannot be checked with `node --check` (they use `export const meta`, top-level `await` and top-level `return`); `run-tests.sh` constructs an `AsyncFunction` from the source instead.

## Working in this repo

See `~/.claude/README.md` (or `~/claude/README.md` in the working checkout) for the architecture — the four layers, the roster, how the guards and tests fit
together, and how to add a role or a mode. Four rules bind any change made here:

- **Guards never block.** `hooks/*-guard.sh` always `exit 0`, never emit `permissionDecision`, and fail
  open on every error path. Warn-only is a design decision, not an oversight.
- **Duplication is deliberate and tested.** Workflow scripts inline copies of `schemas/*.json` and of
  `modes.json` because a running script has no filesystem access; each copy carries a
  `// canonical: <path> — keep in sync (hooks/test-<x>.sh)` marker and is deep-compared by that test.
  Agent twins are full copies of their parents for the same reason. Change one side and the suite fails
  until you change the other.
- **Roles are repo-agnostic.** Never put a project path in an `agents/*.md` file.
- **`.mode` is machine state.** Untracked, deliberately — the two checkouts must not disagree about it.

# Global rules (all repos)

## Dispatch rules

The main session is the **orchestrator** (Fable · medium). It designs, briefs, arbitrates and reviews results. It does not do subagent-shaped work itself — searching, implementing, reviewing — when a role exists for it.

1. **Dispatch by role, never by model.** Every `Agent` call sets `subagent_type` to a roster role; every `Workflow` `agent()` sets `agentType`. Never pass a bare `model`. Roster (`~/.claude/agents/`):
   `scout` (Haiku·medium, read-only search, returns JSON) · `transcriber` (Haiku·medium, plan already contains the code) · `implementer` (Opus·high, prose spec, TDD) · `reviewer` (Opus·high, per-task) · `skeptic` (Opus·medium, refute one claim) · `branch-reviewer` (Opus·xhigh, once per branch) · `docs-writer` (Opus·medium, style supplied in the brief) · `debugger` (Opus·high, reproduce → root cause → fix) · `planner` (Opus·high, spec → plan file, read-only).
2. **Brief template** — every dispatch states: goal · files · done-criteria · return shape · don'ts. A brief without a return shape is not ready to send.
3. **Batch same-shape edits** into one dispatch; one subagent per task only when the task needs its own judgement, tests or review surface.
4. **Scout before implement** when the file set is unknown. Never send an implementer to "find and fix".
5. **Escalation.** Fix rounds 1–3: resume the same implementer. Rounds 4–5: dispatch a fresh `implementer` at effort `high` with the ledger of what failed — or a `debugger` when the rounds are failing on the same test. After round 5: stop and bring the design question back to the user.
6. **Skeptic verdicts.** `refuted: true` means look again, not discard. Dispatch a second `skeptic` only when the orchestrator disagrees with the first; the orchestrator rules.
7. **Saved workflows** (`~/.claude/workflows/`): `/review-branch`, `/research-sweep`, `/verify-findings`. Prefer them over ad-hoc fan-outs for those shapes.
8. The task loop and review prompts come from superpowers (`subagent-driven-development`); these rules only choose who runs each step.
9. **Ledger.** After every reviewer verdict of `request_changes`, the orchestrator appends an entry to `<repo>/.claude/ledgers/<task-slug>.md`: round number, the reviewer's findings (file:line + claim), and what the implementer changed in response. Any round-4+ brief includes the ledger verbatim. Quote it when bringing the design question back to the user.

## Modes

Modes vary the roster and the workflow fan-out with how much budget is left. The names are the interface: **cook** your Claude when the budget is open and the work is hard, **flow** for the everyday middle, **chill** when you are nearing the end of a session or weekly window and want the week to survive. The active mode is one word in `~/.claude/.mode` — `cook` | `flow` | `chill`. Absent, empty or unrecognised means `cook`, so a machine that has never heard of modes behaves exactly as it always did. Set it with `/mode flow`, `/mode chill`, `/mode cook`; `/mode` alone reports it.

| Role | cook | flow | chill |
|---|---|---|---|
| `scout` | Haiku · medium | Haiku · medium | Haiku · medium |
| `transcriber` | Haiku · medium | Haiku · medium | Haiku · medium |
| `planner` | Opus · high | Opus · high | Opus · high |
| `debugger` | Opus · high | Opus · high | Opus · high |
| `implementer` | Opus · high | Opus · medium | Opus · medium |
| `reviewer` | Opus · high | Opus · medium | Sonnet · high |
| `skeptic` | Opus · medium | Sonnet · high | Sonnet · high |
| `docs-writer` | Opus · medium | Sonnet · medium | Sonnet · medium |
| `branch-reviewer` | Opus · xhigh | Opus · high | Opus · high |
| *workflow fan-out* | full | full | capped |

1. **Substitute from the table, never from memory.** In a non-default mode, dispatch the twin `modes.json` names: `implementer-medium`, `reviewer-medium`, `reviewer-sonnet`, `skeptic-sonnet`, `docs-writer-sonnet`, `branch-reviewer-high`. Twins are named by tier, not by mode. `scout`, `transcriber`, `planner` and `debugger` never substitute — a bad plan costs more rework than the saving, and a debugger is dispatched only when something is already wrong.
2. **Pass the mode to every `Workflow` call.** Workflow scripts have no filesystem access; `args.mode` is the only way they learn it, and a workflow called without it runs at cook tiers.
3. **Capped fan-out** (`chill` only): `review-branch` skeptic-verifies only `critical` and `important` findings and returns `minor` ones in `unverified`; `research-sweep` deep-reads at most 4 survivors and reports how many it skipped. `verify-findings` is never capped — the caller already chose its list.
4. **Orchestrator discipline.** In `flow` and `chill` the orchestrator keeps its own context small, preferring a `scout` dispatch over pulling large files into the session itself. The orchestrator is Fable, and its own reads are billed at the session tier however cheap its subagents are.
5. **Advisory, not enforced.** `hooks/mode-context.sh` announces the mode at session start; `hooks/dispatch-guard.sh` names the twin when a substituted role is dispatched; `hooks/workflow-guard.sh` notices a `Workflow` call whose `args` carry no `mode`. All three only warn. A cook-tier dispatch while `chill` is active is legal and loud.
