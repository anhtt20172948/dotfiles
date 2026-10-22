import { expect, test } from 'claude-code/testing'

import type { CrewEvent, CrewReport, QuotaReading } from '../types'
import { cells, clip, pad } from '../hooks/format'
import {
  NONE, STALE_READING_MS, accountsOf, contextExact, contextLine, effectiveFilter, filterLabel, filterLogs, headingParts, isActive, kpiText, layoutFor,
  logEntries, logTag, nextFilter, quotaBrief, quotaEntries, quotaFigure, sourceState, statusOf, untilText, usageLine,
} from '../hooks/view'

const NOW = 1_800_000_000_000

const reading = (over: Partial<QuotaReading> = {}): QuotaReading => ({
  provider: 'claude', account: 'andang', accountKnown: true, scope: 'seven_day', plan: 'Max 5x', login: 'token', percent: 35,
  observedAt: NOW - 240_000, source: 'session', resetsAt: NOW + 2 * 86_400_000 + 4 * 3_600_000, windowMs: 7 * 86_400_000,
  windowStart: NOW - 5 * 86_400_000, windowStartKnown: true, stale: false, reset: false, indexed: true, localCost: 1e6, sinceCost: null,
  forecast: null, confidence: { label: 'uncalibrated', samples: 0 }, ...over,
})

const figure = { share: 0.5, percent: null, settled: null, open: null, since: null, basis: 'raw' as const }
const quotaOf = { session: figure, tools: figure }

test('a status reads as a glyph and a word; no activity and no status line is UNKNOWN, not stale', () => {
  expect(statusOf({ lastAt: NOW - 10_000, status: 'working [at=1]: tests' }, NOW)).toMatchObject({ mark: '●', label: 'WORKING' })
  expect(statusOf({ lastAt: NOW - 10_000, status: '' }, NOW)).toMatchObject({ mark: '●', label: 'ACTIVE' })
  expect(statusOf({ lastAt: NOW - 300_000, status: '' }, NOW)).toMatchObject({ mark: '◐', label: 'QUIET' })
  expect(statusOf({ lastAt: NOW - 3_600_000, status: '' }, NOW)).toMatchObject({ mark: '○', label: 'STALE' })
  expect(statusOf({ lastAt: NOW, status: 'done [at=1]: PR open' }, NOW)).toMatchObject({ mark: '✓', label: 'DONE' })
  expect(statusOf({ lastAt: NOW, status: 'blocked [at=1]: help' }, NOW)).toMatchObject({ mark: '×', label: 'BLOCKED', color: 'error' })
  expect(statusOf({ lastAt: NOW, status: 'paused [at=1]: CI' }, NOW)).toMatchObject({ mark: '◷', label: 'PAUSED' })
  expect(statusOf({ lastAt: 0, status: '' }, NOW)).toMatchObject({ mark: '?', label: 'UNKNOWN' })
  // Every label differs in its glyph too, so a monochrome terminal still tells them apart.
  const marks = ['working', '', 'blocked [at=1]: x', 'done [at=1]: x', 'paused [at=1]: x'].map(status => statusOf({ lastAt: NOW, status }, NOW).mark)
  expect(new Set(marks.slice(1)).size).toBe(4)
})

test('the source state is loading, live, stale or error, and a failed read never looks fresh', () => {
  const stale = 30_000
  expect(sourceState(null, null, NOW, stale)).toMatchObject({ state: 'loading', label: 'LOADING' })
  expect(sourceState(null, { at: NOW, failed: true }, NOW, stale)).toMatchObject({ state: 'error', label: 'SOURCE ERROR', age: 'no data yet' })
  expect(sourceState({ generatedAt: NOW - 4_000 }, { at: NOW, failed: false }, NOW, stale)).toMatchObject({ state: 'live', label: 'LIVE', age: 'updated 4s ago' })
  expect(sourceState({ generatedAt: NOW - 45_000 }, { at: NOW, failed: false }, NOW, stale)).toMatchObject({ state: 'stale', label: 'STALE', age: 'updated 45s ago' })
  expect(sourceState({ generatedAt: NOW - 45_000 }, { at: NOW, failed: true }, NOW, stale)).toMatchObject({ state: 'error', age: 'last good 45s ago' })
  // A clock behind the report's never shows a negative age.
  expect(sourceState({ generatedAt: NOW + 9_000 }, null, NOW, stale).age).toBe('updated 0s ago')
})

