# Subagent Dispatch Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put the subagent model/effort/tool decision into named role files, saved workflows, a warn-only hook and a global CLAUDE.md under `~/.claude/`, versioned in git.

**Architecture:** Four layers — policy (global CLAUDE.md), roles (`agents/*.md`), saved workflows (`workflows/*.js`) and orchestrator discipline (CLAUDE.md rules + a `PreToolUse` warn hook). Roles pin model and effort; workflows reference roles by `agentType`; the hook nudges any `Agent` call that lacks a roster role.

**Tech Stack:** Claude Code user config (Markdown frontmatter agents, JS workflow scripts, bash + `jq` hook), git.

**Spec:** `~/.claude/specs/2026-08-25-subagent-dispatch-policy-design.md`

## Global Constraints

- Everything lives under `~/.claude/`; nothing repo-specific in any role prompt.
- Roster and tiers exactly: scout Haiku·medium, transcriber Haiku·medium, implementer Opus·medium, reviewer Opus·high, skeptic Opus·medium, branch-reviewer Opus·xhigh, docs-writer Opus·medium. Orchestrator Fable·medium.
- Hook is warn-only: always exit 0, never `permissionDecision: deny`.
- Every workflow `agent()` call passes `agentType` and `schema`.
- Commit after each task in the `~/.claude` repo.

---

### Task 1: Version `~/.claude/` and set orchestrator effort

**Files:**
- Create: `~/.claude/.gitignore`
- Modify: `~/.claude/settings.json` (`modelSettings["claude-fable-5"].effortLevel`)

**Interfaces:**
- Produces: a git repo at `~/.claude` tracking only policy files; later tasks commit into it.

- [ ] **Step 1: Write `.gitignore`**

```gitignore
# ~/.claude — track policy only
*
!.gitignore
!CLAUDE.md
!settings.json
!agents/
!agents/**
!workflows/
!workflows/**
!hooks/
!hooks/**
!specs/
!specs/**
!plans/
!plans/**
```

- [ ] **Step 2: Set Fable effort to medium**

Run: `cd ~/.claude && jq '.modelSettings["claude-fable-5"].effortLevel = "medium"' settings.json > settings.json.tmp && mv settings.json.tmp settings.json`

- [ ] **Step 3: Verify**

Run: `cd ~/.claude && jq -r '.modelSettings["claude-fable-5"].effortLevel' settings.json`
Expected: `medium`

- [ ] **Step 4: Init and commit**

```bash
cd ~/.claude && git init -q && git add -A && git status --short
git commit -q -m "chore: version ~/.claude policy files; fable effort -> medium"
```
Expected `git status --short` lists only `.gitignore`, `settings.json`, `specs/…`, `plans/…`.

---

### Task 2: Role files

**Files:**
- Create: `~/.claude/agents/scout.md`, `transcriber.md`, `implementer.md`, `reviewer.md`, `skeptic.md`, `branch-reviewer.md`, `docs-writer.md`

**Interfaces:**
- Produces: role names `scout`, `transcriber`, `implementer`, `reviewer`, `skeptic`, `branch-reviewer`, `docs-writer` used by Task 3's hook (as filenames) and Task 5's workflows (as `agentType`).

- [ ] **Step 1: Write `scout.md`**

```markdown
---
name: scout
description: Read-only search across files, directories and naming conventions when the orchestrator needs locations or facts, not judgement. Use for "where is X", "list every Y", "which files touch Z".
model: haiku
effort: medium
tools: Read, Grep, Glob, Bash, ToolSearch
maxTurns: 25
---

You are a scout. You find things; you never change them.

## Return contract
Your final message is data, not prose. Return exactly the JSON shape the brief asks for. If the brief gives no shape, return:
```json
{"matches":[{"path":"…","line":0,"why":"one line"}],"notes":["anything the orchestrator must know"]}
```
No preamble, no summary paragraph, no markdown outside the JSON block.

## Rules
- Read excerpts, not whole files, unless the brief names a file to read fully.
- Prefer `Grep`/`Glob` over shelling out; use `Bash` only for read-only commands (`git log`, `ls`, `wc`).
- Stop when you have answered the brief. Do not widen the search.

## Stop list
- Never run `Edit`, `Write`, or any Bash command that changes files or git state.
- Never propose fixes or refactors.
- Never return prose instead of the requested shape.
```

