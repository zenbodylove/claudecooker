export const meta = {
  name: 'verify-findings',
  description: 'Run one skeptic per finding and sort them into confirmed / refuted / uncertain',
  whenToUse: 'You have a list of {file,line,claim} findings and want each adversarially checked before acting',
  phases: [{ title: 'Verify', detail: 'one skeptic per finding' }],
}

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
const role = r => (SUBS[mode] && SUBS[mode].roles && SUBS[mode].roles[r]) || r

// canonical: schemas/skeptic-verdict.json — keep in sync (hooks/test-schemas.sh)
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
    { agentType: role('skeptic'), label: `skeptic:${f.file}`, phase: 'Verify', schema: VERDICT },
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
