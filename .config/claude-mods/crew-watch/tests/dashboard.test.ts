import { expect, test } from 'claude-code/testing'
import { clip, contextText, effortText, gauge } from '../hooks/format'
import { activityLane, dashboardLayout, fleetModels, normalizeMember, recentLog, toggleExpanded } from '../hooks/dashboard'

test('layout keeps cards readable and inline output bounded', () => {
  expect(dashboardLayout(40, 'dock', 1)).toMatchObject({ mode: 'cards', columns: 1, cardWidth: 40 })
  expect(dashboardLayout(80, 'dock', 3).mode).toBe('lanes')
  expect(dashboardLayout(120, 'dock', 3)).toMatchObject({ mode: 'cards', columns: 3, cardWidth: 39 })
  expect(dashboardLayout(120, 'inline', 8)).toMatchObject({ mode: 'mini', shown: 3 })
})

test('gauges clamp and context never invents a model window', () => {
  expect(gauge(150, 5)).toBe('▰▰▰▰▰')
  expect(gauge(-10, 5)).toBe('▱▱▱▱▱')
  expect(contextText({ context: 50000, contextWindow: null })).toBe('ctx 50k · window unknown')
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

test('reports from a pre-dashboard session retain a safe fallback during reload', () => {
  const legacy = { id: 'a', topTools: [{ name: 'Read', count: 2 }] } as import('../types').CrewMember
  expect(normalizeMember(legacy)).toMatchObject({ description: 'a', contextWindow: null, events: [], activity: [], tools: { Read: 2 } })
})
