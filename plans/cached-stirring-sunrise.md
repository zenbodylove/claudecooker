# Review, fix, and merge all open PRs (excluding #1259)

## Context

Five open PRs (all from the agent account `illuminaturesales42`, all marked "not for merge without review — for Tim"). They form **two stacks plus one supersession**:

**Stack A — desktop tester builds** (each based on the previous):
- **#1302** `feature/research-telemetry` → `dev` (+3974/−190, 69 files) — sidecar ABI fix, macOS packaging, ONNX model fetch, telemetry fixes, product fixes
- **#1303** `feature/beatgrid-mixnext-0.33.44` → #1302's branch (+6511/−173, 54 files) — beatgrid accuracy port, Mixes Next on TrackTable, cue fixes
- **#1306** `feature/mixnext-drawer` → #1303's branch (+4191/−240, 46 files) — Mix Next drawer rework **+ cherry-picked desktop limiter from #1305**

**Stack B — subscription entitlement:**
- **#1304** `feature/subscription-entitlement` → `dev` (+356/−17, 6 files) — server groundwork: `/api/config` entitlement, migration 079 tester tier, all inert behind `BILLING_ENFORCEMENT`
- **#1305** `feature/subscription-entitlement-desktop` → #1304's branch (+1870/−10, 26 files) — desktop limiter. **Superseded by #1306** (its body says so; verified: every file #1305 touches is also in #1306's diff). Plan: **close #1305 without merging** after content containment is confirmed — merging it would duplicate/conflict with #1306's cherry-picks.

Cross-stack dependency: #1306's limiter reads entitlement served by #1304 — but both are fail-open/inert, so merge order between stacks is not load-bearing. Still, land #1304 first so dev is coherent.

## Merge order

1. **#1304** → dev (smallest, server-only, inert)
2. **#1302** → dev
3. **#1303** → dev (GitHub auto-retargets to dev when #1302 merges with branch delete; otherwise retarget manually)
4. **#1306** → dev (same retarget after #1303)
5. **#1305** → close as superseded, with a comment pointing at #1306 (only after step 4's containment check passes)

## Per-PR review (before each merge)

Review each PR's **claims against the code** (lesson from the 2026-08-06 queue drain — don't trust PR bodies):
- Run `/code-review`-style review per PR via code-reviewer agents, focused on: #1304 (permission hierarchy, migration 079, enforcement-off byte-parity claim), #1302 (CI/staging script changes, CSP change for PostHog, model fetch + manifest verification), #1303 (dual `assessGridHealth` aliasing, geometry flag NOT in `analysis_status`), #1306 (limiter route gating — escape hatches under `blocked`; `clearConfig` ENTITLEMENT_KEYS; Layout `min-w-0`).
- Specific checks from memory/gotchas:
  - Migration 079: numbered migrations are manual-apply on prod (mig head is 074 per memory — confirm 075–078 status and note 079 in the runbook); `db:migrate` only applies schema.sql — ensure both edited.
  - Desktop version-number collisions (0.33.x) across the stack.
  - Fix anything found either by pushing commits to the PR branch or noting as follow-up issues, severity-dependent.

## Merge-result verification (dev has NO branch protection and CI never runs on dev)

For each merge step, before pushing the merge:
- Simulate the post-merge dev tip in a **scratch worktree** (`git worktree add`, `pnpm install`, `turbo build --filter=./packages/*`)
- Run: full workspace typecheck/build (11 packages), **full sidecar suite** (not just touched — ~2548 tests), desktop frontend tests, web tests incl. permissions, `tsc` on apps/desktop
- Only then perform the actual merge (merge commit into dev, matching repo convention "Merge PR #NNNN: …")

For step 5 (#1305): prove containment with a `commit-tree` post-stack simulation — merge #1305's content into the simulated post-#1306 dev and confirm the diff is empty/noise-only; if real deltas surface, cherry-pick them onto dev instead of closing silently.

## Out of scope / follow-ups (surface, don't do)

- Deploying migration 079 + web deploy (limiter stays inert until then; runbook `docs/guides/subscription-limiter.md`)
- #1259 (Clerk cutover) — explicitly excluded
- Known limits stated in PR bodies (code signing, macOS auto-update, bar-phase reliability) — record as issues if not already

## Verification (end state)

- All 5 PRs resolved: 4 merged into dev, #1305 closed with containment proof in the comment
- Scratch-worktree dev tip: full build + all suites green
- `git log dev` shows merge commits in the order above