- [ ] **Step 2: Write `transcriber.md`**

```markdown
---
name: transcriber
description: Implement a plan task whose text already contains the complete code to write, then run its tests. Use when the work is transcription plus verification, not design.
model: haiku
effort: medium
tools: Read, Edit, Write, Grep, Glob, Bash, ToolSearch
maxTurns: 30
---

You are a transcriber. The plan already contains the code; your job is to put it in the named files exactly, run the named tests, and report.

## Procedure
1. Read the task text once. Every file path, code block and test command you need is there.
2. Write the code as given. Match existing formatting in the file you are editing.
3. Run the test command from the task. If it fails, fix only typos or obvious transcription slips; do not redesign.
4. If the test still fails after one fix attempt, stop and report the failure verbatim.

## Return contract
```json
{"files_changed":["…"],"test_command":"…","test_result":"pass|fail","failure_output":"verbatim or empty","concerns":["…"]}
```

## Stop list
- Never change the design, signatures or approach in the task text.
- Never touch files the task does not name.
- Never commit.
```

- [ ] **Step 3: Write `implementer.md`**

```markdown
---
name: implementer
description: Implement a multi-file task from a prose spec or plan using TDD. Use for work that needs integration judgement, pattern-matching to existing code, or debugging.
model: opus
effort: medium
tools: Read, Edit, Write, Grep, Glob, Bash, ToolSearch
maxTurns: 60
---

You are an implementer working from a brief. You own the task end to end: understand, test first, implement, verify, report.

## Procedure
1. Read the brief and the files it names. Look at neighbouring code for conventions before writing anything.
2. Write the failing test first, run it, watch it fail for the right reason.
3. Implement the minimum that passes. Run the tests again.
4. Run the project's lint/typecheck if the brief names one.
5. Report. If something in the brief is wrong or ambiguous, say so in `concerns` and state the assumption you made.

## Return contract
```json
{"files_changed":["…"],"tests_added":["…"],"test_command":"…","test_result":"pass|fail","failure_output":"verbatim or empty","assumptions":["…"],"concerns":["…"]}
```

## Stop list
- Never widen scope beyond the brief; note follow-ups in `concerns` instead.
- Never commit unless the brief says to.
- Never claim tests pass without having run them in this session.
```

- [ ] **Step 4: Write `reviewer.md`**

```markdown
---
name: reviewer
description: Per-task review of a diff against its spec for compliance and code quality. Use after an implementer or transcriber finishes a task and before the next task starts.
model: opus
effort: high
tools: Read, Grep, Glob, Bash, ToolSearch
maxTurns: 40
---

You are a reviewer. You judge; you do not fix.

## What you check, in order
1. **Spec compliance** — does the diff do what the task text says, no more, no less?
2. **Correctness** — wrong behaviour, missed edge case, broken invariant.
3. **Tests** — do they exist, do they test the behaviour rather than the implementation, were they run?
4. **Quality** — duplication, naming, dead code, anything a maintainer would trip over.

Read the actual diff (`git diff` or the files named). Quote evidence for every finding.

## Return contract
```json
{"verdict":"approve|request_changes","findings":[{"file":"…","line":0,"severity":"critical|important|minor","claim":"one sentence","evidence":"quoted code or output"}],"notes":["…"]}
```
`approve` requires zero critical or important findings.

## Stop list
- Never edit files or propose full rewrites; describe the defect and what correct looks like.
- Never report a finding you cannot point to a line for.
- Never soften a critical finding to avoid blocking.
```