test('agents take two columns from 110 cells, stack below, list as rows below 70 or when many', () => {
  expect(layoutFor(120, 40, 2, 'dock')).toMatchObject({ mode: 'cards', columns: 2, cardWidth: 59, logRows: 5 })
  expect(layoutFor(110, 36, 2, 'dock')).toMatchObject({ mode: 'cards', columns: 2, cardWidth: 54 })
  expect(layoutFor(109, 36, 2, 'dock')).toMatchObject({ mode: 'cards', columns: 1, cardWidth: 109 })
  expect(layoutFor(80, 32, 2, 'dock')).toMatchObject({ mode: 'cards', columns: 1, cardWidth: 80, logRows: 3 })
  expect(layoutFor(120, 40, 1, 'dock')).toMatchObject({ mode: 'cards', columns: 1, cardWidth: 120 })
  expect(layoutFor(60, 24, 2, 'dock')).toMatchObject({ mode: 'rows', condensed: true })
  expect(layoutFor(120, 40, 5, 'dock').mode).toBe('rows')
  expect(layoutFor(80, 32, 4, 'dock').mode).toBe('rows')
  expect(layoutFor(120, 20, 2, 'dock')).toMatchObject({ mode: 'rows', logRows: 0, activityCollapsed: true })
  expect(layoutFor(200, 60, 8, 'inline').mode).toBe('mini')
  // Boundaries: 24 and 36 rows, four cards in two columns and three in one, 70 cells, an empty crew.
  expect(layoutFor(120, 23, 2, 'dock')).toMatchObject({ mode: 'rows', logRows: 0 })
  expect(layoutFor(120, 24, 2, 'dock')).toMatchObject({ mode: 'cards', logRows: 3, activityCollapsed: false })
  expect(layoutFor(120, 35, 2, 'dock').logRows).toBe(3)
  expect(layoutFor(120, 36, 2, 'dock').logRows).toBe(5)
  expect(layoutFor(120, 40, 4, 'dock')).toMatchObject({ mode: 'cards', columns: 2 })
  expect(layoutFor(80, 40, 3, 'dock')).toMatchObject({ mode: 'cards', columns: 1 })
  expect(layoutFor(70, 40, 2, 'dock')).toMatchObject({ mode: 'cards', condensed: false })
  expect(layoutFor(69, 40, 2, 'dock')).toMatchObject({ mode: 'rows', condensed: true })
  expect(layoutFor(120, 40, 0, 'dock')).toMatchObject({ mode: 'cards', columns: 1 })
})

test('headings never pass the width and keep the title before the hint', () => {
  for (const width of [8, 20, 60, 120]) {
    const part = headingParts('QUOTA & LIMITS', 'per account · weekly window', width)
    expect(cells(part.lead + part.title + part.hint + part.rule) <= width).toBe(true)
  }
  expect(headingParts('OVERVIEW', 'fleet', 30)).toEqual({ lead: '── ', title: 'OVERVIEW', hint: ' · fleet', rule: ' ' + '─'.repeat(10) })
})

test('the fleet KPIs say what they count and show a dash, not zero, before any report', () => {
  const totals = { requests: 27, input: 37_000, output: 9_100, cacheRead: 1_930_000, cacheWrite: 85_000, reasoning: 2_700, toolCalls: 30 }
  expect(kpiText(totals, false)).toBe('Tokens 2.06M · Requests 27 · Tool calls 30 · Cache 94%')
  expect(kpiText(totals, true)).toBe('Tok 2.06M · Req 27 · Tools 30 · Cache 94%')
  expect(kpiText(null, false)).toBe(`Tokens ${NONE} · Requests ${NONE} · Tool calls ${NONE} · Cache ${NONE}`)
  // A real zero stays zero; a cache share with no input is undefined, not 0%.
  expect(kpiText({ ...totals, requests: 0, input: 0, cacheRead: 0, cacheWrite: 0, output: 0, toolCalls: 0 }, false)).toBe(`Tokens 0 · Requests 0 · Tool calls 0 · Cache ${NONE}`)
})

