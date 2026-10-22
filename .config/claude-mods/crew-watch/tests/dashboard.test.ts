import { expect, test } from 'claude-code/testing'
import { clockText, clip, effortText, gauge, statusLine } from '../hooks/format'
import { activityChart, activityCounts, crewState, fleetModels, toggleExpanded } from '../hooks/dashboard'
import { contextLine } from '../hooks/view'

test('gauges clamp and context never invents a model window', () => {
  expect(gauge(150, 5)).toBe('▰▰▰▰▰')
  expect(gauge(-10, 5)).toBe('▱▱▱▱▱')
  expect(contextLine({ context: 50000, contextWindow: null, contextModel: '' }, 8)).toBe('Ctx 50k · window not recorded')
  expect(contextLine({ context: 50000, contextWindow: null, contextModel: 'claude-test' }, 8)).toBe('Ctx 50k · window n/a for test')
  expect(contextLine({ context: 0, contextWindow: null, contextModel: '' }, 8)).toBe('Ctx — · no request yet')
  expect(contextLine({ context: 50000, contextWindow: 200000, contextModel: '' }, 8)).toBe('Ctx ▰▰▱▱▱▱▱▱ 25% · 50k/200k')
  expect(effortText('high')).toBe('effort ▰▰▰▱ high')
  expect(effortText('default')).toBe('effort default')
  expect(effortText('xhigh')).toBe('effort ▰▰▰▰ xhigh')
  expect(clip('●   nested', 40)).toBe('●   nested')
})

test('activity adds every crewmate per minute, ends in the current minute and leaves out old or future buckets', () => {
  const now = 90 * 60000 + 30_000
  const a = [{ minute: 89, count: 2 }, { minute: 90, count: 1 }, { minute: 80, count: 9 }]
  const b = [{ minute: 90, count: 3 }, { minute: 91, count: 5 }, { minute: 88, count: 0 }]
  expect(activityCounts([a, b], now, 4)).toEqual([0, 0, 2, 4])
  expect(activityCounts([], now, 3)).toEqual([0, 0, 0])
  // An hour at most, one minute at least.
  expect(activityCounts([a], now, 90).length).toBe(60)
  expect(activityCounts([a], now, 0)).toEqual([1])
  expect(a[0]?.count).toBe(2)
})

test('the chart scales bars to the busiest minute and keeps a busy minute above the quiet baseline', () => {
  const chart = activityChart([0, 1, 4, 8], 2)
  // Top row first: 8 fills both rows, 4 the bottom one, 1 of 8 still two eighths, 0 the ▁ baseline.
  expect(chart.map(col => col.glyphs.join(''))).toEqual([' ▁', ' ▂', ' █', '██'])
  expect(chart.map(col => col.busy)).toEqual([false, true, true, true])
  expect(activityChart([0, 3, 6], 1).map(col => col.glyphs.join(''))).toEqual(['▁', '▄', '█'])
  expect(activityChart([0, 0], 2).map(col => col.glyphs.join(''))).toEqual([' ▁', ' ▁'])
})

test('fleet reducers merge models and toggle one open crewmate', () => {
  const crew = [
    { id: 'a', home: '/one', harness: 'claude', models: { opus: 2 }, events: [{ at: 3, kind: 'tool', text: 'Read' }] },
    { id: 'b', home: '/two', harness: 'codex', models: { opus: 1, gpt: 4 }, events: [{ at: 5, kind: 'status', text: 'done' }] },
  ] as const
  expect(fleetModels(crew)).toEqual([['gpt', 4], ['opus', 3]])
  expect(toggleExpanded(null, '/one:a')).toBe('/one:a')
  expect(toggleExpanded('/one:a', '/one:a')).toBe(null)
  expect(crew[0].models.opus).toBe(2)
})

test('clocks use local wall time and can be checked in a fixed timezone', () => {
  const at = Date.parse('2026-10-21T17:23:04Z')
  expect(clockText(at, 'Asia/Ho_Chi_Minh')).toBe('00:23:04')
  expect(clockText(at, 'America/New_York')).toBe('13:23:04')
  const local = new Date(at)
  expect(clockText(at)).toBe([local.getHours(), local.getMinutes(), local.getSeconds()].map(n => String(n).padStart(2, '0')).join(':'))
})

test('latest protocol state overrides fresh transcript activity', () => {
  const now = 1000000
  const state = (status: string, lastAt = now - 60000) => crewState({ status, lastAt }, now)
  expect(state('done [at=900]: committed')).toMatchObject({ mark: '✓', label: 'done · waiting for firstmate', color: 'success' })
  expect(state('blocked [at=900]: needs help')).toMatchObject({ label: 'blocked', color: 'error' })
  expect(state('paused [at=900]: validating')).toMatchObject({ label: 'paused / waiting', color: 'permission' })
  expect(state('waiting: CI')).toMatchObject({ label: 'paused / waiting' })
  expect(state('working [at=900]: tests')).toMatchObject({ label: 'working', color: 'success' })
  expect(state('working: tests', now - 300000)).toMatchObject({ label: 'quiet', color: 'warning' })
  expect(state('working: tests', 0)).toMatchObject({ label: 'stale', color: 'subtle' })
  expect(state('resolved [at=900]: done is only in the detail')).toMatchObject({ label: 'active' })
  const done = { lastAt: now - 1000, status: 'done [at=900]: waiting' } as import('../types').CrewMember
  expect(statusLine([done], { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, requests: 0, reasoning: 0, toolCalls: 0 }, now)).toContain('(0 active)')
})