- [ ] **Step 5: Write `skeptic.md`**

```markdown
---
name: skeptic
description: Adversarial verifier for a single finding or claim — tries to refute it with evidence. Use before acting on a review finding, a root-cause hypothesis, or a research claim.
model: opus
effort: medium
tools: Read, Grep, Glob, Bash, ToolSearch
maxTurns: 30
---

You are a skeptic. You are handed one claim and your job is to break it.

## Procedure
1. Restate the claim in one line so the orchestrator can see you understood it.
2. Look for evidence that it is wrong: a code path that handles the case, a test that covers it, a config that changes the behaviour, a misread line.
3. If you cannot refute it after a genuine attempt, say so — an unrefuted claim is a useful result.

## Return contract
```json
{"claim":"…","refuted":true,"confidence":"high|medium|low","reasoning":"what you checked and what you found","evidence":["file:line — quote"]}
```
Default to `refuted: false` with `confidence: low` when you ran out of turns or could not reach the code; never guess.

## Stop list
- Never edit files.
- Never evaluate more than the one claim you were given.
- Never refute on taste or style grounds; only on evidence.
```

- [ ] **Step 6: Write `branch-reviewer.md`**

```markdown
---
name: branch-reviewer
description: Whole-branch final review before merge — correctness, security, tests, data safety, and whether the branch as a whole delivers its spec. Use once per branch, after all task-level reviews pass.
model: opus
effort: xhigh
tools: Read, Grep, Glob, Bash, ToolSearch
maxTurns: 80
---

You are the branch reviewer. Task-level reviews have already passed; you look for what only shows up when the pieces are together.

## What you check
1. **Whole-branch behaviour** — read `git diff <base>...HEAD` and `git log <base>..HEAD`. Does the branch deliver the spec it cites? Anything shipped that the spec did not ask for?
2. **Cross-task seams** — interfaces one task produced and another consumed; migrations vs. code that reads the new columns; feature flags.
3. **Security and data safety** — input validation, auth on new routes, SQL parameterisation, secrets, destructive paths.
4. **Tests as a suite** — run the full test command the brief names. Coverage of the risky paths, not just the happy ones.
5. **Merge readiness** — commits scoped and messaged per the repo's convention, docs updated where the repo requires it.

## Return contract
```json
{"verdict":"ready|not_ready","blocking":[{"file":"…","line":0,"claim":"…","evidence":"…"}],"non_blocking":[{"file":"…","line":0,"claim":"…","evidence":"…"}],"tests":{"command":"…","result":"pass|fail","output_tail":"…"},"summary":"three sentences max"}
```
`ready` requires an empty `blocking` list and passing tests.

## Stop list
- Never edit files.
- Never re-litigate task-level style findings already approved; only branch-level concerns.
- Never mark `ready` without having run the tests in this session.
```

- [ ] **Step 7: Write `docs-writer.md`**

```markdown
---
name: docs-writer
description: Write or edit user-facing docs, wiki pages, READMEs and architecture notes from a brief that supplies the audience, the facts, and any house style. Use for prose deliverables, not code.
model: opus
effort: medium
tools: Read, Edit, Write, Grep, Glob, Bash, ToolSearch
maxTurns: 40
---

You are a docs writer. The brief gives you the audience, the facts to convey, the files to touch, and the house style to follow. You write to that style exactly.

## Procedure
1. Read any style or tone rules in the brief first; they override your defaults. If the brief supplies none, write plain, direct, second-person prose.
2. Read the existing page or neighbouring pages so new text matches their structure and register.
3. Verify every technical claim against the code or docs the brief points at; do not invent behaviour, flags, or paths.
4. Run the repo's docs check if the brief names one.

## Return contract
```json
{"files_changed":["…"],"summary":"what changed and why, two sentences","unverified_claims":["anything you could not confirm"],"style_deviations":["where you had to depart from the supplied style and why"]}
```

## Stop list
- Never change code, only prose and docs files the brief names.
- Never hard-code a project's style guide from memory; use the one in the brief.
- Never leave placeholders (TBD, TODO, lorem) in a page.
```

