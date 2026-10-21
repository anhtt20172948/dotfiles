import { expect, mock, test } from 'claude-code/testing'
import type { TestBody } from 'claude-code/testing'

import { diffEvents, eventText } from '../hooks/lib/events'
import { bandSegments, columnsFor, fitSegments, pad, rowText } from '../hooks/lib/layout'
import type { FleetRow } from '../types'
import { parseSnapshot } from '../hooks/lib/snapshot'
import { accountFromLimits, modelLabel, statusText } from '../hooks/lib/usage'

const FINGERPRINT = 'a'.repeat(64)

const ran = (stdout: string) => ({
  value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
})

const snapshot = (tasks: unknown[], records: unknown[] = []) => ({
  schema: 'fm-fleet-snapshot.v1',
  tasks,
  backlog: { records },
})

const task = (id: string, state: string, extra: Record<string, unknown> = {}) => ({
  id,
  project: '/home/x/projects/dotfiles',
  spawn_gen: `gen-${id}`,
  current_state: { state },
  pr: { url: null },
  hints: { open_decisions: [] },
  ...extra,
})

const parsed = (tasks: unknown[], records: unknown[] = []) => {
  const result = parseSnapshot(snapshot(tasks, records))

  if (result === null) {
    throw new Error('snapshot did not parse')
  }

  return result
}

test('a snapshot of another schema is ignored', async () => {
  expect(parseSnapshot({ schema: 'other', tasks: [] })).toBe(null)
  expect(parseSnapshot('nonsense')).toBe(null)
})

test('the fleet counts workers, PRs and what needs the captain', async () => {
  const { fleet } = parsed([
    task('a', 'working'),
    task('b', 'working', { pr: { url: 'https://github.com/o/r/pull/33' } }),
    task('c', 'blocked'),
    task('d', 'done', { pr: { url: 'https://github.com/o/r/pull/9' } }),
  ])

  expect(fleet.running).toBe(2)
  expect(fleet.prs).toBe(1)
  expect(fleet.attention).toBe(1)
  expect(fleet.rows.map(row => row.id)).toEqual(['c', 'a', 'b', 'd'])
  expect(fleet.rows[2]?.pr).toBe('#33')
  expect(fleet.rows[0]?.project).toBe('dotfiles')
})

test('events are named for what happened, once', async () => {
  const before = parsed([task('a', 'working'), task('b', 'working'), task('c', 'working')])
  const after = parsed(
    [
      task('a', 'done'),
      task('b', 'working', { pr: { url: 'https://github.com/o/r/pull/7' } }),
      task('c', 'failed'),
    ],
    [{ id: 'z', merged: '2026-10-21' }],
  )
  const events = diffEvents(before.track, after.track)

  expect(events.map(event => event.kind)).toEqual(['finished', 'failed', 'pr', 'merged'])
  expect(diffEvents(after.track, after.track)).toEqual([])
  expect(events.map(eventText)).toEqual([
    'a finished',
    'c failed',
    'b: PR #7 ready',
    'z: merge landed',
  ])
})

test('columns align and give way, narrowest first', async () => {
  const { fleet } = parsed([task('a-long-worker-name-here', 'working')])
  const wide = columnsFor(120, fleet.rows)
  const narrow = columnsFor(36, fleet.rows)
  const tiny = columnsFor(24, fleet.rows)

  expect(wide.map(column => column.key)).toEqual(['id', 'project', 'state', 'pr'])
  expect(narrow.map(column => column.key)).toEqual(['id', 'state', 'pr'])
  expect(tiny.map(column => column.key)).toEqual(['id', 'state'])
  expect(rowText(fleet.rows[0] as FleetRow, wide).length).toBeLessThanOrEqual(120)
  expect(pad('abcdefghij', 6)).toBe('abcde…')
  expect(pad('ab', 4)).toBe('ab  ')
})

test('the band drops its least urgent pieces first', async () => {
  const { fleet } = parsed([task('a', 'working'), task('b', 'blocked')])
  const segments = bandSegments(fleet)

  expect(segments.map(segment => segment.text)).toEqual(['1 needs you', '1 worker'])
  expect(fitSegments(segments, 80)).toHaveLength(2)
  expect(fitSegments(segments, 12)).toHaveLength(1)
})

test('the account is found by fingerprint and quota is shown as used', async () => {
  const files = [
    {
      name: 'claude-work.limits.json',
      text: JSON.stringify({
        fingerprint: FINGERPRINT,
        windows: { five_hour: { used: 41.4 }, seven_day: { used: 12 } },
      }),
    },
    { name: 'claude-other.limits.json', text: JSON.stringify({ fingerprint: 'b'.repeat(64) }) },
  ]
  const found = accountFromLimits(FINGERPRINT, files)

  expect(found).toEqual({ account: 'work', fiveHour: 41, sevenDay: 12 })
  expect(accountFromLimits(undefined, files)).toBe(null)
  expect(modelLabel('claude-opus-4-7[1m]')).toBe('opus 4.7')
  expect(
    statusText('claude-opus-4-7', 23.4, { account: 'work', fiveHour: 41, sevenDay: 12 }),
  ).toBe('opus 4.7 · ctx 23% · work 5h 41% 7d 12%')
})

const PANE = {
  plugin: 'fleet-deck',
  component: 'Pane',
  requestId: 'fleet',
  props: {
    title: 'Fleet',
    isFocused: false,
    bodyColumns: 60,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 20 },
    view: {},
  },
} as const

