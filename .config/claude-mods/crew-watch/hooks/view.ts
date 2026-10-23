/**
 * The dashboard's view model: pure functions from the collector's report to what each zone shows.
 * No engine calls or UI elements. A field the collector does not give is shown as `—` or a stated
 * absence, never as a made-up number.
 */
import type { CrewEvent, CrewMember, CrewReport, CrewTotals, FiveHourReading, HistoryWindow, LogFilter, ModelUsage, PollState, QuotaReading } from '../types'
import { SOURCES, ago, cacheHit, cells, charCells, clip, dispatchText, gauge, measuredText, previewText, roundTokens, tokens, totalTokens } from './format'
import { crewState, isActive, memberKey } from './dashboard'
import { AGENT_BORDERS, harnessStyle } from './theme'

export { isActive } from './dashboard'

/** A field the source does not provide. */
export const NONE = '—'

/** Cells a zone's rows may take before the dashboard drops to one column. */
export const TWO_COLUMNS_FROM = 110
/** Below this the agents are listed as rows and labels shorten. */
export const CONDENSED_BELOW = 70
/** From this width each zone sits in its own box; below it a zone is a heading rule and its rows. */
export const FRAMED_FROM = 40

/** A crewmate's status as the pane writes it: a glyph and an upper-case word, so no colour is needed to read it. */
export const statusOf = (m: Pick<CrewMember, 'lastAt' | 'status'>, now: number): { mark: string; label: string; color: string } => {
  if (m.lastAt <= 0 && m.status.trim() === '') return { mark: '?', label: 'UNKNOWN', color: 'subtle' }
  const state = crewState(m, now)
  const label = state.label === 'done · waiting for firstmate' ? 'DONE' : state.label === 'paused / waiting' ? 'PAUSED' : state.label.toUpperCase()
  return { mark: state.mark, label, color: state.color }
}

export type SourceState = { state: 'loading' | 'live' | 'stale' | 'error'; mark: string; label: string; tone: string; age: string }

/**
 * Whether what the pane shows is fresh. A failed read keeps the last good report and says so; a report
 * older than `staleMs` (two refreshes and one read's timeout) is stale, never shown as current.
 */
export const sourceState = (report: Pick<CrewReport, 'generatedAt'> | null, poll: PollState | null, now: number, staleMs: number): SourceState => {
  if (report === null) {
    return poll?.failed
      ? { state: 'error', mark: '×', label: 'SOURCE ERROR', tone: 'error', age: 'no data yet' }
      : { state: 'loading', mark: '◌', label: 'LOADING', tone: 'subtle', age: 'reading the crew logs…' }
  }
  const elapsed = Math.max(0, now - report.generatedAt)
  const age = `updated ${ago(elapsed)} ago`
  if (poll?.failed) return { state: 'error', mark: '×', label: 'SOURCE ERROR', tone: 'error', age: `last good ${ago(elapsed)} ago` }
  if (elapsed > staleMs) return { state: 'stale', mark: '◷', label: 'STALE', tone: 'warning', age }
  return { state: 'live', mark: '●', label: 'LIVE', tone: 'success', age }
}

export type Layout = {
  mode: 'mini' | 'cards' | 'rows'
  columns: 1 | 2
  /** Each zone sits in its own box, with a blank row between boxes unless the pane is short. */
  framed: boolean
  /** Cells inside a zone: the pane's width less the box's border and padding when framed. */
  inner: number
  cardWidth: number
  condensed: boolean
  /** Rows of logs in the preview; 0 collapses the zone to one line. */
  logRows: number
  /** True when Activity shows one summary line instead of its lanes. */
  activityCollapsed: boolean
  /** Under 24 rows: agent rows drop their status line (a blocked one's stays). */
  short: boolean
}

/** Cells a zone's rows get: inside a box, its two border cells and one cell of padding each side are gone. */
export const zoneInner = (width: number, framed: boolean): number => Math.max(1, framed ? width - 4 : width)

/**
 * The responsive layout. Widths are the pane body's columns, heights its rows: two card columns from
 * 110 columns, one below, agent rows below 70 or past four (two columns) or three (one) crewmates;
 * under 24 rows Activity and the log preview fold to one line each, from 36 rows the log shows five.
 * From 40 columns each zone has its own box; a narrower pane keeps only heading rules.
 */
export const layoutFor = (width: number, rows: number, count: number, placement: string): Layout => {
  const columns = width >= TWO_COLUMNS_FROM ? 2 : 1
  const condensed = width < CONDENSED_BELOW
  const short = rows < 24
  const maxCards = columns === 2 ? 4 : 3
  const mode = placement === 'inline' ? 'mini' : condensed || short || count > maxCards ? 'rows' : 'cards'
  const framed = width >= FRAMED_FROM
  const inner = zoneInner(width, framed)
  return {
    mode,
    columns: mode === 'cards' && count > 1 ? columns : 1,
    framed,
    inner,
    cardWidth: mode === 'cards' && count > 1 && columns === 2 ? Math.floor((inner - 1) / 2) : inner,
    condensed,
    logRows: short ? 0 : rows >= 36 ? 5 : 3,
    activityCollapsed: short,
    short,
  }
}

