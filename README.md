# claude — a versioned Claude Code config

This repository **is** Claude Code's user config directory. It holds the policy that decides which
model does which piece of work: role definitions for subagents, saved multi-agent workflows, the
warn-only hooks that notice when a dispatch skips them, and a test suite that keeps the whole thing
honest.

There is no build and no package manager. The dependencies are `bash`, `jq` and `node`.

## Two checkouts, and why it matters

The same remote is checked out twice:

| Path | Role |
|---|---|
| `~/.claude/` | The **live** config. Claude Code reads roles, hooks, workflows, commands and `CLAUDE.md` from here. |
| `~/claude/` | A working checkout, where the config is edited as a codebase. |

The practical consequence: **an edit in `~/claude` does nothing until it lands in `~/.claude`.** The two
checkouts can drift, so compare them (`git log --oneline -3` in each) before you conclude a change had no
effect. Anything that reads state at runtime — the hooks, the `/mode` command — reads `~/.claude`, never
the working checkout.

`.gitignore` is an allowlist: `*` is ignored, and only the policy directories (`agents/ hooks/ workflows/
schemas/ specs/ plans/ commands/ skills/`) plus `CLAUDE.md`, `settings.json`, `modes.json` and this file are
un-ignored. Runtime state — sessions, history, projects, credentials, plugins — is never tracked. If you add
a new policy directory, add a `!dir/` and `!dir/**` pair or git will not see it.

Once per clone, install the test suite as the pre-commit hook:

```bash
git config core.hooksPath hooks
```

## The problem this solves

A subagent dispatched without a role inherits the session's model and effort. The session model is the
orchestrator's — the most expensive one — so by default the least deliberate work (grepping for a file
name, transcribing code a plan already contains) runs on the most expensive engine, and nothing is
consistent between sessions.

The fix is to make the model/effort decision **once, in a file**, and never per dispatch. That is what
`agents/*.md` are. Everything else here exists to keep that decision reachable, repeatable and hard to
forget.

## The four layers

| Layer | Lives at | Owns |
|---|---|---|
| 0 Policy | `CLAUDE.md` §Dispatch rules | the tier table and the hard rules the orchestrator follows |
| 1 Roles | `agents/*.md` | model, effort, tools, prompt and return contract, one file per role |
| 2 Saved workflows | `workflows/*.js` | repeatable fan-out and verify shapes |
| 3 Guards | `hooks/*.sh` + `settings.json` | warn-only enforcement of layers 0–1 |
| 4 Modes | `modes.json` + `.mode` + `agents/*-<tier>.md` | which roster tier and fan-out the budget affords |

`CLAUDE.md` is loaded by Claude Code as the global instruction file for every repo on this machine. It is
written for Claude. This README is written for you.

**A role file** is YAML frontmatter (`name`, `description`, `model`, `effort`, `tools`, `maxTurns`) plus a
body in three parts: what the role does, its **return contract** (the JSON shape it must return, naming a
canonical schema in `schemas/` where one exists), and a **stop list** of what it must never do — the scout
never edits a file, the reviewer never proposes patches. Roles are repo-agnostic; never put a project path
in one.

**A saved workflow** is a JavaScript file that the `Workflow` tool executes with `agent`, `parallel`,
`pipeline`, `phase` and `log` in scope. Three ship here: `review-branch` (one reviewer per review
dimension, then one skeptic per deduplicated finding), `research-sweep` (several scouts on different search
angles, deduplicate by path, deep-read the survivors, synthesise one map) and `verify-findings` (one
skeptic per finding, sorted into confirmed / refuted / uncertain). Workflow scripts have no filesystem
access, so anything they need to know arrives in `args`.

## The roster

| Role | Model · effort | For |
|---|---|---|
| `scout` | Haiku · medium | Read-only search: where does X live, what touches Y. Returns JSON, never prose. |
| `transcriber` | Haiku · medium | Tasks whose plan already contains the code; write it, run the tests. |
| `planner` | Opus · high | Turn a spec into a task-by-task plan file. Read-only apart from the plan it writes. |
| `implementer` | Opus · high | Multi-file work from a prose spec, TDD. |
| `debugger` | Opus · high | Reproduce, isolate the root cause, fix, verify. |
| `reviewer` | Opus · high | Per-task review of a diff against its spec. |
| `skeptic` | Opus · medium | Adversarial check of one finding: try to refute it with evidence. |
| `docs-writer` | Opus · medium | Docs prose to a style supplied in the brief, never hard-coded. |
| `branch-reviewer` | Opus · xhigh | Whole-branch review once, before merge. |

Adding a file to `agents/` extends the roster automatically: both guards derive it from the basenames of
`agents/*.md` that contain a `name:` line, so no hook needs editing.

Alongside these nine there are six **tier twins** — `implementer-medium`, `reviewer-medium`,
`reviewer-sonnet`, `skeptic-sonnet`, `docs-writer-sonnet`, `branch-reviewer-high`. Each is a full copy of
its parent at a cheaper tier, and modes are what select them.

