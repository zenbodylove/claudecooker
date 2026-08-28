#!/usr/bin/env bash
# Behavioural tests for workflows/*.js: each workflow's source is loaded the way
# hooks/run-tests.sh loads it (strip `export `, build an AsyncFunction) and then
# *executed* against stubbed agent/parallel/pipeline/phase/log. Covers the
# fan-out cap (chill) versus full fan-out (cook, flow) and checks that the
# agentTypes actually dispatched are the substituted twins. Runnable from any cwd.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

node -e "$(cat <<'JS'
const fs = require('fs'), path = require('path')
const root = process.argv[1]
let fail = 0
const ok  = m => console.log('ok   ' + m)
const bad = m => { console.log('FAIL ' + m); fail = 1 }
const eq  = (label, got, want) =>
  JSON.stringify(got) === JSON.stringify(want)
    ? ok(`${label}: ${JSON.stringify(want)}`)
    : bad(`${label}: got ${JSON.stringify(got)}, expected ${JSON.stringify(want)}`)

const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor
function load(file) {
  const src = fs.readFileSync(path.join(root, 'workflows', file), 'utf8').replace(/^export\s+/gm, '')
  return new AsyncFunction('args', 'agent', 'parallel', 'pipeline', 'phase', 'log', src)
}
// Run a workflow with stubs. `canned(opts, prompt)` supplies each agent's reply.
async function run(file, args, canned) {
  const seen = []
  const agent = async (prompt, opts) => {
    seen.push({ agentType: opts.agentType, phase: opts.phase, label: opts.label })
    return canned(opts, prompt)
  }
  const parallel = fns => Promise.all(fns.map(f => f()))
  const pipeline = (items, f) => Promise.all(items.map((it, i) => f(it, items, i)))
  const result = await load(file)(args, agent, parallel, pipeline, () => {}, () => {})
  return { result, seen, types: p => seen.filter(s => s.phase === p).map(s => s.agentType) }
}
const uniq = a => [...new Set(a)]

// --------------------------------------------------------------------------
// review-branch: findings arrive on one dimension, deduped to 3 (crit/imp/min)
// --------------------------------------------------------------------------
const finding = (sev, i) => ({ file: `src/f${i}.js`, line: i, severity: sev, claim: `claim ${i}`, evidence: 'e' })
const reviewCanned = severities => (opts) => {
  if (opts.phase === 'Review')
    return opts.label === 'review:correctness'
      ? { verdict: 'request_changes', findings: severities.map((s, i) => finding(s, i + 1)) }
      : { verdict: 'approve', findings: [] }
  if (opts.phase === 'Verify')
    return { claim: 'c', refuted: false, confidence: 'high', reasoning: 'r' }
  throw new Error('unexpected phase ' + opts.phase)
}
const mixed = ['critical', 'important', 'minor']

async function reviewCase(label, args, expect) {
  const { result, seen, types } = await run('review-branch.js', args, reviewCanned(expect.severities || mixed))
  const skeptics = seen.filter(s => s.phase === 'Verify')
  eq(`review-branch ${label}: skeptic dispatches`, skeptics.length, expect.skeptics)
  eq(`review-branch ${label}: unverified count`, (result.unverified || []).length, expect.unverified)
  eq(`review-branch ${label}: result.mode`, result.mode, expect.mode)
  eq(`review-branch ${label}: review agentTypes`, uniq(types('Review')), [expect.reviewer])
  eq(`review-branch ${label}: verify agentTypes`, uniq(types('Verify')), expect.skeptics ? [expect.skeptic] : [])
  for (const k of ['confirmed', 'refuted', 'uncertain', 'dimensions_run'])
    if (!Array.isArray(result[k])) bad(`review-branch ${label}: result.${k} is not an array`)
  eq(`review-branch ${label}: confirmed count`, result.confirmed.length, expect.skeptics)
  if (expect.unverifiedSeverities)
    eq(`review-branch ${label}: unverified severities`,
      (result.unverified || []).map(f => f.severity), expect.unverifiedSeverities)
}

async function sweepCase(label, args, expect) {
  const canned = (opts) => {
    if (opts.phase === 'Sweep')
      return opts.label === 'scout:1'
        ? { matches: Array.from({ length: 6 }, (_, i) => ({ path: `src/p${i + 1}.js`, line: 1, why: 'w' })) }
        : { matches: [] }
    if (opts.phase === 'Read') return { path: 'x', summary: 's', relevant: true }
    if (opts.phase === 'Synthesise') return { answer: 'a', locations: [], open_questions: [] }
    throw new Error('unexpected phase ' + opts.phase)
  }
  const { result, types } = await run('research-sweep.js', args, canned)
  eq(`research-sweep ${label}: read dispatches`, types('Read').length, expect.reads)
  eq(`research-sweep ${label}: result.skipped`, result.skipped, expect.skipped)
  eq(`research-sweep ${label}: read agentTypes`, uniq(types('Read')), [expect.reader])
  eq(`research-sweep ${label}: synthesis agentTypes`, types('Synthesise'), [expect.synth])
  eq(`research-sweep ${label}: answer preserved`, result.answer, 'a')
}

;(async () => {
  await reviewCase('chill', { base: 'dev', mode: 'chill' },
    { skeptics: 2, unverified: 1, mode: 'chill', reviewer: 'reviewer-sonnet', skeptic: 'skeptic-sonnet',
      unverifiedSeverities: ['minor'] })
  await reviewCase('cook (default)', { base: 'dev' },
    { skeptics: 3, unverified: 0, mode: 'cook', reviewer: 'reviewer', skeptic: 'skeptic' })
  await reviewCase('flow', { base: 'dev', mode: 'flow' },
    { skeptics: 3, unverified: 0, mode: 'flow', reviewer: 'reviewer-medium', skeptic: 'skeptic-sonnet' })
  await reviewCase('chill, all minor', { mode: 'chill' },
    { severities: ['minor', 'minor', 'minor'], skeptics: 0, unverified: 3, mode: 'chill',
      reviewer: 'reviewer-sonnet', skeptic: 'skeptic-sonnet', unverifiedSeverities: ['minor', 'minor', 'minor'] })

  // no findings at all: every return path must carry the same shape
  {
    const { result } = await run('review-branch.js', { mode: 'chill' }, reviewCanned([]))
    eq('review-branch chill, no findings: unverified', result.unverified, [])
    eq('review-branch chill, no findings: mode', result.mode, 'chill')
    eq('review-branch chill, no findings: confirmed', result.confirmed, [])
  }

  await sweepCase('chill', { question: 'q', mode: 'chill' },
    { reads: 4, skipped: 2, reader: 'implementer-medium', synth: 'reviewer-sonnet' })
  await sweepCase('cook (default)', { question: 'q' },
    { reads: 6, skipped: 0, reader: 'implementer', synth: 'reviewer' })
  await sweepCase('flow', { question: 'q', mode: 'flow' },
    { reads: 6, skipped: 0, reader: 'implementer-medium', synth: 'reviewer-medium' })

  process.exit(fail)
})().catch(e => { console.log('FAIL harness threw: ' + (e && e.stack || e)); process.exit(1) })
JS
)" "$ROOT" || exit 1