/** `── TITLE · hint ─────`, cut to the width; the title is never cut before the hint. */
export const headingParts = (title: string, hint: string, width: number): { lead: string; title: string; hint: string; rule: string } => {
  const lead = width > 4 ? '── ' : ''
  const name = clip(title, Math.max(1, width - cells(lead)))
  const rest = Math.max(0, width - cells(lead) - cells(name))
  const tail = hint && rest > 4 ? ` ${clip(`· ${hint}`, rest - 2)}` : ''
  const left = rest - cells(tail)
  return { lead, title: name, hint: tail, rule: left > 1 ? ' ' + '─'.repeat(left - 1) : '' }
}

/** A zone's title and its meta, each cut to fit one row of `width` with two cells between them; the title is cut last. */
export const sectionParts = (title: string, meta: string, width: number): { title: string; meta: string } => {
  const name = clip(title, Math.max(1, width))
  const room = width - cells(name) - 2
  return { title: name, meta: meta && room >= 4 ? clip(meta, room) : '' }
}

/** The fleet's usage under the Overview tiles: what Tokens, Requests and Tool calls count; `—` before any report. */
export const totalsText = (totals: CrewTotals | null): string =>
  totals
    ? `Tokens ${tokens(totalTokens(totals))} · Requests ${totals.requests} · Tool calls ${totals.toolCalls}`
    : `Tokens ${NONE} · Requests ${NONE} · Tool calls ${NONE}`

/** One Overview tile: a big figure over a small upper-case label. */
export type Tile = { key: string; label: string; short: string; value: string; tone: string }

const count2 = (n: number): string => String(n).padStart(2, '0')

/**
 * The Overview tiles: live crewmates, those running (working or active), those done, and the cache-read
 * share of all input. `—` before the first report, and for the cache share while no input is readable.
 * The share is labelled CACHE READ, not a hit rate (see KPI_DEFINITIONS).
 */
export const overviewTiles = (crew: readonly Pick<CrewMember, 'lastAt' | 'status'>[] | null, totals: CrewTotals | null, now: number): Tile[] => {
  const count = crew ? crewCounts(crew, now) : null
  return [
    { key: 'live', label: 'LIVE', short: 'LIVE', value: count ? count2(count.live) : NONE, tone: 'text' },
    { key: 'running', label: 'RUNNING', short: 'RUN', value: count ? count2(count.active) : NONE, tone: 'text' },
    { key: 'done', label: 'DONE', short: 'DONE', value: count ? count2(count.done) : NONE, tone: count && count.done > 0 ? 'success' : 'text' },
    { key: 'cache', label: 'CACHE READ', short: 'CACHE', value: totals ? cacheShare(totals) : NONE, tone: 'permission' },
  ]
}

/** Tiles in a row: four while each keeps 11 cells (a seven-letter label, its border and padding), else two, else one. */
export const tilesPerRow = (width: number): 1 | 2 | 4 => width >= 4 * 11 + 3 ? 4 : width >= 2 * 11 + 1 ? 2 : 1

/** The fleet KPIs, labelled for what they count; `—` before the first report. */
export const kpiText = (totals: CrewTotals | null, condensed: boolean): string => {
  const [tok, req, tools, cache] = totals
    ? [tokens(totalTokens(totals)), String(totals.requests), String(totals.toolCalls), cacheShare(totals)]
    : [NONE, NONE, NONE, NONE]
  return condensed
    ? `Tok ${tok} · Req ${req} · Tools ${tools} · Cache ${cache}`
    : `Tokens ${tok} · Requests ${req} · Tool calls ${tools} · Cache ${cache}`
}

/** The cache-read share of input tokens, `—` when there was no input. */
export const cacheShare = (u: Pick<CrewTotals, 'input' | 'cacheRead' | 'cacheWrite'>): string => {
  const hit = cacheHit(u)
  return hit === '-' ? NONE : hit
}

/** What each fleet KPI counts, said once (Details and help). */
export const KPI_DEFINITIONS = 'Tokens = uncached input + cache read + cache write + output, summed over the live crew since each task started; thinking is part of output, so it is not added again. Cache = cache read / (uncached input + cache read + cache write): the share of all input tokens served from the prompt cache, not a hit rate. The CACHE READ tile shows it.'

/** One part of the Tokens total: its label, the glyph its cells are drawn with and its own colour. */
export type TokenPart = { label: string; glyph: string; tone: string; value: number }

/**
 * The glyph of the token bar and its legend swatches: the thin `━` every other bar in the pane uses, so
 * the bar sits mid-row and never runs into the Tokens line above it or the legend below it.
 */
export const TOKEN_GLYPH = '━'

/** A legend item's swatch: two cells of the bar's glyph in the part's colour. */
export const TOKEN_SWATCH = TOKEN_GLYPH.repeat(2)

/** The four parts Tokens adds up, in the bar's order: cache read, cache write, output, uncached input. */
export const tokenParts = (u: Pick<CrewTotals, 'input' | 'output' | 'cacheRead' | 'cacheWrite'>): TokenPart[] => [
  { label: 'read', glyph: TOKEN_GLYPH, tone: 'permission', value: u.cacheRead },
  { label: 'write', glyph: TOKEN_GLYPH, tone: 'success', value: u.cacheWrite },
  { label: 'out', glyph: TOKEN_GLYPH, tone: 'merged', value: u.output },
  { label: 'uncached in', glyph: TOKEN_GLYPH, tone: 'text', value: u.input },
]