## Modes: cook, flow, chill

Seven of the nine roles are Opus, so the framework as built spends its scarcest resource on nearly every
dispatch. A mode says how much of that you can currently afford. Set one word in `~/.claude/.mode` and the
roster shifts under you.

- **Cook your Claude** when the budget is open and the work is hard. `cook` is the default and the
  baseline: everything runs at its full tier, nothing is capped. Absent, empty or unrecognised means
  `cook`, so a machine that has never heard of modes behaves exactly as it always did.
- **`flow`** is the everyday middle. The shape of the work is unchanged — full skeptic coverage, uncapped
  workflows — but the agents doing it are a notch cheaper.
- **Chill out if you're nearing the end** of a session or a weekly window and want the week to survive.
  `chill` is `flow` plus a narrower fan-out.

Two levers, and they are worth understanding separately:

1. **Tier.** Judgement work moves off Opus where being wrong is cheap to recover from. Where a role drops
   from Opus to Sonnet its effort is *raised* — `reviewer` becomes Sonnet · **high**, not Sonnet · medium.
   Effort buys thinking tokens rather than a heavier model, so Sonnet · high protects the weekly cap while
   recovering most of the judgement quality.
2. **Fan-out**, in `chill` only. The workflow shapes that spawn one agent per finding stop spawning
   unboundedly: `review-branch` skeptic-verifies only `critical` and `important` findings and returns the
   `minor` ones in a separate `unverified` array, and its result carries `mode` so a cheap review can never
   be mistaken later for a thorough one; `research-sweep` deep-reads at most 4 survivors instead of 20 and
   reports how many it `skipped`. `verify-findings` is never capped — you handed it exactly the list you
   wanted checked.

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

`planner` and `debugger` never vary: a bad plan costs more rework than the saving, and a debugger is
dispatched only when something is already wrong. `scout` and `transcriber` are Haiku already.
`implementer` goes the other way in `cook` — Opus · high, because its mistakes cost an Opus review round
plus an Opus fix round.

Switch with the slash command:

```
/mode            # report the active mode, its substitutions and its fan-out
/mode cook
/mode flow
/mode chill
```

`/mode` writes `~/.claude/.mode` — the live config directory, never the working checkout. That file is
untracked by design: it is machine state, not repo state, and the two checkouts must not disagree about it.

`modes.json` at the repo root is the substitution table — the single source of truth for which twin
replaces which role in which mode, and whether fan-out is `full` or `capped`. Twins are named by tier
(`reviewer-sonnet`), not by mode (`reviewer-chill`), because `flow` and `chill` share four of their five
substitutions.

## Guards: they nudge, they never block

Three hooks are registered in `settings.json`. All three **always exit 0**, never emit a
`permissionDecision`, and fail open — silently — on a missing file, malformed JSON or garbage input. A mode
that cannot be read is `cook`. They speak by returning `hookSpecificOutput.additionalContext`, which lands
in the orchestrator's context as a reminder.

| Hook | Fires on | Says |
|---|---|---|
| `hooks/mode-context.sh` | `SessionStart` | The active mode, its substitutions and its fan-out — so the mode survives a resume, a clear or a compaction. Silent in `cook`. |
| `hooks/dispatch-guard.sh` | `PreToolUse` / `Agent` | That no `subagent_type` was set (the agent will inherit the session model), or that the one set is not a roster role — or, in `flow` and `chill`, that the role you asked for has a cheaper twin and names it. |
| `hooks/workflow-guard.sh` | `PreToolUse` / `Workflow` | That an `agent()` call in the script sets no `agentType` or an unknown one, and that a non-default mode is active but the call's `args` carry no `mode`. |

Warn-only is a decision, not an omission. A cook-tier dispatch while `chill` is active is legal; the guard
just makes it loud. The dispatch guard is the one that matters most in a long session, because it runs on
every single `Agent` call — it catches the orchestrator quietly reverting to `reviewer` hours after the
session-start reminder scrolled out of attention.

The workflow guard reads script text heuristically rather than parsing JavaScript. It masks `(` inside
string literals and comments first, so prose containing "agent(" in a prompt is not counted as a call.

## The tests

```bash
bash hooks/run-tests.sh      # everything: each hooks/test-*.sh, then a syntax check of each workflows/*.js
bash hooks/test-modes.sh     # or run one file directly; all are runnable from any cwd
```

`run-tests.sh` globs `hooks/test-*.sh`, so a new test file needs no registration. It is also the pre-commit
hook. Workflow scripts cannot be checked with `node --check` — they use `export const meta`, top-level
`await` and top-level `return` — so the suite constructs an `AsyncFunction` from the source instead, which
catches syntax errors without executing anything.