const BAND = {
  plugin: 'fleet-deck',
  component: 'AbovePrompt',
  props: {
    hasSurvey: false,
    isWorking: false,
    maxRows: 6,
    bodyColumns: 100,
    scroll: { offset: 0, bodyRows: 6 },
    view: {},
  },
} as const

const SNAPSHOT_OUTPUT = JSON.stringify(
  snapshot([task('alpha', 'working'), task('beta', 'blocked')]),
)

test('with a Firstmate home the band and pane show the fleet, on every surface', async ($, on) => {
  mock.clock(on)
  mock.store(on)
  mock.env(on, { HOME: '/home/x' })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('fs.stat', () => ({ value: { kind: 'file', size: 1, mtimeMs: 0, isLink: false } }))
  on('process.run', (_, e) =>
    e.argv[0] === 'uname'
      ? ran('Linux\n')
      : ran(SNAPSHOT_OUTPUT),
  )
  on('command.register', () => ({ value: { command: 'fleet' } }))
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)

    return <Text>engine</Text>
  })
  on('session.model', () => ({ value: 'claude-opus-4-7' }))
  on('ui.status', () => ({ value: undefined }))

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  for (const surface of ['terminal', 'desktop'] as const) {
    const band = await $.ui.mount({ ...BAND, surface })
    const text = (await band.find({ type: 'Text', text: /need/ }))?.text ?? ''
    expect(text).toMatch(/1 needs you/)
    expect((await band.find({ type: 'Text', text: /engine/ }))?.text).toBe('engine')
    await band.unmount()

    const pane = await $.ui.mount({ ...PANE, surface })
    expect((await pane.find({ type: 'Text', text: /alpha/ }))?.text).toMatch(/alpha\s+dotfiles\s+working/)
    await pane.unmount()
  }
})

test('without a Firstmate home the band draws nothing and nothing is registered', async ($, on) => {
  mock.clock(on)
  mock.store(on)
  mock.env(on, { HOME: '/home/x' })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('fs.stat', () => ({ deny: 'no such file' }))
  on('process.run', () => (ran('Linux\n')))
  on('session.model', () => ({ value: 'claude-opus-4-7' }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)

    return <Text>engine</Text>
  })

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })

  expect(await band.find({ type: 'Text', text: /fleet/ })).toBeUndefined()
  expect((await band.find({ type: 'Text', text: /engine/ }))?.text).toBe('engine')
  await band.unmount()
})

const polling = async (...[$, on]: Parameters<TestBody>) => {
  const clock = mock.clock(on, { now: 1_000_000 })
  const toasts: string[] = []
  const players: string[] = []
  let output = SNAPSHOT_OUTPUT

  mock.store(on)
  mock.env(on, { HOME: '/home/x' })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('fs.stat', () => ({ value: { kind: 'file', size: 1, mtimeMs: 0, isLink: false } }))
  on('process.run', (_, e) => {
    if (e.argv[0] === 'uname') {
      return ran('Linux\n')
    }
    if (e.argv[0] === 'paplay') {
      players.push(e.argv[1] ?? '')

      return ran('')
    }

    return ran(output)
  })
  on('command.register', () => ({ value: { command: 'fleet' } }))
  on('session.model', () => ({ value: 'claude-opus-4-7' }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', (_, e) => {
    toasts.push(e.text)

    return { value: undefined }
  })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await clock.settle()

  return {
    toasts,
    players,
    change: async (next: unknown[]) => {
      output = JSON.stringify(snapshot(next))
      await clock.advance(20_000)
    },
  }
}

test('a PR is announced once, silently, and never again', async ($, on) => {
  const fleet = await polling($, on)
  const ready = [
    task('alpha', 'working', { pr: { url: 'https://github.com/o/r/pull/12' } }),
    task('beta', 'blocked'),
  ]

  expect(fleet.toasts).toEqual([])

  await fleet.change(ready)
  await fleet.change(ready)
  await fleet.change(ready)

  expect(fleet.toasts).toEqual(['alpha: PR #12 ready'])
  expect(fleet.players).toEqual([])
})

test('the chime plays only when the option is on', async ($, on) => {
  const quiet = await polling($, on)

  await quiet.change([task('alpha', 'failed'), task('beta', 'blocked')])
  expect(quiet.toasts).toEqual(['alpha failed'])
  expect(quiet.players).toEqual([])
})

test('the chime plays with the sound option', { options: { sound: true } }, async ($, on) => {
  const loud = await polling($, on)

  await loud.change([task('alpha', 'failed'), task('beta', 'blocked')])
  expect(loud.toasts).toEqual(['alpha failed'])
  expect(loud.players).toHaveLength(1)
  expect(loud.players[0]).toMatch(/sounds\/chime\.wav$/)
})

test('a Firstmate worker session never polls or registers the fleet command', async ($, on) => {
  const calls: string[] = []

  mock.clock(on)
  mock.store(on)
  mock.env(on, { HOME: '/home/x', FM_TASK_ID: 'some-task' })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('fs.stat', () => ({ value: { kind: 'file', size: 1, mtimeMs: 0, isLink: false } }))
  on('process.run', (_, e) => {
    calls.push(e.argv.join(' '))

    return ran('Linux\n')
  })
  on('command.register', () => {
    calls.push('command.register')

    return { value: { command: 'fleet' } }
  })
  on('session.model', () => ({ value: 'claude-opus-4-7' }))
  on('ui.status', () => ({ value: undefined }))

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  expect(calls).toEqual(['uname -s'])
})
