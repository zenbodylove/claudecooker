# Subagent Dispatch Policy — Design

**Date:** 2026-08-25 · **Owner:** Tim · **Scope:** user-level (`~/.claude/`), applies to every repo on this machine
**Proposal page:** https://claude.ai/code/artifact/c7427ec2-6b8f-42ea-88e0-8baad0581053

## 1. Goal

Make the model/effort/tooling decision for subagents **once, in a file**, rather than per dispatch. Three targets, in priority order: orchestration quality, overall cost, consistency across sessions and repos.

Today the session model is `fable` at effort `low`; any subagent dispatched without a `model` override inherits that — the most expensive model at the lowest effort. Nothing under `~/.claude/` or the repos standardises roles, effort, or workflow shapes.

## 2. Layers

| Layer | Owns | Lives at |
|---|---|---|
| 0 Policy | tier table, hard rules | `~/.claude/CLAUDE.md` §Dispatch rules; this spec |
| 1 Roles | model, effort, tools, prompt per role | `~/.claude/agents/*.md` |
| 2 Saved workflows | repeatable fan-out/verify shapes | `~/.claude/workflows/*.js` |
| 3 Orchestrator discipline | brief template, batching, escalation, warn hook | `~/.claude/CLAUDE.md`; `~/.claude/hooks/dispatch-guard.sh` |

Consistency comes from roles (Layer 1); orchestration quality from saved shapes (Layer 2); cost from both plus the orchestrator no longer doing subagent-shaped work.

Superpowers' `subagent-driven-development` remains the implementation loop. This policy supplies the roles it dispatches; it does not replace the loop.

## 3. Roster (Layer 1)

Orchestrator: **Fable · medium** — the session itself, set via `settings.json` `modelSettings["claude-fable-5"].effortLevel = "medium"`. It designs, briefs, arbitrates, and never performs scout/implementer/reviewer work itself.

| Role | Model · effort | Tools | Job | Return contract |
|---|---|---|---|---|
| `scout` | Haiku · medium | read-only (Read, Grep, Glob, Bash read-only, ToolSearch) | Read-only search across files/dirs/conventions | JSON per the brief's schema; never prose, never edits |
| `transcriber` | Haiku · medium | full | Implement a task whose plan already contains the code; run the tests | files changed, test command + result |
| `implementer` | Opus · medium | full | Multi-file task from a prose spec, TDD | files changed, tests added, test result, open concerns |
| `reviewer` | Opus · high | read-only | Per-task spec-compliance and code-quality review | findings list: file, line, severity, claim, evidence |
| `skeptic` | Opus · medium | read-only | Adversarial verifier: try to refute one finding | `{refuted, confidence, reasoning}` |
| `branch-reviewer` | Opus · xhigh | read-only | Whole-branch final review before merge | findings list + merge verdict |
| `docs-writer` | Opus · medium | full | Wiki/docs prose; tone guideline supplied in the brief, never hard-coded | files changed, summary |

Each role file: frontmatter `name`, `description` (with trigger phrasing), `model`, `effort`, `tools`, `maxTurns`; body = purpose, return contract, **stop list** (what the role must not do). Roles are repo-agnostic: no Mastermind-specific paths.

Design notes recorded from the brainstorm: reviewer effort was debated (low → high); one skeptic rather than a panel, with the orchestrator arbitrating; no Sonnet tier by decision — if cost bites, `docs-writer` then `reviewer` are the first to drop to Sonnet.

## 4. Hook (Layer 3)

`PreToolUse`, matcher `Agent`, script `~/.claude/hooks/dispatch-guard.sh`, registered in `~/.claude/settings.json`.

- Reads `tool_input.subagent_type` from stdin JSON.
- Roster = basenames of `~/.claude/agents/*.md` (adding a role needs no hook edit).
- If `subagent_type` is absent or not in the roster: exit 0 with JSON `hookSpecificOutput.additionalContext` naming the roster and the nearest fit ("no role set — this inherits the session model; use `scout` for search, `implementer` for changes"). Built-in types (`Explore`, `Plan`, `general-purpose`, `claude-code-guide`, `fork`) get the same nudge.
- **Never blocks** (warn mode, by decision). Fails open on any parse error.

