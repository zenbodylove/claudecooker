# Orchestration Modes — Design

**Date:** 2026-08-28 · **Owner:** Tim · **Scope:** user-level (`~/.claude/`), applies to every repo on this machine
**Builds on:** `specs/2026-08-25-subagent-dispatch-policy-design.md`

## 1. Goal

The dispatch policy makes the model/effort decision once, in a role file. That decision is currently
unconditional: `branch-reviewer` runs at Opus·xhigh whether the week's budget is untouched or nearly
spent. This spec adds **modes** — a Layer 4 that varies the roster and the workflow fan-out according
to how much budget is left.

Target constraint: a Claude Max subscription, where the binding limits are the rolling session cap and
the weekly cap, and Opus consumption is metered far more heavily than Sonnet. Seven of the nine roles
are Opus, so the framework as built spends its scarcest resource on nearly every dispatch.

Two levers, both used:
- **Tier** — move judgement work off Opus where being wrong is cheap to recover from.
- **Fan-out** — cap the workflow shapes that spawn one agent per finding.

Where a role drops from Opus to Sonnet, its effort is *raised* to compensate: effort costs thinking
tokens rather than heavier model weighting, so Sonnet·high protects the weekly cap while recovering
most of the judgement quality.

## 2. Modes

Three modes. `full-power` is today's behaviour, named so the others are diffs against it rather than
special cases.

| Role | full-power | flow | conserve |
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

`implementer` at full power rises from Opus·medium to Opus·high: it is the role whose mistakes cost a
review round plus a fix round, both of which are themselves Opus, so under-powering it is a false economy.

`planner` and `debugger` never vary. A bad plan costs more rework than the saving; a debugger is
dispatched rarely and only when something is already wrong. `scout` and `transcriber` are already Haiku.

Flow's distinction from conserve is mainly **shape, not tier**: flow keeps full skeptic coverage and
uncapped workflows with slightly cheaper agents. Conserve additionally caps the fan-out.

## 3. Mode state

`~/.claude/.mode` — one word, `full-power` | `flow` | `conserve`. Absent, empty or unrecognised means
`full-power`, so a fresh clone, a corrupt file, or a machine that has never heard of modes behaves
exactly as it does today.

**Untracked**, with an explicit never-track line in `.gitignore` beside `settings.local.json`.
`~/.claude` and `~/claude` are separate checkouts of this repo; a tracked mode file would commit budget
state and let the two disagree about it. Untracked, `~/.claude/.mode` is the only one that matters,
because that is the live config the harness reads.

`commands/mode.md` provides `/mode` (report), `/mode flow`, `/mode conserve`, `/mode full-power`.

## 4. Substitution table

`modes.json` at the repo root is the single source of truth, read by both guards and by
`hooks/test-modes.sh`:

```json
{
  "modes": {
    "full-power": { "roles": {}, "fanout": "full" },
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
    "conserve": {
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

**Twins are named by tier, not by mode** (`reviewer-sonnet`, not `reviewer-conserve`). Flow and conserve
share four of five substitutions; mode-suffixed names would have forced duplicate identical files, and
would have to be renamed whenever a future mode reuses a tier. Tier names are self-describing and
reusable, and the table absorbs the mapping.

Six twin files:

| Twin | Model · effort | Used by |
|---|---|---|
| `implementer-medium` | Opus · medium | flow, conserve |
| `reviewer-medium` | Opus · medium | flow |
| `reviewer-sonnet` | Sonnet · high | conserve |
| `skeptic-sonnet` | Sonnet · high | flow, conserve |
| `docs-writer-sonnet` | Sonnet · medium | flow, conserve |
| `branch-reviewer-high` | Opus · high | flow, conserve |

Agent frontmatter cannot inherit, so twins are full copies of their parent. The drift risk is handled the
way `schemas/` already handles it: `hooks/test-modes.sh` asserts every twin's body is identical to its
parent's and that its frontmatter differs only in `name`, `description`, `model` and `effort` — so editing
a parent's stop list and forgetting the twin fails the pre-commit hook.

Roster derivation needs no change: both guards glob `agents/*.md`, so twins join the roster automatically.

## 5. Guards (Layer 3)

All three remain **warn-only**: always `exit 0`, never `permissionDecision: deny`, fail open on any parse
error or missing file. A mode that cannot be read is `full-power`.

- **`hooks/mode-context.sh`** — new, on `SessionStart`. Emits the active mode and its substitution table
  as `additionalContext`, so mode survives session boundaries and compaction.
- **`hooks/dispatch-guard.sh`** — after its existing roster check, if the active mode substitutes the
  dispatched `subagent_type`, emit `additionalContext` naming the twin. This catches the real failure
  mode: the orchestrator is told "conserve" at the top of a long session and quietly reverts to
  `reviewer` once the reminder has scrolled out of attention. The guard runs on every `Agent` call, so
  it is the one place the check cannot be missed.
- **`hooks/workflow-guard.sh`** — if the active mode is not `full-power` and the `Workflow` call's `args`
  carry no `mode`, nudge. A workflow that never learns the mode silently runs full power.

## 6. Workflows (Layer 2)

Workflow scripts have no filesystem access, so the mode can only arrive through `args`. Each script
resolves roles through a helper:

```js
const mode = (args && args.mode) || 'full-power'
const SUBS = { flow: {...}, conserve: {...} }        // inlined, canonical: modes.json
const role = r => (SUBS[mode] && SUBS[mode][r]) || r
```

The inlined `SUBS` constant carries a `// canonical: modes.json` marker and is deep-compared against
`modes.json` by `hooks/test-modes.sh`, following the pattern `hooks/test-schemas.sh` established for
inline schema copies.

Under `fanout: "capped"` (conserve only):

- **`review-branch`** — skeptic-verifies only `critical` and `important` findings. `minor` findings are
  returned in a separate `unverified` array. The result carries `mode`, so a cheap review can never be
  read later as a thorough one.
- **`research-sweep`** — deep-reads at most 4 survivors, and reports how many it skipped.
- **`verify-findings`** — shape unchanged. The caller hands it exactly the findings it wants checked, so
  capping it would mean not doing what was asked. Only the role substitutes.

## 7. Policy (Layer 0)

`CLAUDE.md` gains a §Modes section: the tier table, the rule that a non-default mode substitutes roles
per `modes.json` and passes `mode` through to every `Workflow` call, and the orchestrator-discipline
half — in `flow` and `conserve` the orchestrator keeps its own context small, preferring a `scout`
dispatch over pulling large files into the session itself. The orchestrator is Fable, and its own reads
are billed at the session tier regardless of how cheap its subagents are.

## 8. Documentation

`README.md`, new at the repo root: the shareable explainer. What the repo is and why it has two
checkouts, the four layers, the roster and mode tables, how the guards and tests fit together, and how
to add a role or a mode. `CLAUDE.md` remains the instruction file Claude loads; the README is for people.

## 9. Testing

`hooks/run-tests.sh` discovers `hooks/test-*.sh` automatically, so new files need no registration.

- **`hooks/test-modes.sh`** — new. `modes.json` parses and every twin it names exists; every twin's
  model/effort matches this spec's table; twin bodies are identical to their parents; inline `SUBS`
  constants in `workflows/*.js` deep-match `modes.json`.
- **`hooks/test-dispatch-guard.sh`** — extended: substitution nudge fires in `flow` and `conserve`,
  stays silent in `full-power`, stays silent for a role with no substitution, and fails open when
  `.mode` is absent or contains garbage.
- **`hooks/test-workflow-guard.sh`** — extended: nudge when a non-default mode is active and `args`
  carry no `mode`; silent when they do.

Hook tests already run against a temporary `CLAUDE_CONFIG_DIR`, so mode cases set up the same way.

## 10. Decisions and non-goals

- **Advisory, not enforced.** Nothing prevents a full-power dispatch in conserve mode; the guards only
  make it loud. A `permissionDecision: deny` is available later if loud proves insufficient, but it
  would be this framework's first block and contradicts the warn-only rule in the dispatch spec.
- **No automatic switching.** Modes are set by hand via `/mode`. Scraping usage data to switch on
  thresholds needs a data source whose existence and stability are unverified; not built.
- **Mode is machine state, not repo state.** It is deliberately invisible to git.