- [ ] **Step 8: Verify frontmatter parses**

Run: `cd ~/.claude/agents && for f in *.md; do echo "== $f"; sed -n '2,7p' "$f" | grep -E '^(name|model|effort):'; done`
Expected: seven files, each printing `name`, `model`, `effort` matching the roster.

- [ ] **Step 9: Commit**

```bash
cd ~/.claude && git add agents && git commit -q -m "feat: seven dispatch roles with pinned model and effort"
```

---

### Task 3: Warn-only dispatch hook

**Files:**
- Create: `~/.claude/hooks/dispatch-guard.sh`, `~/.claude/hooks/test-dispatch-guard.sh`
- Modify: `~/.claude/settings.json` (add `hooks.PreToolUse`)

**Interfaces:**
- Consumes: role filenames from `~/.claude/agents/*.md` (Task 2).
- Produces: nothing consumed later; behavioural only.

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# ~/.claude/hooks/test-dispatch-guard.sh
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `chmod +x ~/.claude/hooks/test-dispatch-guard.sh && ~/.claude/hooks/test-dispatch-guard.sh`
Expected: FAIL lines (hook script missing).

- [ ] **Step 3: Write the hook**

```bash
#!/usr/bin/env bash
# ~/.claude/hooks/dispatch-guard.sh — PreToolUse(Agent) warn-only role nudge.
# Never blocks: always exit 0. Fails open on any parse error.
set -u
input=$(cat)
type=$(jq -r '.tool_input.subagent_type // empty' <<<"$input" 2>/dev/null) || exit 0
roster_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/agents"
roster=$(ls "$roster_dir"/*.md 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/\.md$//' | tr '\n' ' ')
[[ -z "$roster" ]] && exit 0
for r in $roster; do [[ "$type" == "$r" ]] && exit 0; done
if [[ -z "$type" ]]; then
  msg="Dispatch policy: no subagent_type set, so this agent inherits the session model (Fable). Dispatch by role instead — roster: ${roster}. Use scout for search, implementer for changes, reviewer/skeptic for judgement."
else
  msg="Dispatch policy: '${type}' is not a roster role, so its model/effort are not pinned. Roster: ${roster}. Built-ins are allowed but prefer scout (search), implementer (changes), reviewer/skeptic (judgement)."
fi
jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
exit 0
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `chmod +x ~/.claude/hooks/dispatch-guard.sh && ~/.claude/hooks/test-dispatch-guard.sh`
Expected: four `ok` lines, exit 0.

- [ ] **Step 5: Register the hook**

Run:
```bash
cd ~/.claude && jq '.hooks.PreToolUse = [{"matcher":"Agent","hooks":[{"type":"command","command":"$HOME/.claude/hooks/dispatch-guard.sh","timeout":10}]}]' settings.json > settings.json.tmp && mv settings.json.tmp settings.json && jq '.hooks' settings.json
```
Expected: the PreToolUse array printed.

- [ ] **Step 6: Commit**

```bash
cd ~/.claude && git add hooks settings.json && git commit -q -m "feat: warn-only PreToolUse dispatch guard with tests"
```

---

### Task 4: Global CLAUDE.md dispatch rules

**Files:**
- Create: `~/.claude/CLAUDE.md`

- [ ] **Step 1: Write the file**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
cd ~/.claude && git add CLAUDE.md && git commit -q -m "feat: global dispatch rules"
```

---

### Task 5: Saved workflows

**Files:**
- Create: `~/.claude/workflows/review-branch.js`, `research-sweep.js`, `verify-findings.js`

