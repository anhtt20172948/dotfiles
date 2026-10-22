import { expect, test } from 'claude-code/testing'
import { clockText, clip, contextText, effortText, gauge, statusLine } from '../hooks/format'
import { activityLane, dashboardLayout, crewState, fleetModels, laneGeometry, recentLog, toggleExpanded } from '../hooks/dashboard'

test('layout keeps cards readable and inline output bounded', () => {
  expect(dashboardLayout(40, 'dock', 1)).toMatchObject({ mode: 'cards', columns: 1, cardWidth: 40 })
  expect(dashboardLayout(80, 'dock', 3).mode).toBe('lanes')
  expect(dashboardLayout(120, 'dock', 3)).toMatchObject({ mode: 'cards', columns: 3, cardWidth: 39 })
  expect(dashboardLayout(120, 'inline', 8)).toMatchObject({ mode: 'mini', shown: 3 })
})

test('gauges clamp and context never invents a model window', () => {
  expect(gauge(150, 5)).toBe('▰▰▰▰▰')
  expect(gauge(-10, 5)).toBe('▱▱▱▱▱')
  expect(contextText({ context: 50000, contextWindow: null })).toBe('ctx 50k · window not recorded')
  expect(contextText({ context: 50000, contextWindow: null, contextModel: 'claude-test' })).toBe('ctx 50k · window n/a for test')
  expect(contextText({ context: 0, contextWindow: null, contextModel: '' })).toBe('ctx - · no request yet')
  expect(contextText({ context: 50000, contextWindow: 200000 })).toBe('ctx ▰▰▱▱▱▱▱▱ 25% · 50k/200k')
  expect(effortText('high')).toBe('effort ▰▰▰▱ high')
  expect(effortText('default')).toBe('effort default')
  expect(effortText('xhigh')).toBe('effort ▰▰▰▰ xhigh')
  expect(clip('●   nested', 40)).toBe('●   nested')
})

test('lanes share the same minute axis and omit old or future activity', () => {
  const now = 90 * 60000
  expect(activityLane([{ minute: 89, count: 2 }, { minute: 90, count: 1 }], now, 4)).toBe('··▰▰')
  expect(activityLane([{ minute: 80, count: 1 }, { minute: 91, count: 1 }], now, 4)).toBe('····')
})

test('fleet reducers merge models and keep a bounded chronological crew log', () => {
  const crew = [
    { id: 'a', home: '/one', harness: 'claude', models: { opus: 2 }, events: [{ at: 3, kind: 'tool', text: 'Read' }] },
    { id: 'b', home: '/two', harness: 'codex', models: { opus: 1, gpt: 4 }, events: [{ at: 5, kind: 'status', text: 'done' }] },
  ] as const
  expect(fleetModels(crew)).toEqual([['gpt', 4], ['opus', 3]])
  expect(recentLog(crew, 1).map(e => e.text)).toEqual(['done'])
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

test('axis and lane cells share an explicit gutter and a gap after the name', () => {
  for (const width of [40, 80, 120]) {
    const geometry = laneGeometry(width)
    expect(geometry.offset).toBe(geometry.markWidth + geometry.nameWidth + geometry.gap)
    expect(geometry.gap).toBe(1)
    expect(geometry.axis.length).toBe(geometry.cells)
    expect(geometry.axis.endsWith('now')).toBe(true)
    expect(geometry.offset + geometry.cells <= width).toBe(true)
  }
})

test('latest protocol state overrides fresh transcript activity', () => {
  const now = 1000000
  const state = (status: string, lastAt = now - 60000) => crewState({ status, lastAt }, now)
  expect(state('done [at=900]: committed')).toMatchObject({ mark: '✓', label: 'done · waiting for firstmate', color: 'merged' })
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
