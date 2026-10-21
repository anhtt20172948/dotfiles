import { expect, test } from 'claude-code/testing'

import type { CrewMember, CrewReport } from '../types'

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
  events: [{ at: NOW - 30_000, kind: 'tool', text: 'Bash: npm test' }, { at: NOW - 60_000, kind: 'status', text: 'working' }],
  recentTools: [{ at: NOW - 30_000, kind: 'tool', text: 'Bash: npm test' }],
  activity: [{ minute: Math.floor(NOW / 60_000), count: 2 }],
  tools: { Bash: 20, Edit: 8, Read: 3 },
  toolCalls: 31,
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
  on('clock.every', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('process.run', (_, e) => {
    argv = e.argv
    return { value: { exitCode: 0, stdout: JSON.stringify(REPORT), stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })

  await $.session.start({ cwd: '/fm', surface: 'desktop', isInteractive: true })
  const ran = await $.command.run({ command: 'crew', args: 'refresh', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 160 } })
  expect(ran.text).toBe('Crew refreshed: 2 live crewmate(s).')
  expect(argv.slice(-2)).toEqual(['--home', '/fm'])

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ type: 'Text', text: /2 live/ }))?.text).toContain('CREW')
    expect(await ui.find({ text: /31 tool calls/ })).toBeDefined()
    expect(await ui.find({ text: /sonnet-5-5 ×12/ })).toBeDefined()
    expect(await ui.find({ text: /88k\/200k/ })).toBeDefined()
    expect((await ui.find({ type: 'Text', text: /cache ▰/ }))?.text).toContain('95%')
    expect(await ui.find({ text: /tools 31/ })).toBeDefined()
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
  on('clock.every', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('process.run', () => ({ value: { exitCode: 1, stdout: '', stderr: 'Traceback\nValueError: boom', isStdoutTruncated: false, isStderrTruncated: false } }))

  await $.session.start({ cwd: '/fm', surface: 'desktop', isInteractive: true })
  await $.command.run({ command: 'crew', args: 'refresh', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 160 } })

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /boom/ }))?.text).toBe('crew_usage.py failed: ValueError: boom')
  await ui.unmount()
})

// drawn() validates the returned tree against the surface table and rejects a refusal.
test('dashboard matrix draws every fleet size, width, placement and surface', async ($, on) => {
  let current = REPORT
  on('command.register', () => ({ value: { command: 'crew' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.root', () => ({ value: '/fm' }))
  on('clock.every', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
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
  on('clock.every', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
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