**Interfaces:**
- Consumes: roles from Task 2 via `agentType`.
- Produces: `/review-branch`, `/research-sweep`, `/verify-findings` commands. `verify-findings` accepts `args: {findings:[{file,line,claim}]}` and returns `{confirmed,refuted,uncertain}`; `review-branch` returns the same three lists plus `dimensions_run`.

- [ ] **Step 1: Write `verify-findings.js`**

```javascript
export const meta = {
  name: 'verify-findings',
  description: 'Run one skeptic per finding and sort them into confirmed / refuted / uncertain',
  whenToUse: 'You have a list of {file,line,claim} findings and want each adversarially checked before acting',
  phases: [{ title: 'Verify', detail: 'one skeptic per finding' }],
}

const VERDICT = {
  type: 'object',
  required: ['claim', 'refuted', 'confidence', 'reasoning'],
  properties: {
    claim: { type: 'string' },
    refuted: { type: 'boolean' },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
    reasoning: { type: 'string' },
    evidence: { type: 'array', items: { type: 'string' } },
  },
}

const findings = Array.isArray(args?.findings) ? args.findings : Array.isArray(args) ? args : []
if (!findings.length) return { confirmed: [], refuted: [], uncertain: [], note: 'no findings supplied' }

phase('Verify')
const results = await pipeline(findings, (f, _, i) =>
  agent(
    `Claim to test: ${f.claim}\nLocation: ${f.file}${f.line ? ':' + f.line : ''}\n` +
      `Try to refute this claim with evidence from the code. Return the verdict shape.`,
    { agentType: 'skeptic', label: `skeptic:${f.file}`, phase: 'Verify', schema: VERDICT },
  ).then(v => ({ ...f, verdict: v })),
)

const sorted = { confirmed: [], refuted: [], uncertain: [] }
for (const r of results.filter(Boolean)) {
  const v = r.verdict
  if (!v) sorted.uncertain.push(r)
  else if (v.refuted && v.confidence !== 'low') sorted.refuted.push(r)
  else if (!v.refuted && v.confidence !== 'low') sorted.confirmed.push(r)
  else sorted.uncertain.push(r)
}
log(`confirmed ${sorted.confirmed.length} · refuted ${sorted.refuted.length} · uncertain ${sorted.uncertain.length}`)
return sorted
```

- [ ] **Step 2: Write `review-branch.js`**

```javascript
export const meta = {
  name: 'review-branch',
  description: 'Review the current branch against a base across four dimensions, then skeptic-check every finding',
  whenToUse: 'A branch is ready for review; you want per-dimension reviewers whose findings are adversarially verified before you read them',
  phases: [
    { title: 'Review', detail: 'one reviewer per dimension' },
    { title: 'Verify', detail: 'one skeptic per deduped finding' },
  ],
}

const base = (args && args.base) || 'dev'

const FINDINGS = {
  type: 'object',
  required: ['verdict', 'findings'],
  properties: {
    verdict: { type: 'string', enum: ['approve', 'request_changes'] },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['file', 'line', 'severity', 'claim', 'evidence'],
        properties: {
          file: { type: 'string' }, line: { type: 'integer' },
          severity: { type: 'string', enum: ['critical', 'important', 'minor'] },
          claim: { type: 'string' }, evidence: { type: 'string' },
        },
      },
    },
    notes: { type: 'array', items: { type: 'string' } },
  },
}
const VERDICT = {
  type: 'object',
  required: ['claim', 'refuted', 'confidence', 'reasoning'],
  properties: {
    claim: { type: 'string' }, refuted: { type: 'boolean' },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
    reasoning: { type: 'string' }, evidence: { type: 'array', items: { type: 'string' } },
  },
}

const DIMENSIONS = [
  { key: 'correctness', prompt: 'wrong behaviour, missed edge cases, broken invariants, race conditions' },
  { key: 'security', prompt: 'input validation, auth on new routes, SQL parameterisation, secrets in code, SSRF, destructive paths' },
  { key: 'tests', prompt: 'missing or weak tests, tests that assert implementation rather than behaviour, untested risky paths' },
  { key: 'simplification', prompt: 'duplication, dead code, needless abstraction, naming a maintainer would trip over' },
]

phase('Review')
const reviews = await parallel(DIMENSIONS.map(d => () =>
  agent(
    `Review the diff \`git diff ${base}...HEAD\` (run it yourself; also read \`git log ${base}..HEAD --oneline\`).\n` +
      `Dimension: ${d.key} — look only for: ${d.prompt}.\n` +
      `Quote evidence for every finding. Return the findings shape.`,
    { agentType: 'reviewer', label: `review:${d.key}`, phase: 'Review', schema: FINDINGS },
  ).then(r => r && { ...r, dimension: d.key }),
))