test('context is shown only against a known window; zero, missing and over-full windows never produce NaN', () => {
  expect(contextLine({ context: 109_000, contextWindow: 1_000_000, contextModel: 'claude-sonnet-5-5' }, 12)).toBe('Ctx ▰▱▱▱▱▱▱▱▱▱▱▱ 11% · 109k/1.00M')
  expect(contextLine({ context: 44_000, contextWindow: 828_000, contextModel: 'gpt' }, 6)).toBe('Ctx ▱▱▱▱▱▱ 5% · 44k/828k')
  expect(contextLine({ context: 1_200, contextWindow: 0, contextModel: '' }, 6)).toBe('Ctx 1.2k · window not recorded')
  expect(contextLine({ context: 5_000, contextWindow: null, contextModel: 'mystery' }, 6)).toBe('Ctx 5.0k · window n/a for mystery')
  expect(contextLine({ context: 260_000, contextWindow: 200_000, contextModel: 'x' }, 6)).toBe('Ctx ▰▰▰▰▰▰ 130% · 260k/200k · over window')
  expect(contextExact({ context: 88_000, contextWindow: 200_000, contextModel: 'm', windowSource: 'transcript' })).toBe('88,000 / 200,000 tokens (44.0%) · window from transcript')
  expect(contextExact({ context: 88_000, contextWindow: null, contextModel: '', windowSource: '' })).toBe('88,000 tokens · window unknown')
  for (const text of [contextLine({ context: 1, contextWindow: 0, contextModel: '' }, 6), contextExact({ context: 1, contextWindow: 0, contextModel: '', windowSource: '' })]) {
    expect(text.includes('NaN') || text.includes('Infinity')).toBe(false)
  }
})

test('usage of a harness whose logs cannot be read shows dashes, never zeros', () => {
  const m = { readable: false, requests: 0, toolCalls: 0, input: 0, output: 0, harness: 'pi' }
  expect(usageLine(m)).toBe(`${NONE} req · ${NONE} tools · pi logs not readable`)
  expect(usageLine({ ...m, readable: true, requests: 19, toolCalls: 22, input: 38_000, output: 7_300, harness: 'claude' })).toBe('19 req · 22 tools · in 38k / out 7.3k')
  expect(usageLine({ ...m, readable: true, requests: 19, toolCalls: 22 }, true)).toBe('19 req · 22 tools')
  expect(contextLine({ context: 0, contextWindow: null, contextModel: '', readable: false }, 6)).toBe(`Ctx ${NONE} · logs not readable`)
  expect(accountsOf({ quota: {}, readable: false }, {})).toBe(`acct ${NONE} · logs not readable`)
  expect(isActive({ lastAt: NOW - 1_000, status: '' }, NOW)).toBe(true)
  expect(isActive({ lastAt: NOW - 1_000, status: 'blocked [at=1]: x' }, NOW)).toBe(false)
  expect(isActive({ lastAt: NOW - 300_000, status: 'working: x' }, NOW)).toBe(false)
})

test('a crewmate names the account its usage went to, or says it is unknown', () => {
  const readings = {
    'claude|andang|seven_day': reading(),
    'claude|unknown|seven_day': reading({ account: 'unknown', accountKnown: false }),
    'codex|codex-60305a97|codex:10080m': reading({ provider: 'codex', account: 'codex-60305a97' }),
  }
  expect(accountsOf({ quota: { 'claude|andang|seven_day': quotaOf } }, readings)).toBe('acct claude andang')
  expect(accountsOf({ quota: { 'claude|unknown|seven_day': quotaOf } }, readings)).toBe('acct claude account unknown')
  expect(accountsOf({ quota: { 'codex|codex-60305a97|codex:10080m': quotaOf } }, readings)).toBe('acct codex 60305a97')
  expect(accountsOf({ quota: { 'claude|andang|seven_day': quotaOf, 'claude|thanhnv|seven_day': quotaOf } }, readings)).toBe('acct claude andang + claude thanhnv')
  expect(accountsOf({ quota: {} }, readings)).toBe(`acct ${NONE} · no usage in this week's window`)
})

