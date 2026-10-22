import { expect, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'

import type { On } from 'claude-code'

import type { CrewMember, CrewReport } from '../types'
import { dashboardLayout } from '../hooks/dashboard'
import { PALETTES } from '../hooks/theme'
import { callTokensText, quotaRows, toolTokenNote, toolTokenText } from '../hooks/format'

const NOW = 1_800_000_000_000

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
    claude: { session: { share: 0.2, percent: 7.4 }, tools: { share: 0.08, percent: 2.96 } },
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
    providers: {
      claude: { plan: 'Max 5x', login: 'account', percentUsed: 37, resetsAt: NOW + 86_400_000, windowStart: NOW - 5 * 86_400_000, windowStartKnown: true, source: 'this session', readAt: NOW - 120_000, stale: false, reset: false, indexed: true, localCost: 1e6 },
    },
    fleet: { claude: { session: { share: 0.2, percent: 7.4 }, tools: { share: 0.08, percent: 2.96 } } },
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
    expect(await ui.find({ text: 'claude Max 5x' })).toBeDefined()
    expect(await ui.find({ text: 'week 37% used · current' })).toBeDefined()
    expect(await ui.find({ text: 'read 2m ago · this session' })).toBeDefined()
    expect(await ui.find({ text: 'session 7.4% of week' })).toBeDefined()
    expect(await ui.find({ text: 'tools direct 3.0% of week' })).toBeDefined()
    expect(await ui.find({ text: /with a current reading shares are upper bounds/ })).toBeDefined()
    expect(await ui.find({ text: /later cache re-reads count to the session only/ })).toBeDefined()
    expect(await ui.find({ text: /other machines and the web are not seen/ })).toBeDefined()
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
  const quota = { claude: { session: { share: 0.1, percent: 4.4 }, tools: { share: 0.02, percent: 0.9 } } }
  let report = REPORT
  on('env.get', () => ({ value: undefined }))
  on('process.run', () => ({ value: { exitCode: 0, stdout: JSON.stringify(report), stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  await $.session.start({ cwd: '/fm', surface: 'terminal', isInteractive: true })
  for (const [columns, size] of [[80, 2], [111, 3], [120, 3]] as const) {
    report = { ...REPORT, crew: Array.from({ length: size }, (_, i) => member({ id: `crew-${i}`, quota })) }
    await $.command.run({ command: 'crew', args: 'refresh', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 160 } })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: { ...PANE.props, bodyColumns: columns } })
    expect(dashboardLayout(columns, 'dock', size).mode).toBe('cards')
    for (const text of ['session 4.4% of week', 'tools direct 0.9% of week', 'read 2m ago · this session', 'week 37% used · current']) {
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
  const share = { session: { share: 0.31, percent: null }, tools: { share: 0.004, percent: null } }
  const provider = { plan: '', login: '', percentUsed: null, resetsAt: null, windowStart: 0, windowStartKnown: false, source: '', readAt: null, stale: false, reset: true, indexed: true, localCost: 5 }
  expect(quotaRows({ codex: share }, { codex: provider }, NOW).map(r => r.text)).toEqual([
    'codex plan not recorded locally',
    'session 31% of local',
    'tools direct 0.4% of local',
    'week % unknown: window reset',
  ])
  expect(quotaRows({ codex: share }, { codex: { ...provider, indexed: false } }, NOW).map(r => r.text)).toEqual(['codex plan not recorded locally', 'indexing local logs…'])
  const old = { ...provider, plan: 'Max 20x · Team', percentUsed: 10, source: 'usage cache', readAt: NOW - 4 * 86_400_000, stale: true, reset: false }
  const measured = { session: { share: 0.31, percent: 3.1 }, tools: { share: 0.004, percent: 0.04 } }
  expect(quotaRows({ claude: measured }, { claude: old }, NOW)).toEqual([
    { text: 'claude Max 20x · Team', tone: 'subtle' },
    { text: 'week 10% used · stale', tone: 'warning' },
    { text: 'read 4d ago · usage cache', tone: 'subtle' },
    { text: 'session 3.1% of week', tone: 'text' },
    { text: 'tools direct <0.1% of week', tone: 'text' },
  ])
  // A token login (ai-acct) records no plan: say so, within a collapsed card's 32 cells.
  const token = quotaRows({ claude: share }, { claude: { ...provider, login: 'token', indexed: false } }, NOW).map(r => r.text)
  expect(token).toEqual(['claude token login', 'plan not exposed by token login', 'indexing local logs…'])
  expect(quotaRows({ codex: share }, { codex: { ...provider, login: 'rollout', indexed: false } }, NOW)[0]?.text).toBe('codex plan not in rollout')
  expect(quotaRows({ claude: share }, { claude: { ...provider, login: 'api-key', indexed: false } }, NOW)[0]?.text).toBe('claude API key')
  const undated = quotaRows({ claude: measured }, { claude: { ...old, readAt: null } }, NOW)
  expect(undated[2]?.text).toBe('read time unknown · usage cache')
  // A collapsed card's narrowest row is 32 cells: no quota row may be cut there.
  const rows = [...undated, ...quotaRows({ claude: measured }, { claude: { ...old, source: 'this session', readAt: NOW - 86_340_000 } }, NOW),
    ...quotaRows({ codex: share }, { codex: provider }, NOW)]
  expect(rows.filter(r => r.text.length > 32)).toEqual([])
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