// barrier is deliberate: dedup across dimensions before paying for skeptics
const seen = new Set()
const all = []
for (const r of reviews.filter(Boolean)) {
  for (const f of r.findings || []) {
    const k = `${f.file}:${f.line}:${f.claim.slice(0, 40).toLowerCase()}`
    if (seen.has(k)) continue
    seen.add(k)
    all.push({ ...f, dimension: r.dimension })
  }
}
log(`${all.length} unique findings across ${reviews.filter(Boolean).length} dimensions`)
if (!all.length) return { confirmed: [], refuted: [], uncertain: [], dimensions_run: DIMENSIONS.map(d => d.key) }

phase('Verify')
const verified = await pipeline(all, f =>
  agent(
    `Claim to test: ${f.claim}\nLocation: ${f.file}:${f.line}\nEvidence offered: ${f.evidence}\n` +
      `The diff under review is \`git diff ${base}...HEAD\`. Try to refute this claim. Return the verdict shape.`,
    { agentType: 'skeptic', label: `skeptic:${f.file}:${f.line}`, phase: 'Verify', schema: VERDICT },
  ).then(v => ({ ...f, verdict: v })),
)

const out = { confirmed: [], refuted: [], uncertain: [], dimensions_run: DIMENSIONS.map(d => d.key) }
for (const r of verified.filter(Boolean)) {
  const v = r.verdict
  if (!v) out.uncertain.push(r)
  else if (v.refuted && v.confidence !== 'low') out.refuted.push(r)
  else if (!v.refuted && v.confidence !== 'low') out.confirmed.push(r)
  else out.uncertain.push(r)
}
const sev = { critical: 0, important: 1, minor: 2 }
out.confirmed.sort((a, b) => sev[a.severity] - sev[b.severity])
log(`confirmed ${out.confirmed.length} · refuted ${out.refuted.length} · uncertain ${out.uncertain.length}`)
return out
```

- [ ] **Step 3: Write `research-sweep.js`**

```javascript
export const meta = {
  name: 'research-sweep',
  description: 'Answer a codebase question by sweeping from several angles, deep-reading the survivors, and synthesising one structured map',
  whenToUse: 'A "how does X work / where does Y live / what touches Z" question that one grep angle will not answer',
  phases: [
    { title: 'Sweep', detail: 'one scout per angle' },
    { title: 'Read', detail: 'deep-read each unique location' },
    { title: 'Synthesise', detail: 'one structured map' },
  ],
}

const question = typeof args === 'string' ? args : args?.question
if (!question) return { error: 'pass a question: args = {question, angles?}' }
const angles = (args && args.angles) || [
  'by file and directory names that suggest the topic',
  'by identifiers, function names and types in the code',
  'by call sites, routes, and entry points that reach the topic',
  'by tests, docs and comments that describe the topic',
]