Workflow scripts are policed by review, not by the hook: their agents are declared in script text via `agentType`.

## 5. Saved workflows (Layer 2)

All reference roles by `agentType`, pass a `schema` on every `agent()` call, and use `pipeline()` unless a barrier is genuinely needed. Located at `~/.claude/workflows/`.

- **`review-branch`** — `args: {base?: string}`. Dimensions (correctness, security, tests, simplification) → one `reviewer` per dimension → one `skeptic` per finding → confirmed list (findings the skeptic did not refute) plus a "disputed" list for the orchestrator to arbitrate. Barrier only for dedup across dimensions before the skeptic stage.
- **`research-sweep`** — `args: {question, angles?: string[]}`. N `scout`s, each with a distinct search angle → dedup by path in script code → `implementer`-tier deep-read of survivors (read-only brief) → synthesis by one `reviewer`-tier agent returning a structured map.
- **`verify-findings`** — `args: {findings: [{file, line, claim}]}`. One `skeptic` each → verdicts; script marks `confirmed / refuted / uncertain`.

## 6. Global CLAUDE.md §Dispatch rules (Layer 0/3)

About 20 lines:

1. Orchestrator is Fable · medium; it never does subagent-shaped work itself.
2. Always dispatch by role (`subagent_type` / `agentType`); never pass a bare `model`.
3. Brief template: goal · files · done-criteria · return shape · don'ts.
4. Batch same-shape edits into one dispatch.
5. Scout before implement when the file set is unknown.
6. Escalation: fix rounds 1–3 resume the implementer; rounds 4–5 dispatch a **fresh `implementer` at effort `high`**; round 5 failure returns to the orchestrator for a design decision.
7. Skeptic "refuted" means look again, not discard; dispatch a second skeptic only on orchestrator–skeptic disagreement.
8. Defers to superpowers for the task loop and review prompts.

## 7. Versioning

`~/.claude/` is a git repo (remote: https://github.com/zenbodylove/claude, private, branch `main`) tracking only: `CLAUDE.md`, `agents/`, `workflows/`, `hooks/`, `specs/`, `settings.json`, `.gitignore`. Everything else (sessions, cache, history, projects, plugins, backups, debug, downloads, file-history, paste-cache, session-env, shell-snapshots, `*.jsonl`) is ignored.

## 8. Testing

- Hook: a shell test feeds three stdin fixtures (absent / unknown / valid `subagent_type`) and asserts exit 0 in all cases, `additionalContext` present for the first two, absent for the third.
- Roles: each dispatched once on a trivial repo-agnostic task; check the return contract is honoured and the stop list respected (scout makes no edits, reviewer proposes no fixes).
- Workflows: `review-branch` run against the current Mastermind `feature/desktop-closed-beta` diff as the acceptance run; `verify-findings` fed that run's output; `research-sweep` asked one real question about the Mastermind repo.
- Settings: restart and confirm the session reports Fable at medium effort.

## 9. Out of scope (follow-ups)

Repo-level copies so Teddy inherits the roles; a Sonnet tier; blocking mode for the hook; per-role cost telemetry.

## 10. Acceptance log

**2026-08-25 (build session)**
- Hook unit tests: 4/4 pass (`hooks/test-dispatch-guard.sh`).
- Hook live: an `Agent` dispatch with no `subagent_type` received the roster nudge as `additionalContext`. Works without restart.
- Workflows: all three pass `node --check`.
- Roles: `Agent(subagent_type: "scout")` returned "not found" — `~/.claude/agents/` did not exist at session start, so roles load on the next Claude Code restart (documented behaviour).
- Fable effort medium: set in `settings.json`; takes effect on restart.

**Pending, next session:** dispatch `scout` and `skeptic` once each and check the return contract; run `/review-branch` with `{base: "dev"}` on `mastermindmusic` `feature/desktop-closed-beta`; confirm `/model` shows Fable · medium.
