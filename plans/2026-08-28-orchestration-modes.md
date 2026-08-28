# Orchestration Modes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Layer 4 — *modes* — to the dispatch framework: a `.mode` word selects a substitution table (`modes.json`) that swaps roles for cheaper tier twins and caps workflow fan-out, announced at session start and nudged by the two existing guards.

**Spec:** `specs/2026-08-28-orchestration-modes-design.md` (approved; do not redesign, do not add or drop features).

**Branch:** `feature/orchestration-modes`.

**Repo:** this repo *is* Claude Code's user config directory. Paths below are relative to the repo root (`~/claude` when editing, `~/.claude` when live). See `CLAUDE.md` §What this repo is.

---

> **Amended 2026-08-28, after this plan was executed:** in `chill`, `planner`, `debugger` and
> `branch-reviewer` were dropped from Opus·high to Opus·medium, adding the twins `planner-medium`,
> `debugger-medium` and `branch-reviewer-medium` — nine twins now, not six. This plan is kept as the
> build record of the original modes branch and its tables are *not* updated; `modes.json` and
> `CLAUDE.md` §Modes are the live source of truth. See the amendment in
> `specs/2026-08-28-orchestration-modes-design.md`.

---

## Global constraints

Carry these into every task. A task that breaks one is not done.

1. **Guards stay warn-only.** `hooks/dispatch-guard.sh`, `hooks/workflow-guard.sh` and the new `hooks/mode-context.sh` always `exit 0`, never emit `permissionDecision`, and fail open (silent) on a missing `.mode`, an unreadable or malformed `modes.json`, garbage input, or a `.mode` naming a mode that does not exist. A mode that cannot be read is `cook`.
2. **`hooks/run-tests.sh` passes at the end of every task.** It is the pre-commit hook. Run it from the repo root: `bash hooks/run-tests.sh`.
3. **Nothing repo-specific in any role file.** Twins inherit that rule from their parents.
4. **The tier table and mode semantics come from the spec verbatim.** Do not adjust a cell.
5. **New shell files are executable** (`chmod +x`), matching `hooks/*.sh` (all `0775` today).
6. **Inline `SUBS` in workflows** carries the marker `// canonical: modes.json — keep in sync (hooks/test-modes.sh)` on the line directly above `const SUBS = {`, and is deep-compared by `hooks/test-modes.sh` — the pattern `hooks/test-schemas.sh` already uses for inline schemas.
7. **Mode is machine state.** `.mode` is never tracked. Only `~/.claude/.mode` (the live config dir) is read at runtime.

## The tier table (spec §2 — the single source of truth for every assertion below)

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

## Task graph

```
1 modes.json + .gitignore ─┬─> 3 test-modes.sh ─┬─> 4 mode-context.sh + settings.json
                           │                    └─> 7 workflow mode plumbing ──> 8 capped fan-out
2 twins + implementer bump ┘
1 ─────────────────────────> 5 dispatch-guard substitution nudge
1 ─────────────────────────> 6 workflow-guard mode nudge
1 ─────────────────────────> 9 commands/mode.md
2 ─────────────────────────> 10 CLAUDE.md §Modes
1..10 ─────────────────────> 11 README.md
```

---

## Task 1 — `modes.json` and the `.gitignore` allowlist

**Kind:** transcriber
**Prerequisites:** none
**Files:** create `modes.json`; modify `.gitignore`

`.gitignore` is an allowlist (`*` ignored, policy files un-ignored). `modes.json` and the later `README.md` are both invisible to git today — verified with `git check-ignore -v modes.json README.md`, which reports `.gitignore:2:*` for both. Both un-ignore lines are added here so no later task has to touch `.gitignore` again.

- [ ] **Step 1: Write `modes.json`** at the repo root, exactly:

```json
{
  "modes": {
    "cook": { "roles": {}, "fanout": "full" },
    "flow": {
      "roles": {
        "implementer": "implementer-medium",
        "reviewer": "reviewer-medium",
        "skeptic": "skeptic-sonnet",
        "docs-writer": "docs-writer-sonnet",
        "branch-reviewer": "branch-reviewer-high"
      },
      "fanout": "full"
    },
    "chill": {
      "roles": {
        "implementer": "implementer-medium",
        "reviewer": "reviewer-sonnet",
        "skeptic": "skeptic-sonnet",
        "docs-writer": "docs-writer-sonnet",
        "branch-reviewer": "branch-reviewer-high"
      },
      "fanout": "capped"
    }
  }
}
```

- [ ] **Step 2: Un-ignore `modes.json` and `README.md`.** In `.gitignore`, in the allowlist block, after the `!settings.json` line, insert:

```gitignore
!modes.json
!README.md
```

- [ ] **Step 3: Never-track `.mode`.** In the `# never track (explicit, ...)` block, on the line directly above `settings.local.json`, insert:

```gitignore
.mode
```

- [ ] **Step 4: Verify**

```bash
jq -e '.modes | keys' modes.json
git check-ignore -v modes.json README.md ; echo "exit=$?"   # expect exit=1, no output: both now trackable
git check-ignore -v .mode                                    # expect a match: still ignored
bash hooks/run-tests.sh
```

**Test:** the four commands in Step 4. There is no committed test for this task's content yet — Task 3 adds it; that is the dependency edge.