test('a weekly figure is the measured vendor percent with its age and reset, or why there is none', () => {
  expect(quotaFigure(reading(), NOW, 6)).toEqual({ text: 'week ▰▰▱▱▱▱ 35% · measured 4m ago · resets in 2d 4h', tone: 'text' })
  expect(quotaFigure(reading({ stale: true, observedAt: NOW - 3 * 3_600_000 }), NOW, 6).text).toBe('week ▰▰▱▱▱▱ 35% · stale 3h0m ago · resets in 2d 4h')
  expect(quotaFigure(reading({ stale: true, observedAt: null, resetsAt: null }), NOW, 6)).toEqual({ text: 'week ▰▰▱▱▱▱ 35% · stale, age unknown', tone: 'warning' })
  expect(quotaFigure(reading({ percent: null }), NOW, 6).text).toBe(`week % ${NONE}: no reading`)
  expect(quotaFigure(reading({ percent: null, reset: true }), NOW, 6).text).toBe(`week % ${NONE}: window reset`)
  expect(quotaFigure(reading({ account: 'unknown', accountKnown: false, percent: null }), NOW, 6).text).toBe(`week % ${NONE}: account unknown`)
  expect(quotaFigure(reading({ indexed: false }), NOW, 6).text).toBe('indexing local logs…')
  // A reset already passed is not shown as a future one.
  expect(quotaFigure(reading({ resetsAt: NOW - 1 }), NOW, 6).text).toBe('week ▰▰▱▱▱▱ 35% · measured 4m ago')
  // Past half an hour a reading is stale even when the report that carried it called it current.
  expect(quotaFigure(reading({ resetsAt: null }), NOW - 240_000 + STALE_READING_MS + 1, 6)).toEqual({ text: 'week ▰▰▱▱▱▱ 35% · stale 30m ago', tone: 'warning' })
  expect([2 * 86_400_000 + 4 * 3_600_000 + 59_000, 3 * 3_600_000 + 12 * 60_000, 59.9 * 60_000, 30_000].map(untilText)).toEqual(['2d 4h', '3h 12m', '59m', '<1m'])
})

test('every account stays its own quota entry: two Claude accounts and one Codex account, never summed', () => {
  const report = {
    crew: [{ quota: { 'claude|unknown|seven_day': quotaOf } }],
    quota: {
      fleet: {},
      readings: {
        'codex|codex-60305a97|codex:10080m': reading({ provider: 'codex', account: 'codex-60305a97', scope: 'codex:10080m', plan: 'Plus', percent: 30 }),
        'claude|thanhnv|seven_day': reading({ account: 'thanhnv', percent: null, plan: '' }),
        'claude|andang|seven_day': reading(),
        'claude|unknown|seven_day': reading({ account: 'unknown', accountKnown: false, percent: null }),
        'codex|unknown|weekly': reading({ provider: 'codex', account: 'unknown', accountKnown: false, percent: null }),
      },
    },
  } as unknown as Pick<CrewReport, 'quota' | 'crew'>
  // Known accounts always; an unknown one only where the crew's usage went to it.
  expect(quotaEntries(report).map(([key]) => key)).toEqual(['claude|andang|seven_day', 'claude|thanhnv|seven_day', 'claude|unknown|seven_day', 'codex|codex-60305a97|codex:10080m'])
  expect(quotaBrief(report, NOW)).toEqual([`claude week: andang 35% · thanhnv ${NONE} · unknown ${NONE}`, 'codex week: 60305a97 30%'])
  expect(quotaBrief({ crew: [], quota: { fleet: {}, readings: {} } }, NOW)).toEqual(['quota: no readings yet'])
  // A reading that has aged past half an hour since the report is stale here too.
  expect(quotaBrief(report, NOW + STALE_READING_MS)).toEqual([`claude week: andang 35% stale · thanhnv ${NONE} · unknown ${NONE}`, 'codex week: 60305a97 30% stale'])
})

