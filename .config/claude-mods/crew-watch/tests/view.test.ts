import { expect, test } from 'claude-code/testing'

import type { CrewEvent, CrewReport, QuotaReading } from '../types'
import { cacheHit, cells, clip, pad, shortPaths, tildeHome, totalTokens } from '../hooks/format'
import {
  KPI_DEFINITIONS, NONE, STALE_READING_MS, accountsOf, cardBorder, contextExact, contextLine, crewCounts, effectiveFilter, filterLabel, filterLogs, fitSegments,
  headingParts, isActive, kpiText, layoutFor, logEntries, logKey, logPreview, nextFilter, quotaBrief, quotaEntries, quotaLine, quotaNames, quotaSource, sourceState,
  statusMessage, statusOf, tokenBar, tokenFormulas, tokenParts, toolTag, untilText,
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

test('a harness whose logs cannot be read shows dashes, never zeros', () => {
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

test('a default quota row is the measured percent, the time to reset and a stale mark, or a dash and why', () => {
  expect(quotaLine(reading(), NOW)).toEqual({ percent: 35, figure: '35%', reset: '↻ 2d 4h', note: '', tone: 'text' })
  expect(quotaLine(reading({ stale: true, observedAt: NOW - 3 * 3_600_000 }), NOW)).toEqual({ percent: 35, figure: '35%', reset: '↻ 2d 4h', note: '◷ stale', tone: 'warning' })
  expect(quotaLine(reading({ stale: true, observedAt: null, resetsAt: null }), NOW)).toMatchObject({ reset: '', note: '◷ stale' })
  expect(quotaLine(reading({ percent: null }), NOW)).toEqual({ percent: null, figure: NONE, reset: '↻ 2d 4h', note: 'no reading', tone: 'subtle' })
  expect(quotaLine(reading({ percent: null, reset: true }), NOW).note).toBe('window reset')
  expect(quotaLine(reading({ account: 'unknown', accountKnown: false, percent: null }), NOW)).toMatchObject({ figure: NONE, note: 'account unknown' })
  expect(quotaLine(reading({ indexed: false }), NOW)).toMatchObject({ figure: NONE, note: 'indexing local logs…' })
  // A reset already passed is not shown as a future one.
  expect(quotaLine(reading({ resetsAt: NOW - 1 }), NOW).reset).toBe('')
  // Past half an hour a reading is stale even when the report that carried it called it current.
  expect(quotaLine(reading({ resetsAt: null }), NOW - 240_000 + STALE_READING_MS + 1)).toMatchObject({ note: '◷ stale', tone: 'warning' })
  // The notes (i) carry what the row leaves out: the reading's age and source, or why there is none.
  expect(quotaSource(reading(), NOW)).toEqual({ text: 'week 35% measured 4m ago · source this session', tone: 'subtle' })
  expect(quotaSource(reading({ stale: true, observedAt: NOW - 3 * 3_600_000, source: 'history' }), NOW)).toEqual({ text: 'week 35% stale 3h0m ago · source reading history', tone: 'warning' })
  expect(quotaSource(reading({ observedAt: null, stale: true }), NOW).text).toBe('week 35% stale, age unknown · source this session')
  expect(quotaSource(reading({ percent: null }), NOW).text).toBe(`week % ${NONE}: no reading yet`)
  expect(quotaSource(reading({ percent: null, reset: true }), NOW).text).toBe(`week % ${NONE}: the window reset since the last reading`)
  expect(quotaSource(reading({ account: 'unknown', accountKnown: false, percent: null }), NOW).text).toBe(`week % ${NONE}: no account could be tied to this usage`)
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
  expect(entries.map(e => logPreview(e).tag)).toEqual(['STAT', '× ERR', 'EXEC', 'BASH'])
  expect(new Set(entries.map(logKey)).size).toBe(4)
  expect(logKey(entries[0] as (typeof entries)[number])).toMatch(/^log-[0-9a-z]+$/)
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

// The captain's screenshot of crew-demo-scout read "cache 94%" beside "in 24 · read 828k · write 57k". Its
// transcript holds 24 uncached input tokens, not 24k: the formula was right and the bare "24" misled.
const SCOUT = { requests: 12, input: 24, output: 9_066, cacheRead: 827_917, cacheWrite: 57_268, reasoning: 0, toolCalls: 21 }

test('Cache is cache read over all input and Tokens adds the four parts once, thinking inside output', () => {
  expect(cacheHit(SCOUT)).toBe('94%')
  // 827,917 / (24 + 827,917 + 57,268) = 93.53%; with 24k uncached input it would be 91.1%.
  expect(cacheHit({ ...SCOUT, input: 24_000 })).toBe('91%')
  expect(totalTokens(SCOUT)).toBe(894_275)
  // Thinking is part of output as the vendors bill it: reporting it never grows Tokens.
  expect(totalTokens({ ...SCOUT, reasoning: 5_000 } as typeof SCOUT)).toBe(894_275)
  expect(kpiText(SCOUT, false)).toBe('Tokens 894k · Requests 12 · Tool calls 21 · Cache 94%')
  expect(tokenFormulas(SCOUT)).toEqual([
    'Tokens 894,275 = uncached in 24 + cache read 827,917 + cache write 57,268 + out 9,066',
    'Cache 94% = cache read 827,917 / (uncached in 24 + cache read 827,917 + cache write 57,268) = 93.5%',
    'thinking not reported apart from out',
  ])
  expect(tokenFormulas({ ...SCOUT, reasoning: 2_700 })[2]).toBe('thinking 2,700, already counted in out')
  expect(tokenFormulas({ ...SCOUT, input: 0, cacheRead: 0, cacheWrite: 0 })[1]).toBe(`Cache ${NONE}: no input tokens yet`)
  expect(KPI_DEFINITIONS).toContain('Tokens = uncached input + cache read + cache write + output')
  expect(KPI_DEFINITIONS).toContain('thinking is part of output, so it is not added again')
  expect(KPI_DEFINITIONS).toContain('Cache = cache read / (uncached input + cache read + cache write)')
  // The legend names the uncached part, so a small count is never read as a share of the others.
  expect(tokenParts(SCOUT).map(p => p.label)).toEqual(['read', 'write', 'out', 'uncached in'])
  expect(tokenParts(SCOUT).reduce((n, p) => n + p.value, 0)).toBe(totalTokens(SCOUT))
})

test('the token bar fills its width in proportion and keeps a cell for every part used', () => {
  const bar = tokenBar(tokenParts(SCOUT), 60)
  expect(bar.map(s => s.text.length)).toEqual([53, 5, 1, 1])
  expect(bar.map(s => s.text[0])).toEqual(['█', '▓', '▒', '░'])
  expect(bar.reduce((n, s) => n + s.text.length, 0)).toBe(60)
  // An unused part draws nothing; nothing used draws no bar; too narrow for every part, shares alone.
  expect(tokenBar(tokenParts({ input: 0, output: 10, cacheRead: 30, cacheWrite: 0 }), 8).map(s => s.text)).toEqual(['██████', '▒▒'])
  expect(tokenBar(tokenParts({ input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }), 20)).toEqual([])
  expect(tokenBar(tokenParts(SCOUT), 2).reduce((n, s) => n + s.text.length, 0)).toBe(2)
})

test('each account has its own row name: Claude by account, Codex by plan unless two would match', () => {
  const entries: [string, QuotaReading][] = [
    ['claude|andang|seven_day', reading()],
    ['claude|unknown|seven_day', reading({ account: 'unknown', accountKnown: false })],
    ['codex|codex-60305a97|codex:10080m', reading({ provider: 'codex', account: 'codex-60305a97', plan: 'Plus' })],
  ]
  expect([...quotaNames(entries).values()]).toEqual(['claude andang', 'claude unknown', 'codex Plus'])
  const twins: [string, QuotaReading][] = [...entries, ['codex|codex-9f00aa11|codex:10080m', reading({ provider: 'codex', account: 'codex-9f00aa11', plan: 'Plus' })]]
  expect([...quotaNames(twins).values()].slice(2)).toEqual(['codex 60305a97', 'codex 9f00aa11'])
  expect(quotaNames([['codex|codex-1|w', reading({ provider: 'codex', account: 'codex-1', plan: '' })]]).get('codex|codex-1|w')).toBe('codex 1')
})

test('a log preview is a tag, the command and a short path; the full text keeps it with home as ~', () => {
  const entry = (text: string, kind: CrewEvent['kind'] = 'tool', level: 'info' | 'error' = 'info') => ({ text, kind, level })
  expect(logPreview(entry('Bash: wc -l </home/anhtran/.local/share/firstmate/data/crew-demo-scout/report.md'))).toEqual({ tag: 'BASH', tone: 'suggestion', head: 'wc', rest: '-l <…/report.md' })
  expect(logPreview(entry('Edit: /home/anhtran/repo/hooks/zones.tsx'))).toMatchObject({ tag: 'EDIT', head: '…/zones.tsx', rest: '' })
  expect(logPreview(entry('Read: hooks/zones.tsx'))).toMatchObject({ tag: 'READ', head: 'hooks/zones.tsx' })
  expect(logPreview(entry('done [at=1792648595]: Scout report written', 'status'))).toEqual({ tag: 'STAT', tone: 'success', head: 'done:', rest: 'Scout report written' })
  expect(logPreview(entry('blocked [at=1]: needs a decision', 'status', 'error'))).toMatchObject({ tag: '× ERR', tone: 'error', head: 'blocked:' })
  expect(logPreview(entry('step 3'))).toMatchObject({ tag: 'TOOL', head: 'step', rest: '3' })
  // A call with no argument to show is its bare name: the tag still names the tool.
  expect(logPreview(entry('TodoWrite'))).toEqual({ tag: 'TODO', tone: 'suggestion', head: '', rest: '' })
  expect(['Bash', 'TodoWrite', 'WebSearch', 'mcp__github__search', 'exec_command', 'constructor', '???'].map(toolTag)).toEqual(['BASH', 'TODO', 'SEARCH', 'MCP', 'EXEC', 'CONSTR', 'TOOL'])
  // No preview carries a home folder: every absolute path of two or more parts is cut to its last part.
  expect(shortPaths('cd /tmp/a/b && cat ~/notes/today.md "/srv/a b/c/x"')).toBe('cd …/b && cat …/today.md "/srv/a b/c/x"')
  expect(shortPaths('python3 -I /home/me/.config/x/ --home /home…')).toBe('python3 -I …/x/ --home /home…')
  expect(shortPaths('x|/opt/a/b/c;/opt/d/e/f')).toBe('x|…/c;…/f')
  // Short paths and URLs stay whole: they hold no folder of the person's.
  expect(shortPaths('ls 2>/dev/null ~/notes /etc/hosts')).toBe('ls 2>/dev/null ~/notes /etc/hosts')
  expect(shortPaths('WebFetch https://github.com/a/b/c file:///x/y/z')).toBe('WebFetch https://github.com/a/b/c file:///x/y/z')
  // The home folder never survives, wherever it sits; a longer name is another folder.
  expect(tildeHome('O=/home/anhtran/.local/x; ls /home/anhtran /home/anhtran2/y; cd /home/anhtran', '/home/anhtran')).toBe('O=~/.local/x; ls ~ /home/anhtran2/y; cd ~')
  expect(tildeHome('cc -I/home/anhtran/inc a|/home/anhtran/bin/x', '/home/anhtran/')).toBe('cc -I~/inc a|~/bin/x')
  expect(logPreview(entry('Bash: cd /home/anhtran && ls -la /home/anhtran/'), '/home/anhtran')).toMatchObject({ head: 'cd', rest: '~ && ls -la ~/' })
  expect(tildeHome('/home/anhtran/x', '')).toBe('/home/anhtran/x')
  // Claude's transcript folders spell the home with dashes; that user name is hidden too, a longer one is not.
  expect(tildeHome('~/.claude/projects/-home-anhtran--treehouse-dotfiles-7/a.jsonl -home-anhtran2-x', '/home/anhtran')).toBe('~/.claude/projects/~--treehouse-dotfiles-7/a.jsonl -home-anhtran2-x')
  expect(logPreview(entry('Read: /home/anhtran/.claude/projects/-home-anhtran--treehouse-d…'), '/home/anhtran').head).toBe('…/~--treehouse-d…')
  expect(logPreview(entry('Bash: ls -home-anhtran-x'), '/home/anhtran').rest).toBe('~-x')
  expect(tildeHome('/x', '/')).toBe('/x')
})

test('a card says the latest status in a word and only a running or blocked one draws a strong border', () => {
  const m = (status: string, lastAt = NOW - 10_000, lastTool = '') => ({ status, lastAt, lastTool })
  expect(statusMessage(m('done [at=1]: Scout report written'), NOW)).toEqual({ text: '✓ Scout report written', tone: 'success' })
  expect(statusMessage(m('done [at=1]'), NOW)).toEqual({ text: '✓ done', tone: 'success' })
  expect(statusMessage(m('blocked [at=1]: needs a decision on /home/me/a/b.md'), NOW)).toEqual({ text: '× blocked: needs a decision on …/b.md', tone: 'error' })
  expect(statusMessage(m('working [at=1]: lockfile'), NOW)).toEqual({ text: 'working: lockfile', tone: 'subtle' })
  expect(statusMessage(m('', NOW, 'Bash: npm test'), NOW)).toEqual({ text: '▸ Bash: npm test', tone: 'subtle' })
  expect(statusMessage(m('', 0), NOW)).toEqual({ text: `${NONE} no status line yet`, tone: 'subtle' })
  expect(cardBorder(m('working [at=1]: x'), NOW)).toEqual({ color: 'merged', dim: false })
  expect(cardBorder(m(''), NOW)).toEqual({ color: 'merged', dim: false })
  expect(cardBorder(m('blocked [at=1]: x'), NOW)).toEqual({ color: 'error', dim: false })
  expect(cardBorder(m('done [at=1]: x'), NOW)).toEqual({ color: 'border', dim: true })
  expect(cardBorder(m('', NOW - 3_600_000), NOW)).toEqual({ color: 'border', dim: true })
  // Quiet is not finished: its border stays purple, only dimmer.
  expect(cardBorder(m('working [at=1]: x', NOW - 300_000), NOW)).toEqual({ color: 'merged', dim: true })
  expect(statusOf(m('done [at=1]: x'), NOW)).toMatchObject({ mark: '✓', color: 'success' })
  expect(crewCounts([m('done [at=1]: x'), m('working [at=1]: y'), m('', NOW - 3_600_000)], NOW)).toEqual({ live: 3, active: 1, done: 1 })
})

test('segments fill one line and cut where the width ends, padding kept', () => {
  const parts = [{ text: '12:45:51  ', tone: 'subtle' }, { text: 'BASH    ', tone: 'suggestion' }, { text: 'wc', tone: 'text' }, { text: ' -l <…/report.md', tone: 'subtle' }]
  expect(fitSegments(parts, 80).map(s => s.text).join('')).toBe('12:45:51  BASH    wc -l <…/report.md')
  expect(fitSegments(parts, 20).map(s => s.text)).toEqual(['12:45:51  ', 'BASH    ', 'wc'])
  expect(fitSegments(parts, 13).map(s => s.text)).toEqual(['12:45:51  ', 'BA…'])
  expect(fitSegments(parts, 0)).toEqual([])
})