**Done when:** `modes.json` parses and matches the block above byte-for-byte in content (whitespace may follow the repo's 2-space JSON style); `git check-ignore` reports `modes.json` and `README.md` as *not* ignored and `.mode` as ignored; `bash hooks/run-tests.sh` prints `all checks passed`.

---

## Task 2 — Six tier twins and the `implementer` effort bump

**Kind:** transcriber
**Prerequisites:** none (independent of Task 1; Task 3 depends on both)
**Files:** modify `agents/implementer.md`; create `agents/implementer-medium.md`, `agents/reviewer-medium.md`, `agents/reviewer-sonnet.md`, `agents/skeptic-sonnet.md`, `agents/docs-writer-sonnet.md`, `agents/branch-reviewer-high.md`

Agent frontmatter cannot inherit, so a twin is a **full copy** of its parent whose frontmatter differs in exactly four keys: `name`, `description`, `model`, `effort`. `tools`, `maxTurns` and the entire body stay byte-identical — Task 3's test enforces that, so it is the copy, not retyping, that is correct here. Both guards derive the roster from `agents/*.md`, so the twins join the roster with no hook edit.

`description` must differ from the parent's so a twin never competes with its parent for automatic selection; the orchestrator dispatches a twin by name, from the table.

- [ ] **Step 1: Bump `implementer` to Opus·high.** In `agents/implementer.md` frontmatter only, change `effort: medium` to `effort: high`. Change nothing else in the file. (Spec §2: the implementer's mistakes cost an Opus review round plus an Opus fix round, so under-powering it is a false economy.)

- [ ] **Step 2: Copy each parent to its twin.** Run from the repo root:

```bash
cp agents/implementer.md     agents/implementer-medium.md
cp agents/reviewer.md        agents/reviewer-medium.md
cp agents/reviewer.md        agents/reviewer-sonnet.md
cp agents/skeptic.md         agents/skeptic-sonnet.md
cp agents/docs-writer.md     agents/docs-writer-sonnet.md
cp agents/branch-reviewer.md agents/branch-reviewer-high.md
```

Do the copies **after** Step 1 so `implementer-medium.md` carries the post-bump body (the bump touches frontmatter only, but the order keeps the two files trivially in step).

- [ ] **Step 3: Rewrite each twin's `name`, `description`, `model` and `effort` lines.** Leave `tools`, `maxTurns` and the body untouched. The replacement values, in full:

`agents/implementer-medium.md`
```yaml
name: implementer-medium
description: Cost-tier twin of `implementer` (Opus · medium) — identical procedure, return contract and stop list. Dispatch instead of `implementer` when the active mode is `flow` or `chill`; see modes.json.
model: opus
effort: medium
```

`agents/reviewer-medium.md`
```yaml
name: reviewer-medium
description: Cost-tier twin of `reviewer` (Opus · medium) — identical procedure, return contract and stop list. Dispatch instead of `reviewer` when the active mode is `flow`; see modes.json.
model: opus
effort: medium
```

`agents/reviewer-sonnet.md`
```yaml
name: reviewer-sonnet
description: Cost-tier twin of `reviewer` (Sonnet · high) — identical procedure, return contract and stop list. Dispatch instead of `reviewer` when the active mode is `chill`; see modes.json.
model: sonnet
effort: high
```

`agents/skeptic-sonnet.md`
```yaml
name: skeptic-sonnet
description: Cost-tier twin of `skeptic` (Sonnet · high) — identical procedure, return contract and stop list. Dispatch instead of `skeptic` when the active mode is `flow` or `chill`; see modes.json.
model: sonnet
effort: high
```

`agents/docs-writer-sonnet.md`
```yaml
name: docs-writer-sonnet
description: Cost-tier twin of `docs-writer` (Sonnet · medium) — identical procedure, return contract and stop list. Dispatch instead of `docs-writer` when the active mode is `flow` or `chill`; see modes.json.
model: sonnet
effort: medium
```

`agents/branch-reviewer-high.md`
```yaml
name: branch-reviewer-high
description: Cost-tier twin of `branch-reviewer` (Opus · high) — identical procedure, return contract and stop list. Dispatch instead of `branch-reviewer` when the active mode is `flow` or `chill`; see modes.json.
model: opus
effort: high
```

- [ ] **Step 4: Verify**

```bash
# frontmatter tiers
for f in agents/*-medium.md agents/*-sonnet.md agents/*-high.md agents/implementer.md; do
  printf '%-34s %s %s\n' "$f" "$(sed -n 's/^model: //p' "$f")" "$(sed -n 's/^effort: //p' "$f")"
done
# bodies identical to parents (everything after the closing --- on line 7-ish)
body() { awk 'c>=2{print} /^---$/{c++}' "$1"; }
for pair in "implementer implementer-medium" "reviewer reviewer-medium" "reviewer reviewer-sonnet" \
            "skeptic skeptic-sonnet" "docs-writer docs-writer-sonnet" "branch-reviewer branch-reviewer-high"; do
  set -- $pair; diff <(body "agents/$1.md") <(body "agents/$2.md") >/dev/null && echo "ok body $2" || echo "FAIL body $2"
done
bash hooks/run-tests.sh
```

**Test:** the loops in Step 4 (six `ok body …` lines, and tiers matching the table below). Task 3 turns these into a committed test.

Expected tiers: `implementer.md` opus/high · `implementer-medium` opus/medium · `reviewer-medium` opus/medium · `reviewer-sonnet` sonnet/high · `skeptic-sonnet` sonnet/high · `docs-writer-sonnet` sonnet/medium · `branch-reviewer-high` opus/high.

**Done when:** all six twins exist; each twin's body diffs clean against its parent; each twin's frontmatter differs from its parent's in exactly `name`, `description`, `model`, `effort` and no other key; `agents/implementer.md` reads `effort: high`; `bash hooks/run-tests.sh` prints `all checks passed`.

---

## Task 3 — `hooks/test-modes.sh`: modes.json, twin drift, tier table

**Kind:** implementer
**Prerequisites:** Tasks 1, 2
**Files:** create `hooks/test-modes.sh`

`hooks/run-tests.sh` globs `hooks/test-*.sh`, so the new file needs no registration. Follow `hooks/test-schemas.sh` exactly for shape: `set -u`, `ROOT="$(cd "$(dirname "$0")/.." && pwd)"`, `ok()`/`bad()` helpers that print `ok   <name>` / `FAIL <name>`, a `fail` accumulator, `exit $fail`, and runnable from any cwd. Numbered comment sections. Later tasks append sections 3 and 4 to this file.

This task writes sections 1 and 2.

**Section 1 — `modes.json` structure.** Assert: the file exists and parses (`jq -e .`); `.modes` is an object whose key set is exactly `cook`, `flow`, `chill`; every mode has an object `roles` and a string `fanout` whose value is `full` or `capped`; `cook` has an empty `roles` and `fanout: "full"`; `flow.fanout == "full"`; `chill.fanout == "capped"`; every *key* of every `roles` map names an existing `agents/<key>.md`; every *value* names an existing `agents/<value>.md`.

**Section 2 — the tier table.** Encode the spec §2 table in the test as data — this is the one place the table lives in code, and it is what makes both the twins and the `implementer` bump testable. For every (role, mode) cell, resolve the *effective* agent (`jq -r --arg m "$mode" --arg r "$role" '.modes[$m].roles[$r] // $r' modes.json`), read `model:` and `effort:` from that agent file's frontmatter, and assert they equal the cell. Suggested encoding:

```bash
# role           cook           flow            chill
TIERS='scout            haiku:medium   haiku:medium    haiku:medium
transcriber      haiku:medium   haiku:medium    haiku:medium
planner          opus:high      opus:high       opus:high
debugger         opus:high      opus:high       opus:high
implementer      opus:high      opus:medium     opus:medium
reviewer         opus:high      opus:medium     sonnet:high
skeptic          opus:medium    sonnet:high     sonnet:high
docs-writer      opus:medium    sonnet:medium   sonnet:medium
branch-reviewer  opus:xhigh     opus:high       opus:high'
```

Also in section 2, for every twin named anywhere in `modes.json` (dedup the values), with `parent` = the role key it substitutes:
- the twin file exists and its `name:` equals its basename;
- its **body** — everything after the second `---` line — is byte-identical to the parent's body (`diff`, quiet);
- its frontmatter **key set** is identical to the parent's;
- every frontmatter key *other than* `name`, `description`, `model`, `effort` has a value identical to the parent's (this is what catches an edited `tools` or `maxTurns`);
- its `description` differs from the parent's.

Extract frontmatter as the lines strictly between the first and second `---`; extract the body as everything after the second `---`. `awk '/^---$/{c++; next} c>=2{print}'` and `awk 'c>=2{print} /^---$/{c++}'` are both fine; pick one and use it consistently.

The test must be robust to a twin appearing under two modes (`skeptic-sonnet` is in both) — check each unique twin once.

- [ ] **Step 1:** Write the test with sections 1 and 2, `chmod +x hooks/test-modes.sh`.
- [ ] **Step 2:** Watch it pass: `bash hooks/test-modes.sh; echo "exit=$?"`.
- [ ] **Step 3:** Watch it fail for the right reasons. Each of these must produce a `FAIL` line and a non-zero exit, and each must be reverted afterwards:
  - `sed -i 's/^effort: high/effort: medium/' agents/implementer.md` → tier-table failure for `implementer` / `cook`.
  - append a line to `agents/reviewer.md`'s body → body-drift failure for `reviewer-medium` and `reviewer-sonnet`.
  - `sed -i 's/^maxTurns: 40/maxTurns: 41/' agents/reviewer-sonnet.md` → frontmatter-drift failure.
  - point a `modes.json` value at a non-existent twin → section 1 failure.
- [ ] **Step 4:** `bash hooks/run-tests.sh` — expect `PASS test-modes.sh` in the output and `all checks passed`.

**Test:** the file itself, plus the four fault-injection checks in Step 3 (run them, revert them, report the `FAIL` lines observed).

**Done when:** `bash hooks/test-modes.sh` exits 0 with an `ok` line per assertion group; each of the four injected faults produces a `FAIL` line and a non-zero exit; the working tree is clean of the injections; `bash hooks/run-tests.sh` prints `PASS test-modes.sh` and `all checks passed`.

---

## Task 4 — `hooks/mode-context.sh` and its `SessionStart` registration

**Kind:** implementer
**Prerequisites:** Tasks 1, 3
**Files:** create `hooks/mode-context.sh`; modify `settings.json`; modify `hooks/test-modes.sh` (append section 3)

Spec §5: the hook emits the active mode and its substitution table as `additionalContext` on `SessionStart`, so the mode survives session boundaries and compaction. Warn-only rules apply in full.

**Silent in `cook`.** Spec §3 requires that an absent, empty or unrecognised `.mode` behaves *exactly as today*; today there is no SessionStart output. So: emit only when the resolved mode is `flow` or `chill`; produce no stdout at all otherwise.

Reference implementation — follow the house style of `hooks/dispatch-guard.sh` (comment header stating the warn-only contract, `set -u`, `jq -cn --arg m …` for the output):

```bash
#!/usr/bin/env bash
# SessionStart mode announcement. Never blocks: always exit 0. Silent in cook and on any parse error.
set -u
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
mode=""
if [[ -r "$cfg/.mode" ]]; then
  mode=$(head -c 64 "$cfg/.mode" 2>/dev/null | tr -d '[:space:]') || mode=""
fi
[[ -n "$mode" && "$mode" != "cook" ]] || exit 0
[[ -r "$cfg/modes.json" ]] || exit 0
entry=$(jq -ec --arg m "$mode" '.modes[$m]' "$cfg/modes.json" 2>/dev/null) || exit 0
subs=$(jq -r 'if (.roles｜length) == 0 then "none" else (.roles｜to_entries｜map("\(.key) -> \(.value)")｜join(", ")) end' <<<"$entry" 2>/dev/null) || exit 0
fanout=$(jq -r '.fanout // "full"' <<<"$entry" 2>/dev/null) || exit 0
msg="Orchestration mode: ${mode}. Role substitutions (modes.json): ${subs}. Workflow fan-out: ${fanout}. Dispatch the twin, not the parent, for every substituted role, and pass mode: \"${mode}\" in args to every Workflow call."
jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
exit 0
```

(The `｜` characters above are stand-ins for jq's pipe `|` so this plan's fenced block survives transcription — write real `|` in the script.)

`head -c 64` bounds a `.mode` that is accidentally a large or binary file. The hook reads nothing from stdin; SessionStart passes JSON on stdin which is simply ignored.

- [ ] **Step 1:** Write `hooks/mode-context.sh`, `chmod +x`.
- [ ] **Step 2: Register it in `settings.json`.** Add a `SessionStart` key inside `hooks`, sibling to `PreToolUse`, with **no matcher** so it fires on startup, resume, clear and compact alike:

```json
"SessionStart": [
  {
    "hooks": [
      { "type": "command", "command": "$HOME/.claude/hooks/mode-context.sh", "timeout": 10 }
    ]
  }
]
```

Match the existing 2-space indentation and the `$HOME/.claude/hooks/...` command form used by the two PreToolUse entries. Verify with `jq -e '.hooks.SessionStart' settings.json`.

- [ ] **Step 3: Append section 3 to `hooks/test-modes.sh`** — `mode-context.sh` behaviour. Build a temp config dir with `mktemp -d`, copy the repo's `modes.json` into it, and drive the hook with `CLAUDE_CONFIG_DIR=$tmp bash hooks/mode-context.sh </dev/null`. Assert exit 0 in every case, and:

| case | `.mode` contents | expect |
|---|---|---|
| `mode-context-absent` | file not created | no stdout |
| `mode-context-empty` | `` (empty file) | no stdout |
| `mode-context-cook` | `cook` | no stdout |
| `mode-context-garbage` | `banana` | no stdout |
| `mode-context-flow` | `flow` | `additionalContext` present, contains `flow`, `reviewer-medium`, `skeptic-sonnet` |
| `mode-context-chill` | `chill` | `additionalContext` present, contains `chill`, `reviewer-sonnet`, `capped` |
| `mode-context-no-modes-json` | `chill`, and `modes.json` deleted from the temp dir | no stdout |
| `mode-context-bad-modes-json` | `chill`, `modes.json` = `not json` | no stdout |
| `mode-context-trailing-newline` | `chill\n` (i.e. `printf 'chill\n'`) | same as `mode-context-chill` |
| `mode-context-event-name` | `chill` | `.hookSpecificOutput.hookEventName == "SessionStart"` |

Clean up the temp dir with `rm -rf`. Reuse the section's own small helper rather than reshaping sections 1–2.

- [ ] **Step 4:** `bash hooks/test-modes.sh` then `bash hooks/run-tests.sh`.

**Test:** section 3 of `hooks/test-modes.sh` (ten cases above).

**Done when:** every case in the table passes with exit 0; `settings.json` parses and `jq -e '.hooks.SessionStart[0].hooks[0].command' settings.json` prints the hook path; the hook writes nothing to stdout in `cook` and in every failure mode; `bash hooks/run-tests.sh` prints `all checks passed`.

---

## Task 5 — `dispatch-guard.sh`: substitution nudge

**Kind:** implementer
**Prerequisites:** Tasks 1, 2
**Files:** modify `hooks/dispatch-guard.sh`; modify `hooks/test-dispatch-guard.sh`

Spec §5: after the existing roster check, if the active mode substitutes the dispatched `subagent_type`, emit `additionalContext` naming the twin. This is the one place the check cannot be missed, because it runs on every `Agent` call — it catches the orchestrator quietly reverting to `reviewer` once the session-start reminder has scrolled out of attention.

**The structural obstacle:** line 14 of the guard today is

```bash
for r in "${roster[@]}"; do [[ "$type" == "$r" ]] && exit 0; done
```

A roster hit exits before any mode check can run. Restructure it into a `known` flag, then branch: if `known`, do the substitution check and either emit the mode nudge or `exit 0`; if not known, fall through to the existing unknown-role / absent-type messages unchanged. Do not alter the wording or the trigger conditions of the two existing messages — Task 5 adds a message, it does not edit one.

The substitution lookup, honouring the fail-open rule at every step:

```bash
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
mode=""
if [[ -r "$cfg/.mode" ]]; then
  mode=$(head -c 64 "$cfg/.mode" 2>/dev/null | tr -d '[:space:]') || mode=""
fi
[[ -n "$mode" && "$mode" != "cook" ]] || exit 0
twin=$(jq -r --arg m "$mode" --arg t "$type" '.modes[$m].roles[$t] // empty' "$cfg/modes.json" 2>/dev/null) || exit 0
[[ -n "$twin" ]] || exit 0
```

A garbage mode name, a missing or malformed `modes.json`, or a role with no substitution all yield an empty `twin` and a silent `exit 0`. Note that `$cfg` must be derived independently — the existing `roster_dir` variable already inlines the same expression; either reuse a single `cfg` variable for both or leave `roster_dir` as it is, but do not introduce a second spelling of the default.

Message: name the mode, the requested role and the twin, and point at `modes.json`. Suggested wording, in the register of the existing two:

> `Mode '<mode>': '<type>' is substituted by '<twin>' (modes.json). Dispatch <twin> instead — same contract, cheaper tier. Cook-tier dispatch is still legal; this is a reminder, not a block.`

A dispatch that already names a twin (`reviewer-sonnet`) is a roster role with no entry in the substitution map, so it stays silent for free — assert that.

- [ ] **Step 1: Extend `hooks/test-dispatch-guard.sh` first.** Keep the existing `check()` helper and the existing thirteen assertions untouched. Add a mode block that builds a temp config dir (`mktemp -d`), copies `agents/*.md` and `modes.json` into it, writes `.mode`, and drives the guard with `CLAUDE_CONFIG_DIR=$tmp`. Cases:

| case | `.mode` | `subagent_type` | expect |
|---|---|---|---|
| `mode-flow-implementer` | `flow` | `implementer` | context |
| `mode-flow-reviewer` | `flow` | `reviewer` | context |
| `mode-chill-reviewer` | `chill` | `reviewer` | context |
| `mode-chill-branch-reviewer` | `chill` | `branch-reviewer` | context |
| `mode-cook-reviewer` | `cook` | `reviewer` | none |
| `mode-absent-reviewer` | file not created | `reviewer` | none |
| `mode-garbage-reviewer` | `banana` | `reviewer` | none |
| `mode-empty-reviewer` | `` (empty) | `reviewer` | none |
| `mode-flow-scout` | `flow` | `scout` | none (no substitution for scout) |
| `mode-flow-planner` | `flow` | `planner` | none |
| `mode-chill-twin` | `chill` | `reviewer-sonnet` | none (already the twin) |
| `mode-no-modes-json` | `chill`, `modes.json` removed from the temp dir | `reviewer` | none (fails open) |
| `mode-bad-modes-json` | `chill`, `modes.json` = `not json` | `reviewer` | none |
| `mode-chill-unknown-role` | `chill` | `general-purpose` | context (the existing unknown-role nudge still fires) |

Add one assertion that the emitted text for `mode-chill-reviewer` contains the string `reviewer-sonnet` — presence alone is not enough for this hook, because naming the twin is the point. A small `check_contains()` helper alongside `check()` is the cleanest way; do not reshape `check()`.

`check()` already asserts exit 0 in every case, which covers the never-blocks rule.

- [ ] **Step 2:** Run the extended test, watch the new cases fail.
- [ ] **Step 3:** Restructure the guard as above; rerun until green.
- [ ] **Step 4:** `bash hooks/run-tests.sh`.

**Test:** `hooks/test-dispatch-guard.sh`, extended with the fourteen cases above plus the `check_contains` assertion.

**Done when:** all existing assertions still pass unchanged; all new cases pass; `grep -c 'permissionDecision' hooks/dispatch-guard.sh` is 0 and the script's only exit statuses are 0; `bash hooks/run-tests.sh` prints `all checks passed`.

---

## Task 6 — `workflow-guard.sh`: missing-`mode`-in-`args` nudge

**Kind:** implementer
**Prerequisites:** Task 1
**Files:** modify `hooks/workflow-guard.sh`; modify `hooks/test-workflow-guard.sh`

Spec §5: if the active mode is not `cook` and the `Workflow` call's `args` carry no `mode`, nudge. A workflow that never learns the mode silently runs at cook tiers.

**The structural obstacle:** the guard has seven early `exit 0`s in its script-resolution block (unresolvable `name`, unreadable path, empty script) and one more when `violations` is zero. The mode nudge is about `args`, not about the script, so it must survive all of them. Restructure with an accumulator and a single exit path:

```bash
msgs=()
finish() {
  if [[ ${#msgs[@]} -gt 0 ]]; then
    printf -v joined '%s ' "${msgs[@]}"
    jq -cn --arg m "${joined% }" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
  fi
  exit 0
}
```

Compute the mode message **first**, push it onto `msgs`, then replace every subsequent `exit 0` with `finish`. The existing violation message becomes the second `msgs` entry rather than a direct `jq` emit. Guard `"${msgs[@]}"` behind the `${#msgs[@]}` length check (this repo's bash is 5.2, but the check is free and correct on older bash too).

Mode resolution is the same fail-open sequence as Task 5. The `args` lookup must not abort the script when `args` is a string rather than an object — `research-sweep` is documented to accept `args` as a bare question string, and `jq` errors on `"str".mode`:

```bash
args_mode=$(jq -r '.tool_input.args.mode // empty' <<<"$input" 2>/dev/null) || args_mode=""
```

Nudge condition: resolved mode is non-empty, is not `cook`, **is a real key in `modes.json`** (so a garbage `.mode` stays silent — it resolves to cook), and `args_mode` is empty. Suggested wording:

> `Mode '<mode>' is active but this Workflow call's args carry no mode. Workflow scripts cannot read the filesystem, so args.mode is the only way they learn it — without it this run uses cook roles and uncapped fan-out. Pass mode: "<mode>" in args.`

- [ ] **Step 1: Extend `hooks/test-workflow-guard.sh` first.** Keep the existing `check()` helper and all thirteen existing assertions untouched. Note that the existing assertions run against the *live* `~/.claude`, so any of them could start failing if the machine's real `.mode` is non-default — pin them by giving the new cases their own `CLAUDE_CONFIG_DIR`, and additionally set `CLAUDE_CONFIG_DIR` to a temp dir with no `.mode` for the pre-existing cases if the implementer finds them mode-sensitive. (They are: with a non-default live `.mode` and no `args`, every existing case would gain a nudge. Pin them.)

Build a temp config dir containing `agents/*.md`, `workflows/` and `modes.json`, and add:

| case | `.mode` | tool_input | expect |
|---|---|---|---|
| `mode-chill-no-args` | `chill` | clean script, no `args` | context |
| `mode-chill-args-no-mode` | `chill` | clean script, `args: {"base":"dev"}` | context |
| `mode-chill-args-mode` | `chill` | clean script, `args: {"mode":"chill"}` | none |
| `mode-flow-args-mode` | `flow` | clean script, `args: {"mode":"flow"}` | none |
| `mode-chill-args-string` | `chill` | clean script, `args: "how does X work"` | context (must not crash) |
| `mode-cook-no-args` | `cook` | clean script, no `args` | none |
| `mode-absent-no-args` | file not created | clean script, no `args` | none |
| `mode-garbage-no-args` | `banana` | clean script, no `args` | none |
| `mode-chill-unresolvable-name` | `chill` | `{"name":"no-such-workflow-xyz"}`, no `args` | context (mode nudge survives the early exit) |
| `mode-chill-plus-violation` | `chill` | script with a bare `agent('x', { label: 'b' })`, no `args` | context containing **both** `agentType` and `args.mode`-related text |
| `role-helper` | `cook` | script with `agentType: role('reviewer')` | none (regression: Task 7's helper form must not read as a violation) |

"clean script" = a script whose every `agent()` call names a roster role, e.g. `const a = await agent('go', { agentType: 'scout', label: 's' })`.

The `role-helper` case matters: after Task 7 the workflows call `agent(..., { agentType: role('reviewer'), ... })`. The guard's regex requires a quoted literal after `agentType:`, and its no-`agentType` branch requires the substring to be absent — so `role('reviewer')` matches neither branch and is silent today. Lock that in before Task 7 relies on it.

- [ ] **Step 2:** Run the extended test, watch the new cases fail.
- [ ] **Step 3:** Restructure the guard; rerun until green.
- [ ] **Step 4:** `bash hooks/run-tests.sh`.

**Test:** `hooks/test-workflow-guard.sh`, extended with the eleven cases above.

**Done when:** all existing assertions still pass unchanged; all new cases pass; the guard never emits two separate JSON objects (one `additionalContext` string, messages joined); `grep -c 'permissionDecision' hooks/workflow-guard.sh` is 0; `bash hooks/run-tests.sh` prints `all checks passed`.

---

## Task 7 — Workflow mode plumbing and the inline-`SUBS` sync test

**Kind:** implementer
**Prerequisites:** Tasks 1, 3
**Files:** modify `workflows/review-branch.js`, `workflows/research-sweep.js`, `workflows/verify-findings.js`; modify `hooks/test-modes.sh` (append section 4)

Spec §6: workflow scripts have no filesystem access, so the mode arrives only through `args`. Each script resolves roles through a helper. Three same-shape edits, batched, plus the drift test that keeps the inline copy honest.

**The inline constant.** Insert into each of the three workflows, after the existing `args` destructuring near the top and before the schema constants:

```js
const mode = (args && args.mode) || 'cook'

// canonical: modes.json — keep in sync (hooks/test-modes.sh)
const SUBS = {
  cook: { roles: {}, fanout: 'full' },
  flow: {
    roles: {
      implementer: 'implementer-medium',
      reviewer: 'reviewer-medium',
      skeptic: 'skeptic-sonnet',
      'docs-writer': 'docs-writer-sonnet',
      'branch-reviewer': 'branch-reviewer-high',
    },
    fanout: 'full',
  },
  chill: {
    roles: {
      implementer: 'implementer-medium',
      reviewer: 'reviewer-sonnet',
      skeptic: 'skeptic-sonnet',
      'docs-writer': 'docs-writer-sonnet',
      'branch-reviewer': 'branch-reviewer-high',
    },
    fanout: 'capped',
  },
}
const role = r => (SUBS[mode] && SUBS[mode].roles[r]) || r
```

`SUBS` holds each mode's **whole** entry — `roles` *and* `fanout` — rather than the roles map alone, so it deep-equals `modes.json`'s `.modes` object exactly and Task 8's fan-out cap has a tested source instead of a hardcoded `mode === 'chill'`. Spec §6's sketch (`const SUBS = { flow: {...}, chill: {...} }`) is preserved in substance: one inline constant, one `// canonical: modes.json` marker, one `role()` helper, deep-compared. See open question 1.

**Formatting is load-bearing.** The test parser is line-based, following `hooks/test-schemas.sh`: the marker comment sits on the line *directly above*, the literal starts at `const SUBS = {` at **column 0**, and it ends at a line that is exactly `}` at **column 0**. No inner line may be exactly `}`; the two-space indentation above guarantees that.

**`fanout`.** Add `const fanout = (SUBS[mode] && SUBS[mode].fanout) || 'full'` to `review-branch.js` and `research-sweep.js` only — Task 8 consumes it. `verify-findings.js` gets `mode`, `SUBS` and `role` but no `fanout` (spec §6: its shape is unchanged, only the role substitutes).

**Call sites.** Replace every quoted `agentType` with the helper, and nothing else:

- `workflows/review-branch.js` — `agentType: 'reviewer'` → `agentType: role('reviewer')`; `agentType: 'skeptic'` → `agentType: role('skeptic')`.
- `workflows/research-sweep.js` — `agentType: 'scout'` → `agentType: role('scout')`; `agentType: 'implementer'` → `agentType: role('implementer')`; `agentType: 'reviewer'` → `agentType: role('reviewer')`.
- `workflows/verify-findings.js` — `agentType: 'skeptic'` → `agentType: role('skeptic')`.

`scout` has no substitution in any mode, so `role('scout')` is a no-op today; use the helper uniformly anyway so a future table change needs no call-site edit.

Do **not** change `meta`, phase titles, schemas, prompts or control flow in this task. `research-sweep.js` also reads `args.angles` and `args.question`; leave that logic alone.

**Section 4 of `hooks/test-modes.sh`** — inline `SUBS` deep-compare. Mirror `hooks/test-schemas.sh`'s node block: a `node -e "$(cat <<'JS' … JS)" "$ROOT"` heredoc that, for every `workflows/*.js`:
- if the source contains an `agent(` call, require a `const SUBS = {` line at column 0 (fail if absent — this is what stops a new workflow from silently ignoring modes);
- require the previous line to match `^\s*\/\/ canonical: modes\.json — keep in sync \(hooks\/test-modes\.sh\)\s*$` (note the em dash, matching the schemas marker exactly);
- slice from that line to the first following line equal to `}`, strip the `const SUBS = ` prefix, evaluate it with `new Function('return ' + literal)()`;
- deep-compare (key-sorted `JSON.stringify`, as `test-schemas.sh`'s `sortDeep`/`norm` do) against `JSON.parse(modes.json).modes`;
- also require the source to contain `const role =` and to contain no remaining quoted `agentType: '…'` literal.

- [ ] **Step 1:** Append section 4 to `hooks/test-modes.sh`; run it and watch it fail on all three workflows.
- [ ] **Step 2:** Make the three workflow edits; rerun until green.
- [ ] **Step 3:** Fault injection — change one twin name inside one workflow's `SUBS` (e.g. `reviewer-sonnet` → `reviewer-sonner`), confirm a `FAIL … drifted from modes.json` line and a non-zero exit, then revert.
- [ ] **Step 4:** `bash hooks/run-tests.sh` — the three `PASS syntax workflows/*.js` lines must still appear (the `AsyncFunction` construction is how workflow syntax is checked), plus `PASS test-schemas.sh` (the schema constants must be untouched) and `PASS test-modes.sh`.

**Test:** section 4 of `hooks/test-modes.sh`, plus the fault injection in Step 3.

**Done when:** all three workflows define `mode`, `SUBS`, `role`; `review-branch.js` and `research-sweep.js` also define `fanout`; no quoted `agentType: '…'` literal remains in `workflows/`; section 4 passes and fails correctly under injection; `bash hooks/run-tests.sh` prints `all checks passed`.

---

## Task 8 — Capped fan-out in `review-branch` and `research-sweep`

**Kind:** implementer
**Prerequisites:** Task 7
**Files:** modify `workflows/review-branch.js`, `workflows/research-sweep.js`

Spec §6, `fanout: "capped"` (chill only). `verify-findings.js` is deliberately **not** touched: the caller hands it exactly the findings it wants checked, so capping it would mean not doing what was asked.

**`workflows/review-branch.js`** — skeptic-verify only `critical` and `important` findings; return `minor` ones in a separate `unverified` array; the result carries `mode`, so a cheap review can never be read later as a thorough one.

- After the dedup barrier, split: `const capped = fanout === 'capped'`, `const toVerify = capped ? all.filter(f => f.severity !== 'minor') : all`, `const unverified = capped ? all.filter(f => f.severity === 'minor') : []`.
- Extend the existing `log()` line, or add one, to report the split when `capped` — e.g. `verifying N, returning M minor finding(s) unverified`.
- The existing early return at `if (!all.length)` must gain `unverified: []` and `mode` so every return path has the same shape.
- Add a second early return for the case where `all` is non-empty but `toVerify` is empty (every finding was minor): return the same shape with `unverified` populated, without entering the Verify phase.
- `pipeline(toVerify, …)` replaces `pipeline(all, …)`.
- The final `out` object gains `unverified` and `mode`. Keep `dimensions_run`, `confirmed`, `refuted`, `uncertain` and the severity sort exactly as they are.

**`workflows/research-sweep.js`** — deep-read at most 4 survivors, and report how many were skipped.

- `const readCap = fanout === 'capped' ? 4 : 20` — 20 is the existing uncapped slice, so `cook` behaviour is bit-for-bit unchanged.
- Slice `[...byPath.values()]` to `readCap`; compute `skipped = byPath.size - unique.length`.
- Rewrite the existing `log()` line (which currently hardcodes `> 20`) to report the cap and the skipped count from the variables.
- The returned map gains a `skipped` field: `return map && typeof map === 'object' ? { ...map, skipped } : map`. `schemas/research-map.json` sets no `additionalProperties: false`, so the extra key is legal. Do **not** add `mode` here — spec §6 asks for it on `review-branch` only.

**Behavioural verification.** The committed suite only syntax-checks workflows; there is no committed runner. Write a throwaway harness under the scratchpad directory (not in the repo, not committed) that loads each workflow the way `hooks/run-tests.sh` does and drives it with stubs:

```js
const src = fs.readFileSync(file, 'utf8').replace(/^export\s+/gm, '')
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor
const fn = new AsyncFunction('args', 'agent', 'parallel', 'pipeline', 'phase', 'log', src)
const seen = []
const agent = async (prompt, opts) => { seen.push(opts.agentType); return canned(opts) }
const parallel = fns => Promise.all(fns.map(f => f()))
const pipeline = (items, f) => Promise.all(items.map((it, i) => f(it, items, i)))
await fn(args, agent, parallel, pipeline, () => {}, () => {})
```

Assert, and paste the output into the task report:
- `review-branch` with `args = {base:'dev', mode:'chill'}` and canned findings of severities critical/important/minor: exactly two skeptic calls; `result.unverified.length === 1`; `result.mode === 'chill'`; the review-phase `agentType`s are `reviewer-sonnet` and the verify-phase ones `skeptic-sonnet`.
- `review-branch` with `args = {base:'dev'}`: three skeptic calls; `result.unverified` empty; `result.mode === 'cook'`; `agentType`s `reviewer` and `skeptic`.
- `review-branch` with `args = {mode:'chill'}` and only minor findings: zero skeptic calls, `unverified.length` equal to the finding count, no crash.
- `research-sweep` with `args = {question:'q', mode:'chill'}` and six unique matches across the sweep: exactly four read calls, `result.skipped === 2`, read `agentType` is `implementer-medium`, synthesis `agentType` is `reviewer-sonnet`.
- `research-sweep` with `args = {question:'q'}` and six unique matches: six read calls, `result.skipped === 0`, `agentType`s `implementer` and `reviewer`.

**Test:** the scratchpad harness above (five scenarios), plus `bash hooks/run-tests.sh`.

**Done when:** all five scenarios assert as specified with their output quoted in the report; `verify-findings.js` is unmodified by this task; `hooks/test-modes.sh` section 4 still passes (the `SUBS` literal must not have been touched); `bash hooks/run-tests.sh` prints `all checks passed`.

---

## Task 9 — `/mode` slash command

**Kind:** transcriber
**Prerequisites:** Task 1
**Files:** create `commands/mode.md`

`commands/` does not exist yet; create it. `.gitignore` already un-ignores `commands/` and `commands/**`, so no `.gitignore` change is needed — confirm with `git check-ignore -v commands/mode.md` (expect no match).

- [ ] **Step 1: Write `commands/mode.md`** exactly:

```markdown
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
```

- [ ] **Step 2: Verify**

```bash
git check-ignore -v commands/mode.md ; echo "exit=$?"   # expect exit=1, no output
head -5 commands/mode.md
bash hooks/run-tests.sh
```

**Test:** Step 2 — the file is trackable, its frontmatter parses as YAML (first five lines are the `---`-delimited block), and the suite passes.

**Done when:** `commands/mode.md` exists with the content above; `git check-ignore` reports it as not ignored; `bash hooks/run-tests.sh` prints `all checks passed`.

---

## Task 10 — `CLAUDE.md` §Modes

**Kind:** transcriber
**Prerequisites:** Task 2
**Files:** modify `CLAUDE.md`

Three edits: a Layer 4 row plus a paragraph in the repo-specific Architecture section, the corrected `implementer` tier in the global roster line, and a new `## Modes` section under `# Global rules (all repos)`.

- [ ] **Step 1: Layer 4 row.** In the Architecture layer table, after the `| 3 Guards | ... |` row, add:

```markdown
| 4 Modes | `modes.json` + `.mode` + `agents/*-<tier>.md` | which roster tier and fan-out the budget affords |
```

- [ ] **Step 2: Twins paragraph.** After the `**Workflow conventions:**` paragraph at the end of the Architecture section, add:

```markdown
**Tier twins are full copies and tested for drift.** A mode substitutes a role for a twin named by tier, not by mode (`reviewer-sonnet`, not `reviewer-chill`), because flow and chill share four of their five substitutions. Agent frontmatter cannot inherit, so each twin is a byte-identical copy of its parent's body with `name`, `description`, `model` and `effort` changed — and `hooks/test-modes.sh` asserts exactly that, so editing a parent's stop list and forgetting the twin fails the pre-commit hook. The same test asserts every (role, mode) cell of the tier table and deep-compares each workflow's inline `SUBS` constant against `modes.json`, the way `hooks/test-schemas.sh` does for inline schemas. `.mode` is untracked: it is machine state, and the two checkouts must not disagree about it.
```

- [ ] **Step 3: Fix the roster tier.** In `## Dispatch rules` rule 1, change `implementer` (Opus·medium, prose spec, TDD)` to `implementer` (Opus·high, prose spec, TDD)`. Change nothing else on that line; the roster there names the nine parent roles, and the twins are documented in §Modes below it.

- [ ] **Step 4: Add `## Modes`** at the end of `CLAUDE.md`, after rule 9 of `## Dispatch rules`:

```markdown
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
```

- [ ] **Step 5: Verify**

```bash
grep -n 'Opus·high, prose spec' CLAUDE.md
grep -n '^## Modes' CLAUDE.md
grep -c '4 Modes' CLAUDE.md
bash hooks/run-tests.sh
```

**Test:** Step 5 — the roster line reads `Opus·high` for `implementer`, `## Modes` exists exactly once, the Layer 4 row exists, and the suite passes.

**Done when:** all four edits are present; the tier table in `CLAUDE.md` matches the spec's table cell for cell; no other section of `CLAUDE.md` is modified; `bash hooks/run-tests.sh` prints `all checks passed`.

---

## Task 11 — `README.md`

**Kind:** docs-writer
**Prerequisites:** Tasks 1–10
**Files:** create `README.md`

Spec §8: `README.md` is the shareable explainer, new at the repo root. `CLAUDE.md` remains the instruction file Claude loads; the README is for people. Dispatch a `docs-writer` (or `docs-writer-sonnet` if a non-default mode is active), not a transcriber — the wording is the deliverable, and this plan deliberately does not pre-write it. See open question 3.

The brief for that dispatch must supply:

- **Audience:** an engineer who has never seen this repo and does not use Claude Code's config layout — no insider shorthand.
- **Contents,** in this order:
  1. What the repo is: it *is* Claude Code's user config directory, versioned; why there are two checkouts (`~/.claude` live, `~/claude` for editing) and how they drift.
  2. The four layers, as a table, with what each owns and where it lives — policy, roles, saved workflows, guards — plus modes as Layer 4.
  3. The roster table (nine roles, model · effort · what each is for).
  4. **The modes, branded — spec §8 makes this the README's job, and it must not be buried in a table.** Lead with the three names as an interface a stranger can act on: **Cook your Claude** when the budget is open and the work is hard; **flow** for everyday work; **chill out if you're nearing the end** of a session or weekly window and want the week to survive. Give each a sentence of when to pick it *before* showing the tier table (spec §2, verbatim), then say how to switch with `/mode cook` / `/mode flow` / `/mode chill` and that `/mode` alone reports the current one. The names should be legible to someone who has never read the spec.
  5. How the guards and the tests fit together: warn-only enforcement, `hooks/run-tests.sh` as the pre-commit hook, the two deliberate-duplication checks (`test-schemas.sh` for inline schemas, `test-modes.sh` for twins and inline `SUBS`).
  6. How to add a role, and how to add a mode — a numbered checklist each, naming every file that must change.
- **Style:** plain, direct, second-person prose; the same register as `CLAUDE.md`; British spelling; no emoji; markdown tables where the source has tables. The mode section is the one place where a lighter, memorable register is wanted — the branding is deliberate — but it stays prose, not marketing copy, and every factual claim around it still has to be true.
- **Facts:** every claim verified against `CLAUDE.md`, `modes.json`, `agents/`, `hooks/` and `workflows/` as they stand after Task 10. No invented flags or paths.
- **Don'ts:** do not restate `CLAUDE.md` verbatim; do not modify any file other than `README.md`; no TBD/TODO placeholders.

- [ ] **Step 1:** Write `README.md`.
- [ ] **Step 2: Verify**

```bash
git check-ignore -v README.md ; echo "exit=$?"   # expect exit=1 (Task 1 un-ignored it)
bash hooks/run-tests.sh
```

**Test:** Step 2, plus a read-through against the "How to add a role" checklist — following it must actually produce a working role (compare against what Task 2 did for a twin).

**Done when:** `README.md` exists and is trackable; it covers all six content items; the mode section names cook, flow and chill with the branding phrasing above and explains when to pick each before it shows the tier table; every path, role name, model and effort it states matches the repo as of Task 10; no placeholders remain; `bash hooks/run-tests.sh` prints `all checks passed`.

---

## Open questions

1. **`SUBS` shape.** Spec §6 sketches `const SUBS = { flow: {...}, chill: {...} }` with `role = r => (SUBS[mode] && SUBS[mode][r]) || r`. Task 7 instead makes `SUBS` deep-equal `modes.json`'s whole `.modes` object (all three modes, each with `roles` and `fanout`) and adjusts the helper to `SUBS[mode].roles[r]`. Reason: Task 8 needs `fanout`, and the alternatives are a second inline constant with a second derivation rule, or a hardcoded `mode === 'chill'` with no sync test at all. The spec's invariants — one inline constant, one `// canonical: modes.json` marker, deep-compared, one `role()` helper — are all preserved, and the deep-compare becomes exact rather than filtered. Confirm before Task 7, since reverting it after Task 8 is expensive.
2. **Where `mode-context.sh`'s tests live.** Spec §9 names exactly three test files and no test for `mode-context.sh`. Task 4 appends its cases to `hooks/test-modes.sh` rather than adding a fourth `hooks/test-mode-context.sh`, on the grounds that modes.json, twins, inline `SUBS` and the mode announcement are one surface. Say so if a separate file is wanted; `run-tests.sh` discovers it either way.
3. **`docs-writer` is not a `planner-report.json` `kind`.** The schema's `kind` enum is `implementer|transcriber`. Task 11 is a docs-writer dispatch as the brief requires; it is reported below as `kind: implementer` because the schema admits nothing else, and this note is the disambiguation. The task text itself says docs-writer.
4. **No committed test exercises a workflow's execution.** Task 8's capped fan-out is verified with a scratchpad harness that stubs `agent`/`parallel`/`pipeline`; the committed suite only syntax-checks workflows. The spec does not ask for a runner. If that harness should become `hooks/test-workflows.sh`, it is a small follow-up — say so and it becomes Task 8b.
5. **Existing guard tests run against the live `~/.claude`.** The first assertions in both `test-dispatch-guard.sh` and `test-workflow-guard.sh` set no `CLAUDE_CONFIG_DIR`, so once a real `.mode` exists on this machine they read it. Tasks 5 and 6 pin the mode-sensitive ones to a temp config dir. Confirm that pinning the pre-existing cases (rather than leaving them reading live state) is acceptable — it is a small change to assertions this plan otherwise leaves untouched.
