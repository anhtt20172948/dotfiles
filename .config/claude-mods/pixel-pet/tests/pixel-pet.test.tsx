import { expect, mock, test } from 'claude-code/testing'

import { INITIAL, REACT_MS, ROAM, SLEEP_MS, caption, shownMood, stats, step } from '../hooks/lib/mood'
import type { PetEvent } from '../hooks/lib/mood'
import { PALETTE, WIDTH, frame, mirror, rows } from '../hooks/lib/sprite'
import type { Pet } from '../types'

const run = (pet: Pet, events: PetEvent[]) => events.reduce(step, pet)

const ticks = (from: number, count: number, every = 400): PetEvent[] =>
  Array.from({ length: count }, (_, i) => ({ type: 'tick', now: from + (i + 1) * every }))

test('two pixel rows make one text row of half blocks, runs merged', async () => {
  const lines = rows(['ko..', 'k.o.'].map(row => row.padEnd(WIDTH, '.')))

  expect(lines).toHaveLength(1)
  expect(lines[0]?.[0]).toEqual({ text: '█', color: PALETTE.k })
  expect(lines[0]?.[1]).toEqual({ text: '▀▄', color: PALETTE.o })
  expect(lines[0]?.[2]).toEqual({ text: ' '.repeat(WIDTH - 3) })
  expect(rows(['ko'.padEnd(WIDTH, '.'), 'ok'.padEnd(WIDTH, '.')])[0]?.[0]).toEqual({
    text: '▀',
    color: PALETTE.k,
    backgroundColor: PALETTE.o,
  })
})

test('without colour the sprite is a silhouette with its eyes cut out', async () => {
  const lines = rows(frame({ isBlinking: false, hasBlush: true, hasTear: true, step: 0 }), true)
  const text = lines.map(line => line.map(segment => segment.text).join(''))

  expect(lines.flat().every(segment => segment.color === undefined && segment.backgroundColor === undefined)).toBe(true)
  // Pixel rows 4 and 5: the eyes on top and a tear under the left one leave a hole.
  expect(text[2]).toBe('██ ██████▄██')
})

test('every frame is the sprite size and mirrors to the same size', async () => {
  const grid = frame({ isBlinking: true, hasBlush: true, hasTear: true, step: 1 })

  expect(grid).toHaveLength(8)
  expect(grid.every(row => row.length === WIDTH)).toBe(true)
  expect(grid.join('')).not.toContain('e')
  expect(mirror(grid)[5]?.[WIDTH - 3]).toBe('b')
  expect(rows(grid)).toHaveLength(4)
})

test('a turn works, celebrates, then settles back to idle', async () => {
  const started = run(INITIAL, [{ type: 'start', now: 0 }])
  const working = run(started, [
    { type: 'prompt', now: 10 },
    { type: 'tool', now: 20, tool: 'Bash' },
  ])
  expect(working).toMatchObject({ mood: 'working', tool: 'Bash', tools: 1 })
  expect(caption('working', working).text).toMatch(/^đang chạy Bash\.+$/)

  const happy = run(working, [
    { type: 'toolDone', now: 30, tool: 'Bash', isError: false },
    { type: 'turn', now: 40, isAborted: false },
  ])
  expect(happy).toMatchObject({ mood: 'happy', tool: null, turns: 1 })

  const settled = run(happy, ticks(40, Math.ceil(REACT_MS / 400)))
  expect(settled.mood).toBe('idle')
  expect(stats(settled)).toBe('1 lượt · 1 tool')
})

test('a failed tool and an interrupted turn make it sad', async () => {
  const failed = run(INITIAL, [
    { type: 'tool', now: 0, tool: 'Bash' },
    { type: 'toolDone', now: 5, tool: 'Bash', isError: true },
  ])
  expect(failed).toMatchObject({ mood: 'sad', errors: 1 })
  expect(caption('sad', failed).text).toBe('Bash lỗi rồi…')
  expect(stats(failed)).toBe('0 lượt · 1 tool · 1 lỗi')

  const aborted = run(INITIAL, [{ type: 'turn', now: 0, isAborted: true }])
  expect(caption(aborted.mood, aborted).text).toBe('bị ngắt rồi…')
})

test('idle it walks within its room and falls asleep, a prompt wakes it', async () => {
  const walked = run(run(INITIAL, [{ type: 'start', now: 0 }]), ticks(0, 200))
  expect(walked.x).toBeGreaterThanOrEqual(0)
  expect(walked.x).toBeLessThanOrEqual(ROAM)

  const asleep = run(walked, [{ type: 'tick', now: SLEEP_MS + 1 }])
  expect(asleep.mood).toBe('sleep')
  expect(run(asleep, [{ type: 'prompt', now: SLEEP_MS + 2 }]).mood).toBe('working')
})

test('a running turn shows as work, a stale working mood as idle', async () => {
  expect(shownMood({ ...INITIAL, mood: 'sleep' }, true)).toBe('working')
  expect(shownMood({ ...INITIAL, mood: 'working' }, false)).toBe('idle')
  expect(shownMood({ ...INITIAL, mood: 'happy' }, false)).toBe('happy')
})

const BAND = {
  plugin: 'pixel-pet',
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

test('the band draws the pet above what lies beneath, and /pet hides it', async ($, on) => {
  mock.clock(on)
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', () => ({ value: { command: 'pet' } }))
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)

    return <Text>engine</Text>
  })

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  for (const surface of ['terminal', 'desktop'] as const) {
    const band = await $.ui.mount({ ...BAND, surface })
    expect((await band.find({ type: 'Text', text: /Mochi/ }))?.text).toMatch(/Mochi · đang chờ bạn/)
    expect((await band.find({ type: 'Text', text: /lượt/ }))?.text).toBe('0 lượt · 0 tool')
    expect((await band.find({ type: 'Text', text: /engine/ }))?.text).toBe('engine')
    await band.unmount()
  }

  const toggled = await $.command.run({
    command: 'pet',
    args: '',
    origin: { kind: 'composer' },
    presentation: { isFullscreen: false, columns: 100 },
  })
  expect(toggled.text).toMatch(/Mochi đi ngủ/)
  const hidden = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await hidden.find({ type: 'Text', text: /Mochi/ })).toBeUndefined()
  expect((await hidden.find({ type: 'Text', text: /engine/ }))?.text).toBe('engine')
  await hidden.unmount()
})

test('the name option names the pet', { options: { name: 'Bơ' } }, async ($, on) => {
  mock.clock(on)
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', () => ({ value: { command: 'pet' } }))
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)

    return <Text>engine</Text>
  })

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await band.find({ type: 'Text', text: /Bơ/ }))?.text).toMatch(/^Bơ · /)
  await band.unmount()
})

test('NO_COLOR draws the pet without colour', async ($, on) => {
  mock.clock(on)
  mock.env(on, { NO_COLOR: '1' })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', () => ({ value: { command: 'pet' } }))
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)

    return <Text>engine</Text>
  })

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  const block = await band.find({ type: 'Text', text: /█/ })
  expect(block).toBeDefined()
  expect(block?.props.color).toBeUndefined()
  await band.unmount()
})
