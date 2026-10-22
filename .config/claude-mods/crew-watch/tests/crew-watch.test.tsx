import { expect, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'

import type { On } from 'claude-code'

import type { CrewMember, CrewReport, QuotaFigure, QuotaReading } from '../types'
import { dashboardLayout } from '../hooks/dashboard'
import { PALETTES } from '../hooks/theme'
import { accountFromLimits } from '../hooks/account'
import { callTokensText, estimateText, quotaRows, toolTokenNote, toolTokenText } from '../hooks/format'

const NOW = 1_800_000_000_000

const KEY = 'claude|andang|seven_day'

const figure = (over: Partial<QuotaFigure> = {}): QuotaFigure => ({ share: 0.2, percent: 7.4, settled: 7, open: 0.4, since: null, basis: 'estimated', ...over })

const reading = (over: Partial<QuotaReading> = {}): QuotaReading => ({
  provider: 'claude', account: 'andang', accountKnown: true, scope: 'seven_day', plan: 'Max 5x', login: 'token', percent: 37,
  observedAt: NOW - 120_000, source: 'session', resetsAt: NOW + 86_400_000, windowMs: 7 * 86_400_000, windowStart: NOW - 5 * 86_400_000,
  windowStartKnown: true, stale: false, reset: false, indexed: true, localCost: 1e6, sinceCost: 20_000, forecast: 38.4,
  confidence: { label: 'uncalibrated', samples: 0 }, ...over,
})

const member = (over: Partial<CrewMember>): CrewMember => ({
  id: 'fix-login',
  home: '/fm',
  depth: 0,
  kind: 'ship',
  harness: 'claude',
  model: 'sonnet',
  effort: 'medium',
  project: 'webapp',
  branch: 'fm/fix-login',
  description: 'Fix login validation',
  worktree: '/repo/login',
  status: 'pr: https://example.test/pr/1',
  statusAt: NOW - 60_000,
  readable: true,
  sessions: 1,
  models: { 'claude-sonnet-5-5': 12 },
  requests: 12,
  input: 120,
  output: 15_400,
  cacheRead: 1_900_000,
  cacheWrite: 98_000,
  reasoning: 4_000,
  context: 88_000,
  contextWindow: 200_000,
  contextModel: 'claude-opus-5-5',
  windowSource: 'transcript',
  events: [{ at: NOW - 30_000, kind: 'tool', text: 'Bash: npm test' }, { at: NOW - 60_000, kind: 'status', text: 'working' }],
  recentTools: [{ at: NOW - 30_000, kind: 'tool', text: 'Bash: npm test', tool: 'Bash', outTokens: 640, inTokens: 2_300, estimated: false }],
  activity: [{ minute: Math.floor(NOW / 60_000), count: 2 }],
  tools: { Bash: 20, Edit: 8, Read: 3 },
  toolCalls: 31,
  toolTokens: {
    Bash: { calls: 20, output: 12_000, input: 30_000, estimated: 0, estCalls: 0 },
    Edit: { calls: 8, output: 3_000, input: 1_600, estimated: 400, estCalls: 1 },
  },
  quota: {
    [KEY]: { session: figure(), tools: figure({ share: 0.08, percent: 2.96, settled: 2.9, open: 0.06 }) },
  },
  topTools: [
    { name: 'Bash', count: 20 },
    { name: 'Edit', count: 8 },
  ],
  lastTool: 'Bash: npm test',
  lastText: 'Tests pass; opening the PR.',
  lastAt: NOW - 30_000,
  ...over,
})

const REPORT: CrewReport = {
  generatedAt: NOW,
  crew: [
    member({}),
    member({ id: 'pi-task', harness: 'pi', readable: false, sessions: 0, requests: 0, models: {}, lastTool: '', lastText: '', status: '', lastAt: 0, statusAt: 0 }),
  ],
  totals: { requests: 12, input: 120, output: 15_400, cacheRead: 1_900_000, cacheWrite: 98_000, reasoning: 4_000, toolCalls: 31 },
  quota: {
    readings: { [KEY]: reading() },
    fleet: { [KEY]: { session: figure(), tools: figure({ share: 0.08, percent: 2.96, settled: 2.9, open: 0.06 }) } },
  },
  errors: [],
}

const PANE = {
  plugin: 'crew-watch',
  component: 'Pane',
  requestId: 'crew-watch',
  props: {
    title: 'Crew',
    isFocused: false,
    bodyColumns: 90,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
} as const

test('the pane shows each crewmate\'s models, tokens, cache and tools, on every surface', async ($, on) => {
  let argv: readonly string[] = []
  on('command.register', () => ({ value: { command: 'crew' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.root', () => ({ value: '/fm' }))
  on('session.id', () => ({ value: 'pane-session' }))
  on('clock.every', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('env.get', (_, e) => ({ value: e.name === 'CLAUDE_CODE_OAUTH_TOKEN' ? 'fabricated-not-a-token' : undefined }))
  on('process.run', (_, e) => {
    argv = e.argv
    return { value: { exitCode: 0, stdout: JSON.stringify(REPORT), stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })

  await $.session.start({ cwd: '/fm', surface: 'desktop', isInteractive: true })
  const ran = await $.command.run({ command: 'crew', args: 'refresh', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 160 } })
  expect(ran.text).toBe('Crew refreshed: 2 live crewmate(s).')
  expect(argv.slice(-2)).toEqual(['--home', '/fm'])
  expect(argv[argv.indexOf('--claude-session') + 1]).toBe('pane-session')
  // The script cannot see the token variable, so the mod says whether one signs this session in (presence only).
  expect(argv[argv.indexOf('--claude-login') + 1]).toBe('token')

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ type: 'Text', text: /2 live/ }))?.text).toContain('CREW')
    expect(await ui.find({ text: /31 tool calls/ })).toBeDefined()
    expect(await ui.find({ text: /sonnet-5-5 ×12/ })).toBeDefined()
    expect(await ui.find({ text: /88k\/200k/ })).toBeDefined()
    expect((await ui.find({ type: 'Text', text: /cache ▰/ }))?.text).toContain('95%')
    expect(await ui.find({ text: /tools 31 · 47k tok/ })).toBeDefined()
    expect(await ui.find({ text: /Bash ▰.* 20 42k/ })).toBeDefined()
    expect(await ui.find({ text: 'claude andang · Max 5x' })).toBeDefined()
    expect(await ui.find({ text: 'week 37% measured 2m ago' })).toBeDefined()
    expect(await ui.find({ text: 'source this session' })).toBeDefined()
    expect(await ui.find({ text: 'session ~7% of week est' })).toBeDefined()
    expect(await ui.find({ text: 'tools direct ~3% of week est' })).toBeDefined()
    expect(await ui.find({ text: 'uncalibrated · 0 samples' })).toBeDefined()
    expect(await ui.find({ text: 'account now est ~38%' })).toBeDefined()
    expect(await ui.find({ text: /neither exact nor an upper bound/ })).toBeDefined()
    expect(await ui.find({ text: /later cache re-reads count to the session only/ })).toBeDefined()
    expect(await ui.find({ text: /Other machines, the web and sessions that never ran this mod/ })).toBeDefined()
    expect(await ui.find({ text: /Bash ▰/ })).toBeDefined()
    expect((await ui.find({ type: 'Text', text: /npm test/ }))?.text).toContain('▸')
    expect((await ui.find({ type: 'Text', text: /not readable for the pi harness/ }))).toBeTruthy()
    await ui.unmount()
  }
})

test('a failed read shows the reason in the pane', async ($, on) => {
  on('command.register', () => ({ value: { command: 'crew' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.root', () => ({ value: '/fm' }))
  on('session.id', () => ({ value: 'pane-session' }))
  on('clock.every', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('env.get', () => ({ value: undefined }))
  on('process.run', () => ({ value: { exitCode: 1, stdout: '', stderr: 'Traceback\nValueError: boom', isStdoutTruncated: false, isStderrTruncated: false } }))

  await $.session.start({ cwd: '/fm', surface: 'desktop', isInteractive: true })
  await $.command.run({ command: 'crew', args: 'refresh', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 160 } })

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /boom/ }))?.text).toBe('crew_usage.py failed: ValueError: boom')
  await ui.unmount()
})

// drawn() validates the returned tree against the surface table and rejects a refusal.
// 96 mounts: past the default 5 s on a loaded machine, so it has its own bound.
test('dashboard matrix draws every fleet size, width, placement and surface', { timeoutMs: 60_000 }, async ($, on) => {
  let current = REPORT
  on('command.register', () => ({ value: { command: 'crew' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.root', () => ({ value: '/fm' }))
  on('session.id', () => ({ value: 'pane-session' }))
  on('clock.every', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('env.get', () => ({ value: undefined }))
  on('process.run', () => ({ value: { exitCode: 0, stdout: JSON.stringify(current), stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  await $.session.start({ cwd: '/fm', surface: 'desktop', isInteractive: true })
  for (const size of [0, 1, 3, 8]) {
    current = { ...REPORT, crew: Array.from({ length: size }, (_, i) => member({ id: `crew-${i}`, depth: i === 1 ? 1 : 0, harness: i % 2 ? 'codex' : 'claude' })) }
    await $.command.run({ command: 'crew', args: 'refresh', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 160 } })
    for (const surface of ['terminal', 'desktop'] as const) {
      for (const columns of [40, 80, 120]) {
        for (const placement of ['dock', 'inline'] as const) {
          const ui = await $.ui.mount({ ...PANE, surface, props: { ...PANE.props, isFocused: true, bodyColumns: columns, placement } })
          const tree = await ui.drawn() as { type: string; children?: unknown[] }
          expect(tree.type).toBe('Box')
          expect(await ui.find({ text: new RegExp(`CREW · ${size} live`) })).toBeDefined()
          if (placement === 'inline') {
            expect((tree.children ?? []).filter(Boolean).length <= 8).toBe(true)
            expect(await ui.find({ text: 'CREW LOG' })).toBeUndefined()
          } else {
            expect(await ui.find({ text: 'FLEET' })).toBeDefined()
            expect(await ui.find({ text: 'CREW LOG' })).toBeDefined()
            if (size > 0) {
              expect((await ui.find({ key: 'lane-axis-gutter' }))?.props.width).toBe(19)
              expect((await ui.find({ key: 'lane-gap-/fm:crew-0' }))?.props.width).toBe(1)
              expect(await ui.find({ type: 'Text', text: /^-\d+m\s+now$/ })).toBeDefined()
              await ui.press({ key: 'card-/fm:crew-0' })
              expect(await ui.find({ text: /Fix login validation/ })).toBeDefined()
              expect(await ui.find({ text: /branch fm\/fix-login/ })).toBeDefined()
              expect(await ui.find({ text: /Read ×3/ })).toBeDefined()
              await ui.press({ key: 'card-/fm:crew-0' })
            }
          }
          await ui.unmount()
        }
      }
    }
  }
})

test('the ninth hotkey works and a failed refresh keeps the inline summary within eight rows', async ($, on) => {
  let fail = false
  const report = { ...REPORT, crew: Array.from({ length: 9 }, (_, i) => member({ id: `crew-${i}` })) }
  on('command.register', () => ({ value: { command: 'crew' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.root', () => ({ value: '/fm' }))
  on('session.id', () => ({ value: 'pane-session' }))
  on('clock.every', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('env.get', () => ({ value: undefined }))
  on('process.run', () => ({ value: { exitCode: fail ? 1 : 0, stdout: JSON.stringify(report), stderr: fail ? 'read unavailable' : '', isStdoutTruncated: false, isStderrTruncated: false } }))
  const refresh = () => $.command.run({ command: 'crew', args: 'refresh', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 80 } })
  await $.session.start({ cwd: '/fm', surface: 'terminal', isInteractive: true })
  await refresh()
  const dock = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await dock.find({ key: 'card-/fm:crew-8' }))?.props.hotkey).toBe('9')
  await dock.press({ key: 'card-/fm:crew-8' })
  expect(await dock.find({ text: /Fix login validation/ })).toBeDefined()
  await dock.unmount()
  fail = true
  await refresh()
  const mini = await $.ui.mount({ ...PANE, surface: 'terminal', props: { ...PANE.props, placement: 'inline' } })
  const tree = await mini.drawn() as { children?: unknown[] }
  expect((tree.children ?? []).filter(Boolean).length).toBe(8)
  expect(await mini.find({ text: /read unavailable/ })).toBeDefined()
  await mini.unmount()
})

test('the expanded crewmate shows tokens per recent call and per-tool totals', async ($, on) => {
  on('command.register', () => ({ value: { command: 'crew' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.root', () => ({ value: '/fm' }))
  on('session.id', () => ({ value: 'pane-session' }))
  on('clock.every', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('env.get', () => ({ value: undefined }))
  on('process.run', () => ({ value: { exitCode: 0, stdout: JSON.stringify(REPORT), stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  await $.session.start({ cwd: '/fm', surface: 'terminal', isInteractive: true })
  await $.command.run({ command: 'crew', args: 'refresh', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 160 } })
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await ui.press({ key: 'card-/fm:fix-login' })
  expect(await ui.find({ text: /out 640 in 2\.3k · Bash: npm test/ })).toBeDefined()
  expect(await ui.find({ text: /Bash ×20 · 42k tok · avg 2\.1k/ })).toBeDefined()
  expect(await ui.find({ text: /Edit ×8 · 4\.6k tok · avg ~575/ })).toBeDefined()
  expect(await ui.find({ text: /~ estimated from result size/ })).toBeDefined()
  await ui.unmount()
})

test('collapsed cards at 80 to 120 columns show the session and tools-direct shares whole', async ($, on) => {
  on('command.register', () => ({ value: { command: 'crew' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.root', () => ({ value: '/fm' }))
  on('session.id', () => ({ value: 'pane-session' }))
  on('clock.every', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  // Card figures differ from the fleet box's, so a find can only match a card row, and only unclipped.
  const quota = { [KEY]: { session: figure({ share: 0.1, percent: 4.4 }), tools: figure({ share: 0.02, percent: 0.9 }) } }
  let report = REPORT
  on('env.get', () => ({ value: undefined }))
  on('process.run', () => ({ value: { exitCode: 0, stdout: JSON.stringify(report), stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  await $.session.start({ cwd: '/fm', surface: 'terminal', isInteractive: true })
  for (const [columns, size] of [[80, 2], [111, 3], [120, 3]] as const) {
    report = { ...REPORT, crew: Array.from({ length: size }, (_, i) => member({ id: `crew-${i}`, quota })) }
    await $.command.run({ command: 'crew', args: 'refresh', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 160 } })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: { ...PANE.props, bodyColumns: columns } })
    expect(dashboardLayout(columns, 'dock', size).mode).toBe('cards')
    for (const text of ['session ~4% of week est', 'tools direct <1% of week est', 'source this session', 'week 37% measured 2m ago']) {
      expect(await ui.find({ text })).toBeDefined()
    }
    await ui.unmount()
  }
})

test('token and quota text states what is unknown instead of inventing numbers', () => {
  expect(callTokensText({ outTokens: 5, inTokens: 7, estimated: true })).toBe('out 5 in ~7')
  expect(callTokensText({})).toBe('tok n/a')
  expect(toolTokenText(undefined)).toBe('tok n/a')
  expect(toolTokenNote({ toolCalls: 3, toolTokens: {} })).toBe('per-call tokens unavailable: the transcript has no usage fields')
  expect(toolTokenNote({ toolCalls: 0, toolTokens: {} })).toBe('')
  const raw = figure({ share: 0.31, percent: null, settled: null, open: null, basis: 'raw' })
  const rawTools = figure({ share: 0.004, percent: null, settled: null, open: null, basis: 'raw' })
  const share = { session: raw, tools: rawTools }
  const codexKey = 'codex|codex-1a2b3c4d|codex:10080m'
  const codex = reading({ provider: 'codex', account: 'codex-1a2b3c4d', scope: 'codex:10080m', plan: '', login: 'rollout', percent: null, observedAt: null, source: '', reset: true, forecast: null, sinceCost: null })
  // No reading: only the raw share of local usage, and why there is no percent.
  expect(quotaRows({ [codexKey]: share }, { [codexKey]: codex }, NOW).map(r => r.text)).toEqual([
    'codex 1a2b3c4d',
    'session 31% of local',
    'tools direct 0.4% of local',
    'week % unknown: window reset',
  ])
  expect(quotaRows({ [codexKey]: share }, { [codexKey]: { ...codex, reset: false } }, NOW).at(-1)?.text).toBe('week % unknown: no reading')
  expect(quotaRows({ [codexKey]: share }, { [codexKey]: { ...codex, indexed: false } }, NOW).map(r => r.text)).toEqual(['codex 1a2b3c4d', 'indexing local logs…'])
  // An account nobody could be tied to never carries a percent: raw share only, and it says so.
  const unknownKey = 'claude|unknown|seven_day'
  const unknown = reading({ account: 'unknown', accountKnown: false, plan: '', login: 'token', percent: null, observedAt: null, source: '', forecast: null, sinceCost: null })
  expect(quotaRows({ [unknownKey]: share }, { [unknownKey]: unknown }, NOW).map(r => r.text)).toEqual([
    'claude account unknown',
    'session 31% of local',
    'tools direct 0.4% of local',
    'week %: account unknown',
  ])
  // A stale reading keeps its time, is never "measured now" and shows the raw delta, not an extrapolation.
  const old = reading({ plan: 'Max 20x · Team', percent: 10, source: 'history', observedAt: NOW - 4 * 86_400_000, stale: true, forecast: null, sinceCost: 5_000 })
  const settled = { session: figure({ percent: 3.1, settled: 3.1, open: null, since: 120_000, basis: 'settled' }), tools: figure({ percent: 0.04, settled: 0.04, open: null, basis: 'settled' }) }
  expect(quotaRows({ [KEY]: settled }, { [KEY]: old }, NOW)).toEqual([
    { text: 'claude andang · Max 20x · Team', tone: 'subtle' },
    { text: 'week 10% stale 4d ago', tone: 'warning' },
    { text: 'source reading history', tone: 'subtle' },
    { text: 'session ~3% as of reading', tone: 'text' },
    { text: 'tools direct <1% as of reading', tone: 'text' },
    { text: 'session since 120k wtok', tone: 'subtle' },
    { text: 'uncalibrated · 0 samples', tone: 'subtle' },
  ])
  expect(quotaRows({ [KEY]: settled }, { [KEY]: { ...old, observedAt: null } }, NOW)[1]?.text).toBe('week 10% stale, age unknown')
  // Half an hour is the limit: just inside is measured, the account line only appears in the fleet box.
  const fresh = quotaRows({ [KEY]: { session: figure(), tools: figure() } }, { [KEY]: reading({ confidence: { label: 'low', samples: 1 } }) }, NOW, true).map(r => r.text)
  expect(fresh).toContain('account now est ~38%')
  expect(fresh).toContain('local since 20k wtok')
  expect(fresh).toContain('low · 1 sample')
  expect(quotaRows({ [KEY]: { session: figure(), tools: figure() } }, { [KEY]: reading() }, NOW).map(r => r.text)).not.toContain('account now est ~38%')
  // Estimates carry no decimal and never read as exact.
  expect([0, 0.4, 1.4, 99.6, 140].map(estimateText)).toEqual(['0%', '<1%', '~1%', '~100%', '~100%'])
  expect(quotaRows({}, {}, NOW)).toEqual([])
  expect(quotaRows({ missing: share }, {}, NOW)).toEqual([])
  // A collapsed card's narrowest row is 32 cells: no quota row may be cut there.
  const rows = [...quotaRows({ [KEY]: settled }, { [KEY]: old }, NOW), ...quotaRows({ [KEY]: settled }, { [KEY]: { ...old, observedAt: null } }, NOW),
    ...quotaRows({ [KEY]: { session: figure({ percent: 100, settled: 100 }), tools: figure({ percent: 99.9 }) } }, { [KEY]: reading({ confidence: { label: 'calibrated', samples: 12 } }) }, NOW),
    ...quotaRows({ [codexKey]: share }, { [codexKey]: codex }, NOW), ...quotaRows({ [unknownKey]: share }, { [unknownKey]: unknown }, NOW)]
  const long = reading({ account: 'work-personal-account-name-xx', plan: 'Max 20x · Team' })
  rows.push(...quotaRows({ [KEY]: { session: figure(), tools: figure() } }, { [KEY]: long }, NOW))
  expect(rows.filter(r => Array.from(r.text).length > 32)).toEqual([])
  expect(quotaRows({ [KEY]: { session: figure(), tools: figure() } }, { [KEY]: long }, NOW)[0]?.text).toBe('claude work-pe… · Max 20x · Team')
})

const LIMITS_A = JSON.stringify({ fingerprint: 'a'.repeat(64), time: 1, windows: {} })
const LIMITS_B = JSON.stringify({ fingerprint: 'b'.repeat(64), time: 1, windows: {} })

test('the account is found by fingerprint and only its name is handed on', () => {
  const files = [{ name: 'claude-alpha.limits.json', text: LIMITS_A }, { name: 'claude-beta.limits.json', text: LIMITS_B }, { name: 'claude-UPPER.limits.json', text: LIMITS_B }]
  expect(accountFromLimits('b'.repeat(64), files)).toBe('beta')
  expect(accountFromLimits('c'.repeat(64), files)).toBeUndefined()
  expect(accountFromLimits('not-a-fingerprint', files)).toBeUndefined()
  expect(accountFromLimits(undefined, files)).toBeUndefined()
  expect(accountFromLimits('a'.repeat(64), [{ name: 'claude-alpha.limits.json', text: 'not json' }])).toBeUndefined()
  // A name that is not a plain account name, or is the reserved "unknown", is never an account.
  expect(accountFromLimits('b'.repeat(64), [{ name: 'claude-unknown.limits.json', text: LIMITS_B }, { name: 'claude-UPPER.limits.json', text: LIMITS_B }])).toBeUndefined()
})

test('the pane passes its account name to the script, never the fingerprint', async ($, on) => {
  let argv: readonly string[] = []
  const reads: string[] = []
  on('command.register', () => ({ value: { command: 'crew' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.root', () => ({ value: '/fm' }))
  on('session.id', () => ({ value: 'pane-session' }))
  on('clock.every', () => ({ value: undefined }))
  on('clock.now', () => ({ value: NOW }))
  on('ui.status', () => ({ value: undefined }))
  on('env.get', (_, e) => ({ value: ({ AI_ACCT_FINGERPRINT: 'b'.repeat(64), XDG_CACHE_HOME: '/cache' } as Record<string, string>)[e.name] }))
  on('fs.list', () => ({ value: ['claude-alpha.limits.json', 'claude-beta.limits.json'].map(name => ({ name, kind: 'file' as const, size: 1, mtimeMs: 0, isLink: false })) }))
  on('fs.read', (_, e) => {
    reads.push(e.path)
    return { value: e.path.includes('beta') ? LIMITS_B : LIMITS_A }
  })
  on('process.run', (_, e) => {
    argv = e.argv
    return { value: { exitCode: 0, stdout: JSON.stringify(REPORT), stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  await $.session.start({ cwd: '/fm', surface: 'desktop', isInteractive: true })
  await $.command.run({ command: 'crew', args: 'refresh', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 160 } })
  expect(argv[argv.indexOf('--claude-account') + 1]).toBe('beta')
  expect(argv.join(' ')).not.toContain('b'.repeat(64))
  // Only the stored limit files of ai-acct are opened: never a token file.
  expect(reads.every(path => path.startsWith('/cache/ai-acct/claude-') && path.endsWith('.limits.json'))).toBe(true)
})

test('a session without a fingerprint or a matching account passes an empty account', async ($, on) => {
  let argv: readonly string[] = []
  on('command.register', () => ({ value: { command: 'crew' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.root', () => ({ value: '/fm' }))
  on('session.id', () => ({ value: 'pane-session' }))
  on('clock.every', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('env.get', () => ({ value: undefined }))
  on('process.run', (_, e) => {
    argv = e.argv
    return { value: { exitCode: 0, stdout: JSON.stringify(REPORT), stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  await $.session.start({ cwd: '/fm', surface: 'desktop', isInteractive: true })
  await $.command.run({ command: 'crew', args: 'refresh', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 160 } })
  expect(argv[argv.indexOf('--claude-account') + 1]).toBe('')
})

type Drawn = { type?: string; props?: Record<string, unknown>; children?: unknown[] }

/** Every colour prop and a layout signature (text, widths, wrapping) of a drawn tree. */
const inspect = (node: unknown, out: { colors: string[]; layout: string[] } = { colors: [], layout: [] }) => {
  if (typeof node === 'string') {
    out.layout.push(node)
    return out
  }
  const { type, props = {}, children = [] } = (node ?? {}) as Drawn
  for (const key of ['color', 'borderColor']) if (typeof props[key] === 'string') out.colors.push(props[key] as string)
  out.layout.push(`${type}:${['width', 'wrap', 'borderStyle', 'paddingX', 'marginTop'].map(k => String(props[k])).join(',')}`)
  for (const child of children) inspect(child, out)
  return out
}

const drawings = new Map<string, ReturnType<typeof inspect>>()

/** Draws the dock pane on a terminal with the given environment and keeps its colours and layout under `label`. */
const drawThemed = async ($: Engine, on: On, label: string, env: Record<string, string>) => {
  on('env.get', (_, e) => ({ value: env[e.name] }))
  on('command.register', () => ({ value: { command: 'crew' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.root', () => ({ value: '/fm' }))
  on('session.id', () => ({ value: 'pane-session' }))
  on('clock.every', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('process.run', () => ({ value: { exitCode: 0, stdout: JSON.stringify(REPORT), stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  await $.session.start({ cwd: '/fm', surface: 'terminal', isInteractive: true })
  await $.command.run({ command: 'crew', args: 'refresh', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 160 } })
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: { ...PANE.props, bodyColumns: 130 } })
  drawings.set(label, inspect(await ui.drawn()))
  await ui.unmount()
}

test('the default theme draws the engine keys', async ($, on) => {
  await drawThemed($, on, 'default', {})
  const { colors } = drawings.get('default') ?? { colors: [] }
  expect(colors.length > 0).toBe(true)
  expect(colors.filter(color => color.startsWith('#') || color.startsWith('ansi256'))).toEqual([])
  expect(colors).toContain('claude')
  expect(colors).toContain('subtle')
})

test('a palette theme paints hex colours from its palette on a truecolor terminal', { options: { theme: 'nord' } }, async ($, on) => {
  await drawThemed($, on, 'nord', { COLORTERM: 'truecolor' })
  const { colors } = drawings.get('nord') ?? { colors: [] }
  expect(colors.length > 0).toBe(true)
  const palette = new Set<string>(Object.values(PALETTES.nord.colors))
  expect(colors.filter(color => !palette.has(color))).toEqual([])
  expect(colors).toContain(PALETTES.nord.colors.claude)
})

test('without truecolor a palette theme falls back to 256-colour indexes', { options: { theme: 'nord' } }, async ($, on) => {
  await drawThemed($, on, 'nord-256', {})
  const { colors } = drawings.get('nord-256') ?? { colors: [] }
  expect(colors.length > 0).toBe(true)
  expect(colors.filter(color => !/^ansi256\(\d+\)$/.test(color))).toEqual([])
})

test('NO_COLOR draws no colour in a palette theme', { options: { theme: 'dracula' } }, async ($, on) => {
  await drawThemed($, on, 'dracula-none', { COLORTERM: 'truecolor', NO_COLOR: '1' })
  expect(drawings.get('dracula-none')?.colors).toEqual([])
})

test('an unknown theme name draws the default', { options: { theme: 'nope' } }, async ($, on) => {
  await drawThemed($, on, 'unknown', { COLORTERM: 'truecolor' })
  expect(drawings.get('unknown')?.colors).toEqual(drawings.get('default')?.colors)
})

test('a theme changes colours only, never the text or layout', () => {
  const base = drawings.get('default')
  expect(base).toBeDefined()
  for (const label of ['nord', 'nord-256', 'dracula-none', 'unknown']) {
    expect(drawings.get(label)?.layout).toEqual(base?.layout)
  }
})

/** Whether any element in a drawn tree sets a background colour. */
const paintsBackground = (node: unknown): boolean => {
  if (typeof node !== 'object' || node === null) return false
  const { props = {}, children = [] } = node as Drawn
  return 'backgroundColor' in props || children.some(paintsBackground)
}

// The engine fills a docked pane itself and has no transparent colour, so the
// only way to stay clear of that fill is to never paint a background of our own
// (see README, "Pane background"). Any theme, size or placement must keep it so.
for (const theme of ['default', 'nord', 'catppuccin-latte']) {
  test(`the ${theme} theme never sets a background colour in any layout`, { options: { theme } }, async ($, on) => {
    on('env.get', (_, e) => ({ value: e.name === 'COLORTERM' ? 'truecolor' : undefined }))
    on('command.register', () => ({ value: { command: 'crew' } }))
    on('session.start', (_, e) => ({ cwd: e.cwd }))
    on('session.root', () => ({ value: '/fm' }))
    on('session.id', () => ({ value: 'pane-session' }))
    on('clock.every', () => ({ value: undefined }))
    on('ui.status', () => ({ value: undefined }))
    on('process.run', () => ({ value: { exitCode: 0, stdout: JSON.stringify(REPORT), stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
    await $.session.start({ cwd: '/fm', surface: 'terminal', isInteractive: true })
    await $.command.run({ command: 'crew', args: 'refresh', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 160 } })
    for (const placement of ['dock', 'inline'] as const) {
      for (const columns of [40, 130]) {
        const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: { ...PANE.props, bodyColumns: columns, placement } })
        expect(paintsBackground(await ui.drawn())).toBe(false)
        await ui.unmount()
      }
    }
  })
}