| File | Checks |
|---|---|
| `hooks/test-dispatch-guard.sh` | The agent guard's messages and silences, including the mode substitution nudge, and exit 0 in every case. |
| `hooks/test-workflow-guard.sh` | The workflow guard's violation detection, the missing-`args.mode` nudge, and that it survives an unresolvable script or a bare-string `args`. |
| `hooks/test-schemas.sh` | Every `schemas/*.json` is valid, and every inline schema copy in a workflow still deep-matches it. |
| `hooks/test-modes.sh` | `modes.json`'s structure, every cell of the tier table, twin fidelity, `mode-context.sh`'s behaviour, and the inline `SUBS` copies. |
| `hooks/test-workflows.sh` | Executes each workflow against stubbed `agent`/`parallel`/`pipeline`, asserting which `agentType`s were dispatched and that the `chill` cap actually caps. |

Two of those are **deliberate-duplication checks**, and they are the reason this repo tolerates copied
data at all:

- **Inline schemas.** A workflow script has no filesystem access, so it must inline a copy of the return
  schema it passes to `agent()`. Each copy carries the exact marker line
  `// canonical: schemas/<file>.json — keep in sync (hooks/test-schemas.sh)` directly above it.
  `test-schemas.sh` evaluates the literal and deep-compares it against the file the marker names.
- **Inline `SUBS` and the twins.** Same problem, same answer: each workflow inlines the whole `.modes`
  object from `modes.json` under a `// canonical: modes.json — keep in sync (hooks/test-modes.sh)` marker,
  and `test-modes.sh` deep-compares it. The same test asserts that each twin's body is byte-identical to
  its parent's and that its frontmatter differs only in `name`, `description`, `model` and `effort` — so
  editing a parent's stop list and forgetting the twin fails the commit.

Both parsers are line-based: the literal must begin at `const NAME = {` in column 0 and end at a `}` in
column 0, with the marker comment on the line directly above. Reindent one and the test will tell you.

## Adding a role

1. Write `agents/<role>.md`. Frontmatter: `name` (matching the filename), a `description` whose wording
   says when to pick this role, `model`, `effort`, `tools`, `maxTurns`. Body: what the role does, its
   return contract, its stop list. Keep it repo-agnostic.
2. If the role returns a structured result, add `schemas/<name>.json` (draft-07, with `title`, `type`,
   `required`, `properties`) and name it from the return contract, the way `agents/scout.md` names
   `schemas/scout-matches.json`.
3. Add the role to the roster line in `CLAUDE.md` §Dispatch rules, rule 1, with its model, effort and a
   few words on what it is for. Add a row to the roster table in this README.
4. If the role should vary by mode, follow "Adding a mode" step 2 for its twin, add its substitutions to
   `modes.json`, add a row to the tier table in `CLAUDE.md` §Modes and to the one in this README, and add a
   row to the `TIERS` block in `hooks/test-modes.sh` so every cell is asserted. If it should never vary —
   like `planner` and `debugger` — add the `TIERS` row anyway, with the same tier in all three columns.
5. Run `bash hooks/run-tests.sh`.
6. Land the change in `~/.claude`. Roles are loaded when a session starts, so a role added mid-session is
   not dispatchable until Claude Code restarts.

No hook edit is ever needed: the guards glob `agents/*.md`.

## Adding a mode

1. Add the mode to `modes.json` as a key under `.modes`, with a `roles` object mapping role name to twin
   name and a `fanout` of `"full"` or `"capped"` — those are the only two values the tests and the
   workflows understand.
2. For every tier the new mode needs that no twin covers yet, create the twin: copy the parent file
   (`cp agents/reviewer.md agents/reviewer-sonnet.md`), then change exactly four frontmatter keys —
   `name` to the new basename, `description` to something that will not compete with the parent for
   automatic selection, `model` and `effort`. Leave `tools`, `maxTurns` and the entire body byte-identical;
   `hooks/test-modes.sh` enforces that.
3. Update the inline `SUBS` constant in **all three** of `workflows/*.js`. The inline copy must deep-equal
   the whole `.modes` object, so a mode missing from one workflow fails `hooks/test-modes.sh`.
4. Update `hooks/test-modes.sh`: the assertion that `.modes`' key set is exactly `cook,flow,chill`, the
   per-mode fan-out list (`cook:full flow:full chill:capped`), and the `TIERS` table — whose loop reads
   three columns, so a fourth mode means widening it.
5. Add a column to the tier table in `CLAUDE.md` §Modes and to the one in this README, and say in prose
   when to reach for the new mode.
6. Update `commands/mode.md`: the `description`, the `argument-hint`, and the list of names it will accept
   and report.
7. If the mode introduces genuinely new fan-out behaviour rather than reusing `full` or `capped`, the
   workflows need the branch written and `hooks/test-workflows.sh` needs a scenario for it.
8. Run `bash hooks/run-tests.sh`, then land the change in `~/.claude` and check it with `/mode`.

No guard needs editing for a new mode: all three read `modes.json` and treat any key they find there as
real.

## Where to read further

- `specs/2026-08-25-subagent-dispatch-policy-design.md` — why roles, guards and saved workflows, and what
  was deliberately left out.
- `specs/2026-08-28-orchestration-modes-design.md` — the modes design: the tier table and the reasoning
  behind every cell.
- `plans/` — the task-by-task plans these were built from.