/**
 * The parts as one bar of `width` cells, each part's cells in proportion (largest remainders round up);
 * a part above zero keeps at least one cell while there is room for each. Empty when nothing was used.
 * With `gap`, that many blank cells part each two neighbours, unless the width leaves no room for them.
 */
export const tokenBar = (parts: readonly TokenPart[], width: number, gap = 0): Segment[] => {
  const shown = parts.filter(p => p.value > 0)
  const total = shown.reduce((n, p) => n + p.value, 0)
  const gaps = Math.max(0, shown.length - 1) * gap
  const parted = gap > 0 && Math.floor(width) - gaps >= shown.length
  const size = Math.max(0, Math.floor(width) - (parted ? gaps : 0))
  if (total <= 0 || size === 0) return []
  const least = size >= shown.length ? 1 : 0
  const spare = size - least * shown.length
  const exact = shown.map(p => p.value * spare / total)
  const short = spare - exact.reduce((n, x) => n + Math.floor(x), 0)
  const bumped = new Set(exact.map((x, i) => [x - Math.floor(x), i] as const).sort((a, b) => b[0] - a[0] || a[1] - b[1]).slice(0, short).map(([, i]) => i))
  return shown
    .map((p, i) => ({ text: p.glyph.repeat(least + Math.floor(exact[i] ?? 0) + (bumped.has(i) ? 1 : 0)), tone: p.tone }))
    .filter(s => s.text !== '')
    .flatMap((s, i): Segment[] => i > 0 && parted ? [{ text: ' '.repeat(gap), tone: 'subtle' }, s] : [s])
}

const exact = (n: number): string => n.toLocaleString('en-US')

/**
 * The Tokens and Cache figures written out with every term, for Details: the numbers a reader can
 * recompute, so a rounded `24` beside `828k` cannot pass for 24k.
 */
export const tokenFormulas = (u: Pick<CrewTotals, 'input' | 'output' | 'cacheRead' | 'cacheWrite' | 'reasoning'>): string[] => {
  const input = u.input + u.cacheRead + u.cacheWrite
  const terms = `uncached in ${exact(u.input)} + cache read ${exact(u.cacheRead)} + cache write ${exact(u.cacheWrite)}`
  return [
    `Tokens ${exact(totalTokens(u))} = ${terms} + out ${exact(u.output)}`,
    input === 0 ? `Cache ${NONE}: no input tokens yet` : `Cache ${cacheShare(u)} = cache read ${exact(u.cacheRead)} / (${terms}) = ${(u.cacheRead * 100 / input).toFixed(1)}%`,
    u.reasoning > 0 ? `thinking ${exact(u.reasoning)}, already counted in out` : 'thinking not reported apart from out',
  ]
}

/** The header's counts: crewmates listed, those working or active, and those done. */
export const crewCounts = (crew: readonly Pick<CrewMember, 'lastAt' | 'status'>[], now: number): { live: number; active: number; done: number } => ({
  live: crew.length,
  active: crew.filter(m => isActive(m, now)).length,
  done: crew.filter(m => statusOf(m, now).label === 'DONE').length,
})

/** The context line: a gauge and the percent only when the window is known; over 100% is shown, not clamped. */
export const contextLine = (m: Pick<CrewMember, 'context' | 'contextWindow' | 'contextModel'> & Partial<Pick<CrewMember, 'readable'>>, bar: number, label = 'Ctx'): string => {
  if (m.readable === false) return `${label} ${NONE} · logs not readable`
  if (!m.contextWindow || m.contextWindow <= 0) {
    if (m.context === 0 && !m.contextModel) return `${label} ${NONE} · no request yet`
    return `${label} ${tokens(m.context)} · ${m.contextModel ? `window n/a for ${m.contextModel.replace(/^claude-/, '')}` : 'window not recorded'}`
  }
  const pct = Math.round(m.context * 100 / m.contextWindow)
  const over = m.context > m.contextWindow ? ' · over window' : ''
  return `${label} ${gauge(pct, bar)} ${pct}% · ${tokens(m.context)}/${tokens(m.contextWindow)}${over}`
}

/**
 * A card's context figure, `used / window · percent`, and the percent its bar is drawn from; null when
 * the window is not known, so no bar is drawn. Over 100% is shown, not clamped.
 */
export const contextFigure = (m: Pick<CrewMember, 'context' | 'contextWindow' | 'contextModel'> & Partial<Pick<CrewMember, 'readable'>>): { text: string; percent: number | null } => {
  if (m.readable === false) return { text: `${NONE} · logs not readable`, percent: null }
  if (!m.contextWindow || m.contextWindow <= 0) {
    if (m.context === 0 && !m.contextModel) return { text: `${NONE} · no request yet`, percent: null }
    return { text: `${tokens(m.context)} · ${m.contextModel ? `window n/a for ${m.contextModel.replace(/^claude-/, '')}` : 'window not recorded'}`, percent: null }
  }
  const pct = Math.round(m.context * 100 / m.contextWindow)
  const over = m.context > m.contextWindow ? ' · over window' : ''
  return { text: `${roundTokens(m.context)} / ${roundTokens(m.contextWindow)} · ${pct}%${over}`, percent: pct }
}

/**
 * A bar `width` cells wide: the filled part (`━`) and the rest (`─`). A percent that reads above zero at
 * one decimal keeps one cell, so a bar never shows a cell its `0%` does not; a non-finite one fills none.
 */
