import { expect, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'

import type { On } from 'claude-code'

import type { CrewMember, CrewReport, QuotaFigure, QuotaReading } from '../types'
import { PALETTES } from '../hooks/theme'
import { accountFromLimits } from '../hooks/account'
import { callTokensText, cells, estimateText, quotaRows, toolTokenNote, toolTokenText } from '../hooks/format'

const NOW = 1_800_000_000_000

const KEY = 'claude|andang|seven_day'
const OTHER = 'claude|thanhnv|seven_day'
const CODEX = 'codex|codex-60305a97|codex:10080m'

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
    member({ id: 'pi-task', harness: 'pi', readable: false, sessions: 0, requests: 0, models: {}, lastTool: '', lastText: '', status: '', lastAt: 0, statusAt: 0, quota: {}, activity: [], events: [] }),
  ],
  totals: { requests: 12, input: 120, output: 15_400, cacheRead: 1_900_000, cacheWrite: 98_000, reasoning: 4_000, toolCalls: 31 },
  quota: {
    readings: { [KEY]: reading() },
    fleet: { [KEY]: { session: figure(), tools: figure({ share: 0.08, percent: 2.96, settled: 2.9, open: 0.06 }) } },
  },
  errors: [],
}

/** The handoff's reference: a Claude and a Codex crewmate, two Claude accounts and one Codex account. */
const REFERENCE: CrewReport = {
  generatedAt: NOW,
  crew: [
    member({
      id: 'crew-watch-transparent', project: 'dotfiles', model: 'sonnet', effort: 'high', status: '', lastAt: NOW - 20_000,
      context: 109_000, contextWindow: 1_000_000, requests: 19, toolCalls: 22, input: 38_000, output: 7_300,
      events: [
        { at: NOW - 40_000, kind: 'tool', text: 'Bash: W=.; O=/home/anhtran/.local/share/firstmate/data/crew-watch-ui-redesign/live/report.json; python3 -I scripts/crew_usage.py --home /home…' },
        { at: NOW - 20_000, kind: 'tool', text: 'Read: hooks/zones.tsx' },
      ],
    }),
    member({
      id: 'workflow-cryptography-advisory', harness: 'codex', project: 'workflow', model: 'gpt-6.1-sol', effort: 'medium', status: 'working [at=1]: lockfile',
      lastAt: NOW - 4_000, context: 44_000, contextWindow: 828_000, contextModel: 'gpt-6.1-sol', requests: 8, toolCalls: 8, input: 37_000, output: 1_800,
      models: { 'gpt-6.1-sol': 8 }, quota: { [CODEX]: { session: figure({ share: 1, percent: 0.4, settled: 0.4, open: 0 }), tools: figure({ share: 0.5, percent: 0.2, settled: 0.2, open: 0 }) } },
      events: [
        { at: NOW - 8_000, kind: 'tool', text: 'exec: uv lock --upgrade-package cryptography' },
        { at: NOW - 4_000, kind: 'tool', text: 'exec: uv lock --upgrade-package cryptogr…' },
      ],
    }),
  ],
  totals: { requests: 27, input: 75_000, output: 9_100, cacheRead: 1_930_000, cacheWrite: 85_000, reasoning: 2_700, toolCalls: 30 },
  quota: {
    readings: {
      [KEY]: reading({ percent: 32 }),
      [OTHER]: reading({ account: 'thanhnv', percent: null, observedAt: null, source: '', plan: '', login: '', forecast: null, sinceCost: null }),
      [CODEX]: reading({ provider: 'codex', account: 'codex-60305a97', scope: 'codex:10080m', plan: 'Plus', login: 'rollout', percent: 29, source: 'codex log', observedAt: NOW - 4_000 }),
    },
    fleet: {
      [KEY]: { session: figure({ share: 0.3, percent: 0.3, settled: 0.3, open: 0 }), tools: figure({ share: 0.01, percent: 0.04, settled: 0.04, open: 0 }) },
      [CODEX]: { session: figure({ share: 1, percent: 0.4, settled: 0.4, open: 0 }), tools: figure({ share: 0.5, percent: 0.2, settled: 0.2, open: 0 }) },
    },
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

/** A pane body of `columns` x `rows` cells. */
const sized = (columns: number, rows: number, over: Record<string, unknown> = {}) =>
  ({ ...PANE, surface: 'terminal' as const, props: { ...PANE.props, bodyColumns: columns, scroll: { offset: 0, bodyRows: rows }, ...over } })

type World = { report: CrewReport; fail: string; now: number; env: Record<string, string>; argv: readonly string[] }

/** Answers every engine call the mod makes from a mutable world the test steers. */
const stub = (on: On, world: Partial<World> = {}): World => {
  const w: World = { report: REPORT, fail: '', now: NOW + 4_000, env: {}, argv: [], ...world }
  on('command.register', () => ({ value: { command: 'crew' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.root', () => ({ value: '/fm' }))
  on('session.id', () => ({ value: 'pane-session' }))
  on('clock.every', () => ({ value: undefined }))
  on('clock.now', () => ({ value: w.now }))
  on('ui.status', () => ({ value: undefined }))
  on('env.get', (_, e) => ({ value: w.env[e.name] }))
  on('process.run', (_, e) => {
    w.argv = e.argv
    return { value: { exitCode: w.fail ? 1 : 0, stdout: w.fail ? '' : JSON.stringify(w.report), stderr: w.fail, isStdoutTruncated: false, isStderrTruncated: false } }
  })
  return w
}

const start = async ($: Engine, surface: 'terminal' | 'desktop' = 'terminal') => {
  await $.session.start({ cwd: '/fm', surface, isInteractive: true })
  await refresh($)
}

const refresh = ($: Engine) => $.command.run({ command: 'crew', args: 'refresh', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 160 } })

type Drawn = { type?: string; key?: string; props?: Record<string, unknown>; children?: unknown[] }

const textOf = (node: unknown): string => {
  if (typeof node === 'string') return node
  const { children = [] } = (node ?? {}) as Drawn
  return children.map(textOf).join('')
}

/** Every shown text, in document order: Texts and Button labels, as a reader meets them. */
const lines = (node: unknown, out: string[] = []): string[] => {
  const { type, props = {}, children = [] } = (node ?? {}) as Drawn
  if (type === 'Text') out.push(textOf(node))
  else if (type === 'Button') out.push(`${props.hotkey ? `${String(props.hotkey)}: ` : ''}${String(props.label ?? '')}`)
  else for (const child of children) lines(child, out)
  return out
}

/**
 * Cells a node needs on one line: a cut Text its text, a Button its label (and `1: `), a row Box its
 * children and gaps, a column Box its widest child; a wrapping Text and a flexGrow spacer need none.
 */
const natural = (node: unknown): number => {
  if (typeof node === 'string') return cells(node)
  const { type, props = {}, children = [] } = (node ?? {}) as Drawn
  if (type === 'Text') return props.wrap === 'wrap' ? 0 : Math.max(0, ...textOf(node).split('\n').map(cells))
  if (type === 'Button') return cells(String(props.label ?? '')) + (props.hotkey ? 3 : 0) + (props.plain ? 0 : 4)
  if (type !== 'Box') return 0
  if (typeof props.width === 'number') return props.width
  const frame = (props.borderStyle ? 2 : 0) + 2 * Number(props.paddingX ?? 0)
  const kids = children.filter(Boolean).map(natural)
  if (props.flexDirection === 'column' || props.flexWrap === 'wrap') return frame + Math.max(0, ...kids)
  return frame + kids.reduce((n, k) => n + k, 0) + Number(props.columnGap ?? 0) * Math.max(0, kids.length - 1)
}

/** Every Box whose content needs more cells than it has: the overflow a terminal would cut or wrap. */
const overflows = (node: unknown, out: string[] = []): string[] => {
  const { type, props = {}, children = [] } = (node ?? {}) as Drawn
  if (type !== 'Box') return out
  const kids = children.filter(Boolean)
  if (typeof props.width === 'number') {
    const inner = props.width - (props.borderStyle ? 2 : 0) - 2 * Number(props.paddingX ?? 0)
    const need = natural({ ...(node as Drawn), props: { ...props, width: undefined, borderStyle: undefined, paddingX: 0 } })
    if (need > inner) out.push(`${String(props.key ?? (node as Drawn).key ?? 'Box')} needs ${need} of ${inner}: ${lines(node).slice(0, 2).join(' | ')}`)
    if (props.flexWrap === 'wrap') for (const kid of kids) if (natural(kid) > inner) out.push(`a wrapped child needs ${natural(kid)} of ${inner}`)
  }
  for (const kid of kids) overflows(kid, out)
  return out
}

const HEADINGS = ['OVERVIEW', 'AGENTS', 'QUOTA & LIMITS', 'ACTIVITY', 'RECENT LOGS']

test('the pane draws a header and the five zones in order; default cards carry no quota', async ($, on) => {
  stub(on, { report: REFERENCE })
  await start($)
  const ui = await $.ui.mount(sized(120, 40))
  const shown = lines(await ui.drawn())
  const at = HEADINGS.map(title => shown.indexOf(title))
  expect(at.every(i => i >= 0)).toBe(true)
  expect([...at].sort((a, b) => a - b)).toEqual(at)
  expect(shown[0]).toBe('CREW MONITOR · 2 live · 2 active')
  expect(shown[1]).toBe('● LIVE · updated 4s ago')
  expect(shown).toContain('Tokens 2.10M · Requests 27 · Tool calls 30 · Cache 92%')
  // The cache figure is labelled as what it is, never a hit rate.
  expect(shown.some(line => /hit rate/i.test(line))).toBe(false)
  // Agent cards: status word, recency, provider and model, context, requests and tools, the account.
  expect(shown).toContain('1: ▸ crew-watch-transparent')
  expect(shown).toContain(' ● ACTIVE · 24s')
  expect(shown).toContain(' ● WORKING · 8s')
  expect(shown).toContain('codex gpt-6.1-sol/medium · ship / workflow')
  expect(shown.some(line => line.includes('11% · 109k/1.00M'))).toBe(true)
  expect(shown.some(line => line.includes('5% · 44k/828k'))).toBe(true)
  expect(shown).toContain('19 req · 22 tools · in 38k / out 7.3k')
  expect(shown).toContain('acct claude andang')
  expect(shown).toContain('acct codex 60305a97')
  // Weekly figures live in Quota & Limits alone: one line per account, none in the cards.
  const quota = shown.indexOf('QUOTA & LIMITS')
  expect(shown.slice(0, quota).filter(line => /week|of week/.test(line))).toEqual([])
  const accounts = shown.slice(quota, shown.indexOf('ACTIVITY'))
  expect(accounts.filter(line => line.startsWith('claude andang · Max 5x') && line.includes('32% · measured 2m ago · resets in 23h 59m')).length).toBe(1)
  expect(accounts.filter(line => line.startsWith('claude thanhnv') && line.includes('week % —: no reading')).length).toBe(1)
  expect(accounts.filter(line => line.startsWith('codex 60305a97 · Plus') && line.includes('29% · measured 8s ago')).length).toBe(1)
  expect(shown.some(line => /61%|average|total quota/i.test(line))).toBe(false)
  // Logs: newest first, the source's own cut is not hidden in the preview.
  const logs = shown.slice(shown.indexOf('RECENT LOGS'))
  expect(logs.findIndex(line => line.includes('uv lock --upgrade-package cryptogr…')) < logs.findIndex(line => line.includes('Read: hooks/zones.tsx'))).toBe(true)
  expect(overflows(await ui.drawn())).toEqual([])
  await ui.unmount()
})

test('agents sit two to a row from 110 columns, stack below, and list as rows at 60', async ($, on) => {
  stub(on, { report: REFERENCE })
  await start($)
  for (const [columns, rows, mode] of [[120, 36, 'side'], [110, 36, 'side'], [109, 36, 'stack'], [80, 24, 'stack'], [80, 32, 'stack'], [60, 24, 'rows']] as const) {
    const ui = await $.ui.mount(sized(columns, rows))
    const tree = await ui.drawn()
    const pair = await ui.find({ key: 'cards-0' }) as Drawn | undefined
    if (mode === 'side') expect(pair?.children?.filter(Boolean).length).toBe(2)
    if (mode === 'stack') {
      expect(pair?.children?.filter(Boolean).length).toBe(1)
      expect(await ui.find({ key: 'cards-1' })).toBeDefined()
    }
    if (mode === 'rows') {
      expect(await ui.find({ key: 'cards-0' })).toBeUndefined()
      expect(await ui.find({ key: 'row-/fm:workflow-cryptography-advisory' })).toBeDefined()
    }
    // Status and full names stay readable at every width, and nothing runs past the pane.
    const shown = lines(tree)
    // Each account's weekly figure keeps its reset time: the line splits rather than cut it.
    expect(shown.filter(line => line.includes('resets in 23h 59m')).length).toBe(2)
    expect(shown.some(line => line.endsWith('…') && line.includes('week'))).toBe(false)
    for (const name of ['crew-watch-transparent', 'workflow-cryptography-advisory']) expect(shown.some(line => line.includes(name))).toBe(true)
    expect(shown.some(line => line.includes('WORKING'))).toBe(true)
    expect(overflows(tree)).toEqual([])
    await ui.unmount()
  }
})

test('a short pane folds Activity and the log preview; a tall one shows five log rows', async ($, on) => {
  const many = { ...REFERENCE, crew: REFERENCE.crew.map(m => ({ ...m, events: Array.from({ length: 6 }, (_, i) => ({ at: NOW - i * 1_000, kind: 'tool' as const, text: `step ${m.id} ${i}` })) })) }
  stub(on, { report: many })
  await start($)
  const view = async (columns: number, rows: number) => {
    const ui = await $.ui.mount(sized(columns, rows))
    const shown = lines(await ui.drawn())
    await ui.unmount()
    return shown
  }
  const short = await view(120, 20)
  expect(short.some(line => /^2 of 2 readable crewmates logged activity in \d+ min · newest 8s ago$/.test(line))).toBe(true)
  expect(short.some(line => line.startsWith('12 entries · newest '))).toBe(true)
  expect(short.filter(line => line.includes('▸ TOOL')).length).toBe(0)
  const mid = await view(80, 32)
  expect(mid.filter(line => line.includes('▸ TOOL')).length).toBe(3)
  const tall = await view(120, 40)
  expect(tall.filter(line => line.includes('▸ TOOL')).length).toBe(5)
  expect(tall.some(line => line.includes('newest first · All · 5 of 12 · l more'))).toBe(true)
})

test('keys switch details, logs, filters and help, and every hotkey is unique', { timeoutMs: 30_000 }, async ($, on) => {
  stub(on, { report: REFERENCE })
  await start($)
  const ui = await $.ui.mount(sized(120, 40, { isFocused: true }))
  const hotkeys = (await ui.findAll({ type: 'Button' })).map(b => (b as Drawn).props?.hotkey).filter(Boolean)
  expect(hotkeys).toEqual(['d', 'l', 'f', 'h', '1', '2'])
  // Compact by default: no level-C rows.
  expect(await ui.find({ text: /^in 75k · out 9\.1k · thinking 2\.7k$/ })).toBeUndefined()
  await ui.press({ key: 'key-mode' })
  expect(await ui.find({ text: /^in 75k · out 9\.1k · thinking 2\.7k$/ })).toBeDefined()
  expect(await ui.find({ text: /^Tokens = in \+ out \+ cache read \+ cache write/ })).toBeDefined()
  expect(await ui.find({ text: /neither exact nor an upper bound/ })).toBeDefined()
  expect(await ui.find({ text: '  session <1% of week est' })).toBeDefined()
  expect(await ui.find({ text: '  source codex log' })).toBeDefined()
  expect(await ui.find({ text: '  no crew usage in this window' })).toBeDefined()
  expect((await ui.find({ key: 'key-mode' }) as Drawn | undefined)?.props?.label).toBe('compact')
  // Logs expand to full entries that say where the source cut them.
  await ui.press({ key: 'key-logs' })
  expect(await ui.find({ text: /uv lock --upgrade-package cryptogr… \(source truncated\)/ })).toBeDefined()
  expect(await ui.find({ text: /--home \/home… \(source truncated\)/ })).toBeDefined()
  // Filters: All -> Tools -> Status -> Errors (nothing matches, and it says so) -> All.
  await ui.press({ key: 'key-filter' })
  expect(await ui.find({ text: /newest first · Tools · 4 of 4$/ })).toBeDefined()
  await ui.press({ key: 'key-filter' })
  expect(await ui.find({ text: 'No matching logs (filter: Status).' })).toBeDefined()
  await ui.press({ key: 'key-filter' })
  expect(await ui.find({ text: 'No matching logs (filter: Errors).' })).toBeDefined()
  await ui.press({ key: 'key-filter' })
  expect(await ui.find({ text: /newest first · All · 4 of 4$/ })).toBeDefined()
  // With a crewmate open the cycle offers its own log.
  await ui.press({ key: 'card-/fm:workflow-cryptography-advisory' })
  for (let i = 0; i < 4; i++) await ui.press({ key: 'key-filter' })
  expect(await ui.find({ text: /newest first · Agent: workflow-cryptography-advisory · 2 of 2$/ })).toBeDefined()
  // Closing the crewmate ends its filter; it never stays as an Agent filter that filters nothing.
  await ui.press({ key: 'card-/fm:workflow-cryptography-advisory' })
  expect(await ui.find({ text: /newest first · All · 4 of 4$/ })).toBeDefined()
  expect((await ui.find({ key: 'key-filter' }) as Drawn | undefined)?.props?.label).toBe('filter All')
  await ui.press({ key: 'card-/fm:workflow-cryptography-advisory' })
  await ui.press({ key: 'key-help' })
  expect(await ui.find({ text: 'HELP' })).toBeDefined()
  expect(await ui.find({ text: /^d {14}compact or details mode$/ })).toBeDefined()
  expect(await ui.find({ text: /^Esc .*close details with its number\)$/ })).toBeDefined()
  expect(overflows(await ui.drawn())).toEqual([])
  await ui.press({ key: 'key-help' })
  expect(await ui.find({ text: 'HELP' })).toBeUndefined()
  await ui.unmount()
})

test('the open crewmate, mode and log filter survive a live refresh', async ($, on) => {
  const world = stub(on, { report: REFERENCE })
  await start($)
  const ui = await $.ui.mount(sized(120, 40, { isFocused: true }))
  await ui.press({ key: 'card-/fm:crew-watch-transparent' })
  await ui.press({ key: 'key-mode' })
  await ui.press({ key: 'key-filter' })
  await ui.unmount()
  world.report = { ...REFERENCE, generatedAt: NOW + 5_000, crew: [...REFERENCE.crew].reverse() }
  world.now = NOW + 6_000
  await refresh($)
  const after = await $.ui.mount(sized(120, 40, { isFocused: true }))
  expect(await after.find({ text: 'crew-watch-transparent · details' })).toBeDefined()
  expect((await after.find({ key: 'card-/fm:crew-watch-transparent' }) as Drawn | undefined)?.props?.label).toBe('▾ crew-watch-transparent')
  expect((await after.find({ key: 'key-mode' }) as Drawn | undefined)?.props?.label).toBe('compact')
  expect(await after.find({ text: /newest first · Tools/ })).toBeDefined()
  expect(await after.find({ text: '● LIVE · updated 1s ago' })).toBeDefined()
  await after.unmount()
  // A crewmate that leaves closes its details; the others stay.
  world.report = { ...REFERENCE, generatedAt: NOW + 10_000, crew: REFERENCE.crew.slice(1) }
  await refresh($)
  const gone = await $.ui.mount(sized(120, 40))
  expect(await gone.find({ text: /· details$/ })).toBeUndefined()
  expect(await gone.find({ key: 'card-/fm:workflow-cryptography-advisory' })).toBeDefined()
})

test('a failed read says SOURCE ERROR with its reason and the age of the last good data; old data is STALE', async ($, on) => {
  const world = stub(on, { fail: 'Traceback\nValueError: boom' })
  await start($)
  const none = await $.ui.mount(sized(80, 24))
  // Before any report the crew's size is unknown, not zero.
  expect(await none.find({ text: 'CREW MONITOR · — live · — active' })).toBeDefined()
  expect(await none.find({ text: '× SOURCE ERROR · no data yet' })).toBeDefined()
  expect(await none.find({ text: '× SOURCE ERROR: crew_usage.py failed: ValueError: boom' })).toBeDefined()
  expect(await none.find({ text: `Tokens — · Requests — · Tool calls — · Cache —` })).toBeDefined()
  await none.unmount()
  world.fail = ''
  await refresh($)
  world.fail = 'read unavailable'
  world.now = NOW + 45_000
  await refresh($)
  const failed = await $.ui.mount(sized(80, 24))
  expect(await failed.find({ text: '× SOURCE ERROR · last good 45s ago' })).toBeDefined()
  expect(await failed.find({ text: /fix-login/ })).toBeDefined()
  await failed.unmount()
  world.fail = ''
  world.report = { ...REPORT, generatedAt: NOW - 60_000, errors: ['cache not saved: disk full'] }
  world.now = NOW
  await refresh($)
  const stale = await $.ui.mount(sized(80, 24))
  expect(await stale.find({ text: '◷ STALE · updated 1m ago' })).toBeDefined()
  // Ages keep moving with the clock while the data is stale: the crewmate last seen 90 s ago is no longer active.
  expect(await stale.find({ text: ' ● ACTIVE · 1m' })).toBeUndefined()
  expect(await stale.find({ text: '! cache not saved: disk full' })).toBeDefined()
  expect(await stale.find({ text: /SOURCE ERROR/ })).toBeUndefined()
})

test('missing data reads as missing: no crew, unreadable harness, unknown model, unknown account', async ($, on) => {
  const world = stub(on, { report: { ...REPORT, crew: [], quota: { readings: {}, fleet: {} } } })
  await start($)
  const first = await $.ui.mount(sized(80, 24))
  const empty = lines(await first.drawn())
  await first.unmount()
  for (const text of ['No crewmates are live.', 'No quota readings yet.', 'No activity data: no crewmates are live.', 'No log events yet.']) expect(empty).toContain(text)
  world.report = {
    ...REPORT,
    crew: [
      member({ id: 'pi-task', harness: 'pi', readable: false, sessions: 0, requests: 0, toolCalls: 0, models: {}, context: 0, contextWindow: null, contextModel: '', lastTool: '', lastText: '', status: '', lastAt: 0, quota: {}, activity: [], events: [] }),
      member({ id: 'mystery', harness: 'claude', contextWindow: null, contextModel: 'claude-unreleased', context: 5_000, quota: { 'claude|unknown|seven_day': { session: figure({ percent: null, basis: 'raw' }), tools: figure({ percent: null, basis: 'raw' }) } } }),
      member({ id: 'fresh', context: 0, contextWindow: null, contextModel: '', requests: 0, toolCalls: 0, models: {}, quota: {} }),
    ],
    quota: { readings: { 'claude|unknown|seven_day': reading({ account: 'unknown', accountKnown: false, percent: null, plan: '' }) }, fleet: {} },
  }
  await refresh($)
  const ui = await $.ui.mount(sized(80, 32))
  const shown = lines(await ui.drawn())
  expect(shown).toContain(' ? UNKNOWN · —')
  expect(shown).toContain('— req · — tools · pi logs not readable')
  expect(shown).toContain('Ctx — · logs not readable')
  expect(shown).toContain('acct — · logs not readable')
  expect(shown).toContain('Ctx — · no request yet')
  expect(shown).toContain('excludes 1 crewmate: pi logs not readable')
  expect(shown).toContain('Ctx 5.0k · window n/a for unreleased')
  expect(shown).toContain('acct claude account unknown')
  expect(shown.some(line => line.startsWith('claude account unknown') && line.includes('week % —: account unknown'))).toBe(true)
  expect(shown.some(line => line.startsWith('history unavailable: pi logs not readable'))).toBe(true)
  expect(shown.some(line => /NaN|undefined|Infinity/.test(line))).toBe(false)
  await ui.press({ key: 'card-/fm:pi-task' })
  expect(await ui.find({ text: 'usage is not readable for the pi harness' })).toBeDefined()
  expect(await ui.find({ text: '— no tool call yet' })).toBeDefined()
  expect(await ui.find({ text: 'tools —: pi logs not readable' })).toBeDefined()
  expect(await ui.find({ text: /harness pi · transcripts not readable/ })).toBeDefined()
  // Details mode adds no zeros for it either.
  await ui.press({ key: 'key-mode' })
  const details = lines(await ui.drawn())
  expect(details.filter(line => line.startsWith('thinking ')).length).toBe(2)
  expect(details.some(line => /^tools 0 · 0 tok$|0 transcripts/.test(line))).toBe(false)
  await ui.unmount()
  // With no readable crewmate at all, the fleet totals are unknown, not zero.
  world.report = { ...REPORT, crew: [REPORT.crew[1] as CrewMember], totals: { requests: 0, input: 0, output: 0, cacheRead: 0, cacheWrite: 0, reasoning: 0, toolCalls: 0 } }
  await refresh($)
  const blind = await $.ui.mount(sized(80, 24))
  expect(await blind.find({ text: 'Tokens — · Requests — · Tool calls — · Cache —' })).toBeDefined()
  expect(await blind.find({ text: 'no readable usage from 1 crewmate: pi logs not readable' })).toBeDefined()
  expect(await blind.find({ text: 'Activity history unavailable: no crewmate\'s logs are readable.' })).toBeDefined()
})

test('many crewmates, long unicode names and long commands stay inside the pane at 60, 80 and 120 columns', { timeoutMs: 60_000 }, async ($, on) => {
  const name = 'very-very-long-agent-name-with-unicode-測試-🚀'
  const crew = Array.from({ length: 12 }, (_, i) => member({
    id: i === 0 ? name : `crew-${i}`,
    harness: i % 3 === 0 ? 'claude' : i % 3 === 1 ? 'codex' : 'pi',
    status: i === 2 ? 'blocked [at=1]: the review needs a product decision about the quota thresholds' : '',
    lastTool: `Bash: ${'/very/long/path/nested'.repeat(20)}`,
    events: [{ at: NOW - i * 1_000, kind: 'tool', text: `Bash: ${'/very/long/path/nested'.repeat(20)}…` }],
  }))
  stub(on, { report: { ...REPORT, crew } })
  await start($)
  for (const [columns, rows] of [[60, 24], [80, 24], [80, 32], [120, 36], [120, 40]] as const) {
    for (const mode of ['compact', 'details'] as const) {
      const ui = await $.ui.mount(sized(columns, rows, { isFocused: true }))
      if (mode === 'details') await ui.press({ key: 'key-mode' })
      const tree = await ui.drawn()
      expect(overflows(tree)).toEqual([])
      const buttons = (await ui.findAll({ type: 'Button' })).map(b => (b as Drawn).props?.hotkey).filter(h => /^\d$/.test(String(h)))
      expect(buttons).toEqual(['1', '2', '3', '4', '5', '6', '7', '8', '9'])
      expect((await ui.findAll({ type: 'Box' })).filter(b => String((b as Drawn).key ?? (b as Drawn).props?.key ?? '').startsWith('row-')).length).toBe(12)
      expect(await ui.find({ text: /^× blocked \[at=1\]: the review/ })).toBeDefined()
      if (mode === 'details') await ui.press({ key: 'key-mode' })
      await ui.unmount()
    }
  }
})

test('inline above the prompt the summary keeps zone order within eight rows, accounts apart', async ($, on) => {
  const world = stub(on, { report: { ...REFERENCE, crew: Array.from({ length: 9 }, (_, i) => member({ id: `crew-${i}` })) } })
  await start($)
  const mini = await $.ui.mount(sized(80, 24, { placement: 'inline' }))
  const tree = await mini.drawn() as Drawn
  const shown = lines(tree)
  expect((tree.children ?? []).filter(Boolean).length).toBe(8)
  expect(shown[0]).toMatch(/^CREW · 9 live · \d active · ● LIVE updated 4s ago$/)
  expect(shown[1]).toBe('Tok 2.10M · Req 27 · Tools 30 · Cache 92%')
  expect(shown[2]).toMatch(/^● crew-0 · ACTIVE 34s · claude sonnet\/medium$/)
  expect(shown).toContain('+6 more · dock /crew for details')
  expect(shown.slice(-2)).toEqual(['claude week: andang 32% · thanhnv —', 'codex week: 60305a97 29%'])
  await mini.unmount()
  world.fail = 'read unavailable'
  await refresh($)
  const failed = await $.ui.mount(sized(80, 24, { placement: 'inline' }))
  const again = await failed.drawn() as Drawn
  expect((again.children ?? []).filter(Boolean).length).toBe(8)
  expect(await failed.find({ text: /read unavailable/ })).toBeDefined()
  expect(overflows(again)).toEqual([])
})

test('the refresh command reports the crew and passes the session and its sign-in presence only', async ($, on) => {
  const world = stub(on, { env: { CLAUDE_CODE_OAUTH_TOKEN: 'fabricated-not-a-token' } })
  await $.session.start({ cwd: '/fm', surface: 'desktop', isInteractive: true })
  const ran = await refresh($)
  expect(ran.text).toBe('Crew refreshed: 2 live crewmate(s).')
  expect(world.argv.slice(-2)).toEqual(['--home', '/fm'])
  expect(world.argv[world.argv.indexOf('--claude-session') + 1]).toBe('pane-session')
  // The script cannot see the token variable, so the mod says whether one signs this session in (presence only).
  expect(world.argv[world.argv.indexOf('--claude-login') + 1]).toBe('token')
  expect(world.argv.join(' ')).not.toContain('fabricated-not-a-token')
})

// drawn() validates the returned tree against the surface table and rejects a refusal.
test('dashboard matrix draws every fleet size, width, placement and surface', { timeoutMs: 120_000 }, async ($, on) => {
  const world = stub(on)
  await $.session.start({ cwd: '/fm', surface: 'desktop', isInteractive: true })
  for (const size of [0, 1, 3, 8]) {
    world.report = { ...REPORT, crew: Array.from({ length: size }, (_, i) => member({ id: `crew-${i}`, depth: i === 1 ? 1 : 0, harness: i % 2 ? 'codex' : 'claude' })) }
    await refresh($)
    for (const surface of ['terminal', 'desktop'] as const) {
      for (const columns of [40, 60, 80, 120]) {
        for (const placement of ['dock', 'inline'] as const) {
          const ui = await $.ui.mount({ ...PANE, surface, props: { ...PANE.props, isFocused: true, bodyColumns: columns, placement } })
          const tree = await ui.drawn() as Drawn
          expect(tree.type).toBe('Box')
          expect(await ui.find({ text: new RegExp(`CREW( MONITOR)? · ${size} live`) })).toBeDefined()
          if (placement === 'inline') {
            expect((tree.children ?? []).filter(Boolean).length <= 8).toBe(true)
            expect(await ui.find({ text: 'RECENT LOGS' })).toBeUndefined()
          } else {
            for (const title of HEADINGS) expect(await ui.find({ text: title })).toBeDefined()
            if (size > 0) {
              await ui.press({ key: 'card-/fm:crew-0' })
              expect(await ui.find({ text: /Fix login validation/ })).toBeDefined()
              expect(await ui.find({ text: /branch fm\/fix-login/ })).toBeDefined()
              expect(await ui.find({ text: /Read ×3/ })).toBeDefined()
              await ui.press({ key: 'card-/fm:crew-0' })
            }
          }
          if (surface === 'terminal' && columns >= 60) expect(overflows(tree)).toEqual([])
          await ui.unmount()
        }
      }
    }
  }
})

test('the expanded crewmate shows tokens per recent call, per-tool totals and its account limits', async ($, on) => {
  stub(on)
  await start($)
  const ui = await $.ui.mount(sized(120, 40))
  await ui.press({ key: 'card-/fm:fix-login' })
  expect(await ui.find({ text: /out 640 in 2\.3k · Bash: npm test/ })).toBeDefined()
  expect(await ui.find({ text: /Bash ×20 · 42k tok · avg 2\.1k/ })).toBeDefined()
  expect(await ui.find({ text: /Edit ×8 · 4\.6k tok · avg ~575/ })).toBeDefined()
  expect(await ui.find({ text: /~ estimated from result size/ })).toBeDefined()
  expect(await ui.find({ text: 'context 88,000 / 200,000 tokens (44.0%) · window from transcript' })).toBeDefined()
  expect(await ui.find({ text: 'SOURCE & LIMITS' })).toBeDefined()
  expect(await ui.find({ text: 'claude andang · Max 5x' })).toBeDefined()
  expect(await ui.find({ text: 'session ~7% of week est' })).toBeDefined()
  expect(await ui.find({ text: 'tools direct ~3% of week est' })).toBeDefined()
  expect(await ui.find({ text: /later cache re-reads count to the session only/ })).toBeDefined()
  await ui.unmount()
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
  // A narrow card's row is 32 cells: no quota row may be cut there.
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
  const reads: string[] = []
  const world = stub(on, { env: { AI_ACCT_FINGERPRINT: 'b'.repeat(64), XDG_CACHE_HOME: '/cache' } })
  on('fs.list', () => ({ value: ['claude-alpha.limits.json', 'claude-beta.limits.json'].map(name => ({ name, kind: 'file' as const, size: 1, mtimeMs: 0, isLink: false })) }))
  on('fs.read', (_, e) => {
    reads.push(e.path)
    return { value: e.path.includes('beta') ? LIMITS_B : LIMITS_A }
  })
  await start($, 'desktop')
  expect(world.argv[world.argv.indexOf('--claude-account') + 1]).toBe('beta')
  expect(world.argv.join(' ')).not.toContain('b'.repeat(64))
  // Only the stored limit files of ai-acct are opened: never a token file.
  expect(reads.every(path => path.startsWith('/cache/ai-acct/claude-') && path.endsWith('.limits.json'))).toBe(true)
})

test('a session without a fingerprint or a matching account passes an empty account', async ($, on) => {
  const world = stub(on)
  await start($, 'desktop')
  expect(world.argv[world.argv.indexOf('--claude-account') + 1]).toBe('')
})

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
  stub(on, { env })
  await start($)
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
    stub(on, { env: { COLORTERM: 'truecolor' } })
    await start($)
    for (const placement of ['dock', 'inline'] as const) {
      for (const columns of [40, 130]) {
        const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: { ...PANE.props, bodyColumns: columns, placement } })
        expect(paintsBackground(await ui.drawn())).toBe(false)
        await ui.unmount()
      }
    }
  })
}