const MATCHES = {
  type: 'object', required: ['matches'],
  properties: {
    matches: { type: 'array', items: { type: 'object', required: ['path', 'why'], properties: { path: { type: 'string' }, line: { type: 'integer' }, why: { type: 'string' } } } },
    notes: { type: 'array', items: { type: 'string' } },
  },
}
const READ = {
  type: 'object', required: ['path', 'summary', 'relevant'],
  properties: { path: { type: 'string' }, summary: { type: 'string' }, relevant: { type: 'boolean' }, key_lines: { type: 'array', items: { type: 'string' } } },
}
const MAP = {
  type: 'object', required: ['answer', 'locations', 'open_questions'],
  properties: {
    answer: { type: 'string' },
    locations: { type: 'array', items: { type: 'object', required: ['path', 'role'], properties: { path: { type: 'string' }, role: { type: 'string' } } } },
    open_questions: { type: 'array', items: { type: 'string' } },
  },
}

phase('Sweep')
const sweeps = await parallel(angles.map((a, i) => () =>
  agent(`Question: ${question}\nSearch angle: ${a}.\nReturn up to 12 matches with one-line reasons.`,
    { agentType: 'scout', label: `scout:${i + 1}`, phase: 'Sweep', schema: MATCHES }),
))
const byPath = new Map()
for (const s of sweeps.filter(Boolean)) for (const m of s.matches || []) if (!byPath.has(m.path)) byPath.set(m.path, m)
const unique = [...byPath.values()].slice(0, 20)
log(`${unique.length} unique locations from ${angles.length} angles${byPath.size > 20 ? ` (capped from ${byPath.size})` : ''}`)

phase('Read')
const reads = await pipeline(unique, m =>
  agent(`Question: ${question}\nRead ${m.path} in full (it was flagged because: ${m.why}). Do not edit anything.\nSummarise what it contributes to the question and whether it is actually relevant.`,
    { agentType: 'implementer', label: `read:${m.path}`, phase: 'Read', schema: READ }),
)
const relevant = reads.filter(Boolean).filter(r => r.relevant)

phase('Synthesise')
const map = await agent(
  `Question: ${question}\nHere are per-file summaries from a read pass:\n${JSON.stringify(relevant, null, 2)}\n` +
    `Produce one structured answer: the answer in plain prose, the locations with each file's role, and open questions you could not settle from these summaries.`,
  { agentType: 'reviewer', label: 'synthesise', phase: 'Synthesise', schema: MAP },
)
return map
```

- [ ] **Step 4: Syntax-check all three**

Run: `cd ~/.claude/workflows && for f in *.js; do sed 's/^export const meta/const meta/; 1i (async()=>{' "$f" | sed '$a })' | node --check - 2>&1 | sed "s|^|$f: |"; done; echo done`
Expected: only `done` (no syntax errors). The wrapper makes top-level `await`/`return` legal for `node --check`.

- [ ] **Step 5: Commit**

```bash
cd ~/.claude && git add workflows && git commit -q -m "feat: review-branch, research-sweep, verify-findings workflows"
```

---

### Task 6: Acceptance

**Files:** none created.

- [ ] **Step 1: Restart-sensitive check** — the `agents/` dir did not exist at session start, so roles load only after a restart. Record this in the handoff; the run below may need to happen in a fresh session.

- [ ] **Step 2: Hook fires** — from a session, dispatch `Agent` with no `subagent_type` on a trivial prompt and confirm the dispatch-policy nudge appears in the tool result context.

- [ ] **Step 3: Roles honour contracts** — dispatch `scout` ("list files under `packages/schemas/src` that export a Zod schema; return the default shape") and `skeptic` (one made-up claim about a real file). Confirm JSON returns and no edits (`git status --short` clean).

- [ ] **Step 4: Workflow acceptance** — in the Mastermind repo on `feature/desktop-closed-beta`, run `/review-branch` with `args: {base: "dev"}`. Confirm phases Review → Verify appear in `/workflows`, and the result has the four lists.

- [ ] **Step 5: Effort** — after restart, confirm the status line / `/model` shows Fable at medium.

- [ ] **Step 6: Record results** in `~/.claude/specs/2026-08-25-subagent-dispatch-policy-design.md` under a new `## 10. Acceptance log` heading (date, what ran, what failed), and commit.