export const barParts = (percent: number, width: number): { fill: string; track: string } => {
  const size = Math.max(0, Math.floor(width))
  const shown = Number.isFinite(percent) ? Number(percent.toFixed(1)) : 0
  const filled = Math.max(shown > 0 && size > 0 ? 1 : 0, Math.min(size, Math.round(shown * size / 100)))
  return { fill: '━'.repeat(filled), track: '─'.repeat(size - filled) }
}

/**
 * A card's own usage line: requests, tool calls, and its input and output tokens. `in` is all input
 * (uncached + cache read + cache write), so it is never a small uncached count beside a large total.
 */
export const cardStats = (m: Pick<CrewMember, 'readable' | 'harness' | 'requests' | 'toolCalls' | 'input' | 'cacheRead' | 'cacheWrite' | 'output'>): string => {
  if (!m.readable) return `requests ${NONE} · tools ${NONE} · ${m.harness} logs not readable`
  const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`
  return `${plural(m.requests, 'request')} · ${plural(m.toolCalls, 'tool')} · in ${tokens(m.input + m.cacheRead + m.cacheWrite)} / out ${tokens(m.output)}`
}

/** Exact context, for the details panel. */
export const contextExact = (m: Pick<CrewMember, 'context' | 'contextWindow' | 'contextModel' | 'windowSource'>): string => {
  const used = m.context.toLocaleString('en-US')
  if (!m.contextWindow || m.contextWindow <= 0) return `${used} tokens · window unknown${m.contextModel ? ` for ${m.contextModel}` : ''}`
  const pct = (m.context * 100 / m.contextWindow).toFixed(1)
  return `${used} / ${m.contextWindow.toLocaleString('en-US')} tokens (${pct}%)${m.windowSource ? ` · window from ${m.windowSource}` : ''}`
}

const STAMP = /\s*\[at=\d+\]/

/**
 * A crewmate's latest word on its task: its status line without the stamp (done reads `✓ <what>`,
 * blocked `× <line>`), else its last tool call; long paths cut to their last part, home never shown.
 */
export const statusMessage = (m: Pick<CrewMember, 'lastAt' | 'status' | 'lastTool'>, now: number, home = ''): { text: string; tone: string } => {
  const label = statusOf(m, now).label
  const line = previewText(m.status.replace(STAMP, '').trim(), home)
  if (label === 'DONE') return { text: `✓ ${line.replace(/^done\b\s*:?\s*/i, '') || 'done'}`, tone: 'success' }
  if (label === 'BLOCKED') return { text: `× ${line}`, tone: 'error' }
  if (line !== '') return { text: line, tone: 'subtle' }
  if (m.lastTool !== '') return { text: `▸ ${previewText(m.lastTool, home)}`, tone: 'subtle' }
  return { text: `${NONE} no status line yet`, tone: 'subtle' }
}

export type CardBorder = { color: string; dim: boolean; isRunning: boolean }

/**
 * A card's border: its harness's colour (Claude amber, Codex blue, any other neutral), full while the
 * crewmate runs (working or active) or is blocked and dim otherwise; only a running one carries the moving
 * run. The state itself is read from the status glyph and word, never from the border.
 */
export const cardBorder = (m: Pick<CrewMember, 'lastAt' | 'status' | 'harness'>, now: number): CardBorder => {
  const label = statusOf(m, now).label
  const state = label === 'WORKING' || label === 'ACTIVE' ? AGENT_BORDERS.running : label === 'BLOCKED' ? AGENT_BORDERS.blocked : AGENT_BORDERS.calm
  return { color: harnessStyle(m.harness).role, ...state }
}

/** The glyph of a running border's highlight: the heavy line, so it reads without colour too. */
export const RUNNER_GLYPH = '━'

/** Where a running border's highlight sits at one frame: its first cell after the corner and its run of glyphs. */
export type RunnerPart = { left: number; text: string }

/**
 * The highlight a running card's border carries at `frame`, for a box `width` cells wide: a run of heavy
 * `━` that moves half its length each frame, left to right along the top edge and right to left along
 * the bottom one, so the border reads as turning. A run reaching the corner is cut there and the next
 * frame starts over from the far side. Offsets count from the first cell after the left corner. Null
 * when the box is too narrow for one.
 */
export const runnerParts = (width: number, frame: number): { top: RunnerPart; bottom: RunnerPart } | null => {
  const span = Math.floor(width) - 2
  if (span < 3 || !Number.isFinite(frame)) return null
  const size = Math.max(3, Math.min(8, Math.round(span / 6)))
  const step = Math.ceil(size / 2)
  const stops = Math.ceil(span / step)
  const at = ((Math.floor(frame) % stops) + stops) % stops * step
  const run = RUNNER_GLYPH.repeat(Math.min(size, span - at))
  return { top: { left: at, text: run }, bottom: { left: span - at - run.length, text: run } }
}

/** A harness, provider or model name after its family's icon and in its family's colour; `family` names it when `name` does not. */
export const harnessName = (name: string, family = name): Segment => {
  const style = harnessStyle(family)
  return { text: `${style.icon} ${name}`, tone: style.role }
}

/** What a crewmate was dispatched as, `✻ claude opus/high`, all in its harness's colour. */
export const dispatchName = (m: Pick<CrewMember, 'harness' | 'model' | 'effort'>): Segment => harnessName(dispatchText(m), m.harness)

/** The quota keys a crewmate's usage was charged to, each named by provider and account. */
export const accountsOf = (m: Pick<CrewMember, 'quota'> & Partial<Pick<CrewMember, 'readable'>>, readings: Record<string, QuotaReading>): string => {
  if (m.readable === false) return `acct ${NONE} · logs not readable`
  const names = Object.keys(m.quota).map(key => {
    const r = readings[key]
    const [provider = '', account = ''] = key.split('|')
    const who = r?.account ?? account
    return who === 'unknown' ? `${r?.provider ?? provider} account unknown` : `${r?.provider ?? provider} ${who.replace(/^codex-/, '')}`
  })
  return names.length > 0 ? `acct ${[...new Set(names)].join(' + ')}` : `acct ${NONE} · no usage in this week's window`
}

