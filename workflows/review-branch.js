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
