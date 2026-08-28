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
const fanout = (SUBS[mode] && SUBS[mode].fanout) || 'full'

// canonical: schemas/scout-matches.json — keep in sync (hooks/test-schemas.sh)
const MATCHES = {
  type: 'object', required: ['matches'],
  properties: {
    matches: { type: 'array', items: { type: 'object', required: ['path', 'why'], properties: { path: { type: 'string' }, line: { type: 'integer' }, why: { type: 'string' } } } },
    notes: { type: 'array', items: { type: 'string' } },
  },
}

// canonical: schemas/research-read.json — keep in sync (hooks/test-schemas.sh)
const READ = {
  type: 'object', required: ['path', 'summary', 'relevant'],
  properties: { path: { type: 'string' }, summary: { type: 'string' }, relevant: { type: 'boolean' }, key_lines: { type: 'array', items: { type: 'string' } } },
}

// canonical: schemas/research-map.json — keep in sync (hooks/test-schemas.sh)
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
    { agentType: role('scout'), label: `scout:${i + 1}`, phase: 'Sweep', schema: MATCHES }),
))
const byPath = new Map()
for (const s of sweeps.filter(Boolean)) for (const m of s.matches || []) if (!byPath.has(m.path)) byPath.set(m.path, m)
const unique = [...byPath.values()].slice(0, 20)
log(`${unique.length} unique locations from ${angles.length} angles${byPath.size > 20 ? ` (capped from ${byPath.size})` : ''}`)

phase('Read')
const reads = await pipeline(unique, m =>
  agent(`Question: ${question}\nRead ${m.path} in full (it was flagged because: ${m.why}). Do not edit anything.\nSummarise what it contributes to the question and whether it is actually relevant.`,
    { agentType: role('implementer'), label: `read:${m.path}`, phase: 'Read', schema: READ }),
)
const relevant = reads.filter(Boolean).filter(r => r.relevant)

phase('Synthesise')
const map = await agent(
  `Question: ${question}\nHere are per-file summaries from a read pass:\n${JSON.stringify(relevant, null, 2)}\n` +
    `Produce one structured answer: the answer in plain prose, the locations with each file's role, and open questions you could not settle from these summaries.`,
  { agentType: role('reviewer'), label: 'synthesise', phase: 'Synthesise', schema: MAP },
)
return map