/** Time left until a reset, rounded down: `2d 4h`, `3h 12m`, `45m`, `<1m`. */
export const untilText = (ms: number): string => {
  const minutes = Math.floor(ms / 60_000)
  const hours = Math.floor(minutes / 60)
  return hours >= 24 ? `${Math.floor(hours / 24)}d ${hours % 24}h` : hours >= 1 ? `${hours}h ${minutes % 60}m` : minutes >= 1 ? `${minutes}m` : '<1m'
}

/** A vendor reading older than this is stale, whatever the last report said (as the collector's own rule). */
export const STALE_READING_MS = 30 * 60_000

const isStaleReading = (r: Pick<FiveHourReading, 'stale' | 'observedAt'>, now: number): boolean =>
  r.stale || r.observedAt === null || now - r.observedAt > STALE_READING_MS

/**
 * One account's default Quota row: the vendor's weekly percent as measured (`—` and why when there is
 * none), the time to its reset when known, and a stale mark once the reading is over half an hour old.
 */
export type QuotaLine = { percent: number | null; figure: string; reset: string; note: string; tone: string }

const resetText = (resetsAt: number | null, now: number): string => resetsAt !== null && resetsAt > now ? `resets ${untilText(resetsAt - now)}` : ''

const noneLine = (reset: string, note: string): QuotaLine => ({ percent: null, figure: NONE, reset, note, tone: 'subtle' })

const measuredLine = (w: FiveHourReading & { percent: number }, now: number): QuotaLine => {
  const stale = isStaleReading(w, now)
  return { percent: w.percent, figure: measuredText(w.percent), reset: resetText(w.resetsAt, now), note: stale ? '◷ stale' : '', tone: stale ? 'warning' : 'text' }
}

export const quotaLine = (r: QuotaReading, now: number): QuotaLine => {
  const reset = resetText(r.resetsAt, now)
  if (!r.indexed) return noneLine(reset, 'indexing local logs…')
  if (!r.accountKnown) return noneLine(reset, 'account unknown')
  if (r.percent === null) return noneLine(reset, r.reset ? 'window reset' : 'no reading')
  return measuredLine({ ...r, percent: r.percent }, now)
}

/** The 5h row of an account: the vendor's 5-hour percent as reported, never estimated, or `—` and why. */
export const fiveHourLine = (r: QuotaReading, now: number): QuotaLine => {
  const w = r.fiveHour
  const reset = resetText(w?.resetsAt ?? null, now)
  if (!r.accountKnown) return noneLine(reset, 'account unknown')
  if (!w) return noneLine(reset, 'no 5h reading')
  if (w.percent === null) return noneLine(reset, w.reset ? 'window reset' : 'no 5h reading')
  return measuredLine({ ...w, percent: w.percent }, now)
}

/** Where an account's figure comes from and how old it is, for the Quota notes (`i`). */
export const quotaSource = (r: QuotaReading, now: number): { text: string; tone: string } => {
  if (!r.indexed) return { text: 'indexing local logs…', tone: 'subtle' }
  if (!r.accountKnown) return { text: `week % ${NONE}: no account could be tied to this usage`, tone: 'warning' }
  if (r.percent === null) return { text: `week % ${NONE}: ${r.reset ? 'the window reset since the last reading' : 'no reading yet'}`, tone: 'warning' }
  const stale = isStaleReading(r, now)
  const when = r.observedAt === null ? 'stale, age unknown' : `${stale ? 'stale' : 'measured'} ${ago(Math.max(0, now - r.observedAt))} ago`
  const source = r.source ? ` · source ${SOURCES[r.source] ?? r.source}` : ''
  return { text: `week ${measuredText(r.percent)} ${when}${source}`, tone: stale ? 'warning' : 'subtle' }
}

/** Where an account's 5h figure comes from and how old it is, for the Quota notes (`i`). */
export const fiveHourSource = (r: QuotaReading, now: number): { text: string; tone: string } => {
  const w = r.fiveHour
  if (!r.accountKnown) return { text: `5h % ${NONE}: no account could be tied to this usage`, tone: 'warning' }
  if (!w) return { text: `5h % ${NONE}: no source has a 5-hour window for this account`, tone: 'subtle' }
  if (w.percent === null) return { text: `5h % ${NONE}: ${w.reset ? 'the window reset since the last reading' : 'no reading yet'}`, tone: 'warning' }
  const stale = isStaleReading(w, now)
  const when = w.observedAt === null ? 'stale, age unknown' : `${stale ? 'stale' : 'measured'} ${ago(Math.max(0, now - w.observedAt))} ago`
  const source = w.source ? ` · source ${SOURCES[w.source] ?? w.source}` : ''
  return { text: `5h ${measuredText(w.percent)} ${when}${source}`, tone: stale ? 'warning' : 'subtle' }
}