const event = (at: number, kind: CrewEvent['kind'], text: string): CrewEvent => ({ at, kind, text })

test('the log is newest first, tags errors from the status protocol only and keeps ids stable', () => {
  const crew = [
    { home: '/fm', id: 'a', harness: 'claude', events: [event(3, 'tool', 'Bash: npm test'), event(5, 'status', 'blocked [at=5]: needs a decision')] },
    { home: '/fm', id: 'b', harness: 'codex', events: [event(4, 'tool', 'exec: uv lock --upgrade-package cryptogr…'), event(6, 'status', 'working: error handling in tests')] },
  ]
  const entries = logEntries(crew)
  expect(entries.map(e => e.at)).toEqual([6, 5, 4, 3])
  // Calls of one instant list newest first too, and an event keeps its id when older ones drop off.
  const tied = logEntries([{ home: '/fm', id: 'a', harness: 'claude', events: [event(1, 'tool', 'first'), event(2, 'tool', 'second'), event(2, 'tool', 'third')] }])
  expect(tied.map(e => e.text)).toEqual(['third', 'second', 'first'])
  const later = logEntries([{ home: '/fm', id: 'a', harness: 'claude', events: [event(2, 'tool', 'second'), event(2, 'tool', 'third')] }])
  expect(later.map(e => e.id)).toEqual(tied.slice(0, 2).map(e => e.id))
  expect(new Set(logEntries([{ home: '/fm', id: 'a', harness: 'claude', events: [event(0, 'status', 'x'), event(0, 'status', 'x')] }]).map(e => e.id)).size).toBe(2)
  // "error" inside a working line's text is not a severity; the protocol's state word is.
  expect(entries.map(e => e.level)).toEqual(['info', 'error', 'info', 'info'])
  expect(entries.map(logTag)).toEqual(['◇ STAT', '× ERR ', '▸ TOOL', '▸ TOOL'])
  expect(entries.find(e => e.at === 4)?.sourceTruncated).toBe(true)
  expect(logEntries(crew).map(e => e.id)).toEqual(entries.map(e => e.id))
  expect(filterLogs(entries, 'tools', null).map(e => e.at)).toEqual([4, 3])
  expect(filterLogs(entries, 'status', null).map(e => e.at)).toEqual([6, 5])
  expect(filterLogs(entries, 'errors', null).map(e => e.at)).toEqual([5])
  expect(filterLogs(entries, 'agent', '/fm:b').map(e => e.at)).toEqual([6, 4])
  expect(filterLogs(entries, 'agent', null).length).toBe(4)
  expect(nextFilter('all', false)).toBe('tools')
  expect(nextFilter('errors', false)).toBe('all')
  expect(nextFilter('errors', true)).toBe('agent')
  expect(nextFilter('agent', true)).toBe('all')
  expect(filterLabel('agent', 'b')).toBe('Agent: b')
  // An Agent filter with no open crewmate filters nothing, so it is shown as All.
  expect(effectiveFilter('agent', null)).toBe('all')
  expect(effectiveFilter('agent', '/fm:b')).toBe('agent')
  expect(effectiveFilter('tools', null)).toBe('tools')
  expect(filterLabel('errors', undefined)).toBe('Errors')
})

test('wide and zero-width characters are measured in terminal cells, so clipping never overflows', () => {
  expect(cells('abc')).toBe(3)
  expect(cells('測試')).toBe(4)
  expect(cells('🚀x')).toBe(3)
  expect(cells('é')).toBe(1)
  expect(clip('very-very-long-agent-name-with-unicode-測試', 42)).toBe('very-very-long-agent-name-with-unicode-測…')
  expect(clip('very-very-long-agent-name-with-unicode-測試', 41)).toBe('very-very-long-agent-name-with-unicode-…')
  expect(cells(clip('測試測試測試', 5))).toBe(5)
  expect(clip('測試測試', 4)).toBe('測…')
  expect(cells(pad('測試', 7))).toBe(7)
  expect(clip('abc', 0)).toBe('')
})
