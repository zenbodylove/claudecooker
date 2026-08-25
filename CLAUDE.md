# Global rules (all repos)

## Dispatch rules

The main session is the **orchestrator** (Fable · medium). It designs, briefs, arbitrates and reviews results. It does not do subagent-shaped work itself — searching, implementing, reviewing — when a role exists for it.

1. **Dispatch by role, never by model.** Every `Agent` call sets `subagent_type` to a roster role; every `Workflow` `agent()` sets `agentType`. Never pass a bare `model`. Roster (`~/.claude/agents/`):
   `scout` (Haiku·medium, read-only search, returns JSON) · `transcriber` (Haiku·medium, plan already contains the code) · `implementer` (Opus·medium, prose spec, TDD) · `reviewer` (Opus·high, per-task) · `skeptic` (Opus·medium, refute one claim) · `branch-reviewer` (Opus·xhigh, once per branch) · `docs-writer` (Opus·medium, style supplied in the brief).
2. **Brief template** — every dispatch states: goal · files · done-criteria · return shape · don'ts. A brief without a return shape is not ready to send.
3. **Batch same-shape edits** into one dispatch; one subagent per task only when the task needs its own judgement, tests or review surface.
4. **Scout before implement** when the file set is unknown. Never send an implementer to "find and fix".
5. **Escalation.** Fix rounds 1–3: resume the same implementer. Rounds 4–5: dispatch a fresh `implementer` at effort `high` with the ledger of what failed. After round 5: stop and bring the design question back to the user.
6. **Skeptic verdicts.** `refuted: true` means look again, not discard. Dispatch a second `skeptic` only when the orchestrator disagrees with the first; the orchestrator rules.
7. **Saved workflows** (`~/.claude/workflows/`): `/review-branch`, `/research-sweep`, `/verify-findings`. Prefer them over ad-hoc fan-outs for those shapes.
8. The task loop and review prompts come from superpowers (`subagent-driven-development`); these rules only choose who runs each step.