/**
 * Each account's name in the Quota zone: a Claude account by its ai-acct name, a Codex one by its plan
 * (its id is only a hash) unless two of a provider would then read the same; never merged.
 */
export const quotaNames = (entries: readonly [string, QuotaReading][]): Map<string, string> => {
  const id = (r: QuotaReading) => r.accountKnown ? r.account.replace(/^codex-/, '') : 'unknown'
  const short = (r: QuotaReading) => r.provider === 'codex' && r.accountKnown && r.plan ? r.plan : id(r)
  const counts = entries.reduce((n, [, r]) => n.set(`${r.provider} ${short(r)}`, (n.get(`${r.provider} ${short(r)}`) ?? 0) + 1), new Map<string, number>())
  return new Map(entries.map(([key, r]) => {
    const name = `${r.provider} ${short(r)}`
    return [key, (counts.get(name) ?? 0) > 1 ? `${r.provider} ${id(r)}` : name]
  }))
}

const PROVIDER_ORDER = ['claude', 'codex']

/**
 * The accounts the Quota zone lists, one entry per provider and account, never merged: every known
 * account with a reading or local usage, and an unknown one only where the crew's usage went to it.
 */
export const quotaEntries = (report: Pick<CrewReport, 'quota' | 'crew'>): [string, QuotaReading][] => {
  const used = new Set([...Object.keys(report.quota.fleet), ...report.crew.flatMap(m => Object.keys(m.quota))])
  const rank = (p: string) => (PROVIDER_ORDER.indexOf(p) + 1 || PROVIDER_ORDER.length + 1)
  return Object.entries(report.quota.readings)
    .filter(([key, r]) => r.accountKnown || used.has(key))
    .sort(([, a], [, b]) => rank(a.provider) - rank(b.provider) || Number(!a.accountKnown) - Number(!b.accountKnown) || a.account.localeCompare(b.account))
}

/** The inline summary's quota rows, one per provider: the provider, then each account's weekly percent, never summed or mixed. */
export const quotaBriefParts = (report: Pick<CrewReport, 'quota' | 'crew'>, now: number): { provider: string; text: string }[] => {
  const byProvider = new Map<string, string[]>()
  for (const [, r] of quotaEntries(report)) {
    const name = r.accountKnown ? r.account.replace(/^codex-/, '') : 'unknown'
    const figure = r.percent === null || !r.accountKnown ? NONE : `${measuredText(r.percent)}${isStaleReading(r, now) ? ' stale' : ''}`
    byProvider.set(r.provider, [...(byProvider.get(r.provider) ?? []), `${name} ${figure}`])
  }
  return [...byProvider].map(([provider, parts]) => ({ provider, text: ` week: ${parts.join(' · ')}` }))
}

/** The inline summary as plain text: one row per provider of each account's weekly percent. */
export const quotaBrief = (report: Pick<CrewReport, 'quota' | 'crew'>, now: number): string[] => {
  const rows = quotaBriefParts(report, now).map(row => `${row.provider}${row.text}`)
  return rows.length > 0 ? rows : ['quota: no readings yet']
}

export type LogEntry = {
  id: string
  /** The event's place in its crewmate's log, oldest 0: breaks ties between events of one instant. */
  seq: number
  at: number
  who: string
  key: string
  color: string
  /** The crewmate's harness: a tool tag takes its colour. */
  harness: string
  kind: CrewEvent['kind']
  level: 'info' | 'error'
  text: string
  /** The collector cut the text (it ends its snippets with `…`): the rest is not kept anywhere. */
  sourceTruncated: boolean
} & Pick<CrewEvent, 'inTokens' | 'outTokens' | 'estimated'>

/** A status line's state word is the firstmate protocol's, so blocked, failed and needs-decision are errors. */
const levelOf = (event: CrewEvent): LogEntry['level'] =>
  event.kind === 'status' && /^\s*(blocked|failed|needs-decision)\b/i.test(event.text) ? 'error' : 'info'

/** Every logged event of the crew, newest first, with a stable id per event. */
export const logEntries = (crew: readonly Pick<CrewMember, 'home' | 'id' | 'harness' | 'events'>[]): LogEntry[] =>
  crew.flatMap(m => m.events.map((event, i) => ({
    // The event itself names it, so the id holds while older events drop off; a repeat gets its ordinal.
    id: `${memberKey(m)}#${event.at}#${event.kind}#${event.text}#${m.events.slice(0, i).filter(e => e.at === event.at && e.kind === event.kind && e.text === event.text).length}`,
    seq: i,
    at: event.at,
    who: m.id,
    key: memberKey(m),
    color: 'subtle',
    harness: m.harness,
    kind: event.kind,
    level: levelOf(event),
    text: event.text,
    sourceTruncated: event.text.endsWith('…'),
    inTokens: event.inTokens,
    outTokens: event.outTokens,
    estimated: event.estimated,
  }))).sort((a, b) => b.at - a.at || b.seq - a.seq || a.key.localeCompare(b.key))

export const FILTER_LABELS: Record<LogFilter, string> = { all: 'All', tools: 'Tools', status: 'Status', errors: 'Errors', agent: 'Agent' }

/** The next log filter; `agent` is offered only while one crewmate's details are open. */
export const nextFilter = (current: LogFilter, hasAgent: boolean): LogFilter => {
  const order: LogFilter[] = hasAgent ? ['all', 'tools', 'status', 'errors', 'agent'] : ['all', 'tools', 'status', 'errors']
  return order[(order.indexOf(current) + 1) % order.length] ?? 'all'
}

/** The filter in force: `agent` with no open crewmate is no filter, and is shown as All. */
export const effectiveFilter = (filter: LogFilter, agentKey: string | null): LogFilter => filter === 'agent' && agentKey === null ? 'all' : filter

/** The entries a filter keeps; `agent` without an open crewmate keeps them all. */
export const filterLogs = (entries: readonly LogEntry[], filter: LogFilter, agentKey: string | null): LogEntry[] =>
  entries.filter(entry =>
    filter === 'tools' ? entry.kind === 'tool'
      : filter === 'status' ? entry.kind === 'status'
        : filter === 'errors' ? entry.level === 'error'
          : filter === 'agent' && agentKey !== null ? entry.key === agentKey
            : true)

/** The filter's label as the zone shows it, naming the crewmate for `agent`. */
export const filterLabel = (filter: LogFilter, agentId: string | undefined): string =>
  filter === 'agent' ? `Agent: ${agentId ?? NONE}` : FILTER_LABELS[filter]

/** A run of text in one tone, one piece of a line drawn as several Texts; `inverse` draws it as a badge. */
export type Segment = { text: string; tone: string; bold?: boolean; inverse?: boolean }

/** Segments laid on one line of `width` cells: the one that reaches the edge is clipped with `…`, any after it dropped. */
export const fitSegments = (segments: readonly Segment[], width: number): Segment[] =>
  segments.reduce<{ out: Segment[]; room: number }>((acc, s) => {
    if (acc.room <= 0 || s.text === '') return acc
    if (cells(s.text) <= acc.room) return { out: [...acc.out, s], room: acc.room - cells(s.text) }
    return { out: [...acc.out, { ...s, text: clip(s.text, acc.room) }], room: 0 }
  }, { out: [], room: Math.max(0, width) }).out

/**
 * Segments wrapped into rows of at most `width` cells: breaks fall between words, a word longer than a
 * row is split across rows, a newline always breaks, and the spaces at a break are dropped. Each piece
 * keeps its segment's tone, so a row never relies on the terminal to wrap it.
 */
export const wrapSegments = (segments: readonly Segment[], width: number): Segment[][] => {
  const room = Math.max(1, Math.floor(width))
  const rows: Segment[][] = [[]]
  let used = 0
  const put = (s: Segment, text: string) => {
    const row = rows[rows.length - 1] as Segment[]
    const last = row[row.length - 1]
    if (last && last.tone === s.tone && last.bold === s.bold && last.inverse === s.inverse) row[row.length - 1] = { ...last, text: last.text + text }
    else row.push({ ...s, text })
    used += cells(text)
  }
  const breakRow = () => {
    const row = rows[rows.length - 1] as Segment[]
    const last = row[row.length - 1]
    if (last) row[row.length - 1] = { ...last, text: last.text.trimEnd() }
    rows.push([])
    used = 0
  }
  for (const s of segments) {
    for (const [i, part] of s.text.split('\n').entries()) {
      if (i > 0) breakRow()
      for (const token of part.replace(/[\r\t]+/g, ' ').match(/ +|[^ ]+/g) ?? []) {
        if (token.startsWith(' ')) {
          if (used > 0 && used + cells(token) < room) put(s, token)
          else if (used > 0) breakRow()
          continue
        }
        if (used > 0 && used + cells(token) > room) breakRow()
        let rest = Array.from(token)
        while (rest.length > 0) {
          const take: string[] = []
          let size = 0
          for (const char of rest) {
            if (used + size + charCells(char) > room) break
            take.push(char)
            size += charCells(char)
          }
          // A wide character on an empty row narrower than it takes the row alone rather than never fit.
          if (take.length === 0 && used === 0) take.push(rest[0] as string)
          if (take.length === 0) {
            breakRow()
            continue
          }
          put(s, take.join(''))
          rest = rest.slice(take.length)
          if (rest.length > 0) breakRow()
        }
      }
    }
  }
  const out = rows.map(row => row.filter(s => s.text !== ''))
  // Trailing spaces that reached the edge broke onto a row of nothing.
  return out.length > 1 && out[out.length - 1]?.length === 0 ? out.slice(0, -1) : out
}

/** Cells the tag column takes: the longest tag (`SEARCH`, `NBEDIT`) fits. */
export const TAG_CELLS = 6

const TOOL_TAGS: Record<string, string> = {
  todowrite: 'TODO', webfetch: 'FETCH', websearch: 'SEARCH', multiedit: 'EDIT', notebookedit: 'NBEDIT',
  exec_command: 'EXEC', apply_patch: 'PATCH', write_stdin: 'STDIN',
}

/** A tool's tag: its name upper-cased in at most six cells (`Bash` BASH, `TodoWrite` TODO, an MCP tool MCP). */
export const toolTag = (name: string): string => {
  const key = name.trim().toLowerCase()
  if (key.startsWith('mcp__')) return 'MCP'
  if (Object.hasOwn(TOOL_TAGS, key)) return TOOL_TAGS[key] ?? 'TOOL'
  return key.replace(/[^a-z0-9]/g, '').slice(0, TAG_CELLS).toUpperCase() || 'TOOL'
}

/**
 * A log row's preview: a tag (the tool's name, STAT for a status line, `× ERR` for an error, so an
 * error reads without red) and its colour (a tool call its crewmate's harness colour, a status line
 * green, an error red), the command or path as the head and the rest of it. Absolute paths are cut to
 * their last part and the home folder written `~`, so the person's user name never shows in a preview
 * or a screenshot.
 */
export const logPreview = (entry: Pick<LogEntry, 'kind' | 'level' | 'text' | 'harness'>, home = ''): { tag: string; tone: string; head: string; rest: string } => {
  const text = entry.text.replace(STAMP, '')
  // A call is `Name: detail`, or the bare name when the call had no argument to show.
  const call = entry.kind === 'tool' ? /^([\w.-]{1,64})(?::\s+([\s\S]*))?$/.exec(text) : null
  const tag = entry.level === 'error' ? '× ERR' : entry.kind === 'status' ? 'STAT' : call?.[1] ? toolTag(call[1]) : 'TOOL'
  const tone = entry.level === 'error' ? 'error' : entry.kind === 'status' ? 'success' : harnessStyle(entry.harness).role
  const [head = '', ...rest] = previewText(call ? call[2] ?? '' : text, home).trim().split(' ')
  return { tag, tone, head, rest: rest.join(' ') }
}

/** Cells each of a log row's token columns takes, right-aligned: `~1.93M` fits. */
export const TOKEN_COLUMN_CELLS = 6

/**
 * A log row's token columns, as the details' recent calls count them: the input its result added
 * (`~` when estimated from its size) and its share of the request's output; `—` where nothing measured it.
 */
export const logTokens = (e: Pick<LogEntry, 'inTokens' | 'outTokens' | 'estimated'>): { input: string; output: string } => ({
  input: e.inTokens === undefined ? NONE : `${e.estimated ? '~' : ''}${tokens(e.inTokens)}`,
  output: e.outTokens === undefined ? NONE : tokens(e.outTokens),
})

/** A short, stable address for a log row's Button, from its entry id. */
export const logKey = (entry: Pick<LogEntry, 'id'>): string => {
  const hash = Array.from(entry.id).reduce((h, char) => Math.imul(h ^ (char.codePointAt(0) ?? 0), 16_777_619) >>> 0, 2_166_136_261)
  return `log-${hash.toString(36)}`
}

/** A figure column of Usage by Model: the field it shows and its header. `total` is in + out + cache read + write. */
export type UsageColumn = { key: 'requests' | 'input' | 'output' | 'cacheRead' | 'cacheWrite' | 'total' | 'crewmates'; label: string }

export const USAGE_COLUMNS: readonly UsageColumn[] = [
  { key: 'requests', label: 'req' }, { key: 'input', label: 'in' }, { key: 'output', label: 'out' }, { key: 'cacheRead', label: 'read' },
  { key: 'cacheWrite', label: 'write' }, { key: 'total', label: 'total' }, { key: 'crewmates', label: 'crew' },
]

/** Cells a figure column takes: a gap and six right-aligned cells, so `1.93M` and `999k` line up. */
export const USAGE_CELLS = 7

/** Cells the model column keeps before a figure column gives way: `✻ claude-opus-5-5` fits. */
export const MIN_MODEL_CELLS = 18

/** The order a narrowing pane drops the figure columns in; `total` stays to the last. */
const USAGE_FOLD: readonly UsageColumn['key'][] = ['crewmates', 'cacheWrite', 'cacheRead', 'requests', 'input', 'output']

/** The figure columns a zone `width` cells wide shows, folding them in USAGE_FOLD's order until the model name keeps its cells. */
export const usageColumns = (width: number): UsageColumn[] => {
  const dropped = USAGE_FOLD.reduce<UsageColumn['key'][]>((out, key) =>
    width - (USAGE_COLUMNS.length - out.length) * USAGE_CELLS >= MIN_MODEL_CELLS ? out : [...out, key], [])
  return USAGE_COLUMNS.filter(c => !dropped.includes(c.key))
}

/** The sums a Usage by Model row shows; `crewmates` counts tasks, so the total row's is not a sum of the rows'. */
export type UsageFigures = Pick<ModelUsage, 'requests' | 'input' | 'output' | 'cacheRead' | 'cacheWrite' | 'crewmates'>

export const usageText = (u: UsageFigures | null, key: UsageColumn['key']): string =>
  u === null ? NONE : key === 'total' ? tokens(totalTokens(u)) : key === 'crewmates' ? String(u.crewmates) : tokens(u[key])

/** The window's total row: every model added up, and the crewmates that had usage in it. */
export const usageTotal = (h: HistoryWindow): UsageFigures => ({
  ...h.models.reduce((sum, m) => ({
    requests: sum.requests + m.requests, input: sum.input + m.input, output: sum.output + m.output,
    cacheRead: sum.cacheRead + m.cacheRead, cacheWrite: sum.cacheWrite + m.cacheWrite,
  }), { requests: 0, input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }),
  crewmates: h.measured,
})

/** The zone's meta: the window, then how many crewmates it holds; `—` before the first report. */
export const usageMeta = (h: HistoryWindow | null, window: HistoryWindow['window']): string => {
  const name = window === 'week' ? 'this week' : 'all time'
  return h ? `${name} · ${h.finished} finished + ${h.live} live` : `${name} · ${NONE}`
}
