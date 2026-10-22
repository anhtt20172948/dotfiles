/**
 * The dashboard's view model: pure functions from the collector's report to what each zone shows.
 * No engine calls or UI elements. A field the collector does not give is shown as `—` or a stated
 * absence, never as a made-up number.
 */
import type { CrewEvent, CrewMember, CrewReport, CrewTotals, LogFilter, PollState, QuotaReading } from '../types'
import { ago, cacheHit, cells, clip, gauge, measuredText, tokens, totalTokens } from './format'
import { crewState, harnessColor, memberKey } from './dashboard'

export { isActive } from './dashboard'

/** A field the source does not provide. */
export const NONE = '—'

/** Cells a zone's rows may take before the dashboard drops to one column. */
export const TWO_COLUMNS_FROM = 110
/** Below this the agents are listed as rows and labels shorten. */
export const CONDENSED_BELOW = 70

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
  cardWidth: number
  condensed: boolean
  /** Rows of logs in the preview; 0 collapses the zone to one line. */
  logRows: number
  /** True when Activity shows one summary line instead of its lanes. */
  activityCollapsed: boolean
}

/**
 * The responsive layout. Widths are the pane body's columns, heights its rows: two card columns from
 * 110 columns, one below, agent rows below 70 or past four (two columns) or three (one) crewmates;
 * under 24 rows Activity and the log preview fold to one line each, from 36 rows the log shows five.
 */
export const layoutFor = (width: number, rows: number, count: number, placement: string): Layout => {
  const columns = width >= TWO_COLUMNS_FROM ? 2 : 1
  const condensed = width < CONDENSED_BELOW
  const short = rows < 24
  const maxCards = columns === 2 ? 4 : 3
  const mode = placement === 'inline' ? 'mini' : condensed || short || count > maxCards ? 'rows' : 'cards'
  return {
    mode,
    columns: mode === 'cards' && count > 1 ? columns : 1,
    cardWidth: mode === 'cards' && count > 1 && columns === 2 ? Math.floor((width - 1) / 2) : width,
    condensed,
    logRows: short ? 0 : rows >= 36 ? 5 : 3,
    activityCollapsed: short,
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
export const KPI_DEFINITIONS = 'Tokens = in + out + cache read + cache write, summed over the live crew since each task started. Cache = cache read / (in + cache read + cache write): the share of input served from the prompt cache.'

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

/** Exact context, for the details panel. */
export const contextExact = (m: Pick<CrewMember, 'context' | 'contextWindow' | 'contextModel' | 'windowSource'>): string => {
  const used = m.context.toLocaleString('en-US')
  if (!m.contextWindow || m.contextWindow <= 0) return `${used} tokens · window unknown${m.contextModel ? ` for ${m.contextModel}` : ''}`
  const pct = (m.context * 100 / m.contextWindow).toFixed(1)
  return `${used} / ${m.contextWindow.toLocaleString('en-US')} tokens (${pct}%)${m.windowSource ? ` · window from ${m.windowSource}` : ''}`
}

/** Requests, tools and tokens; `—` where the harness's logs cannot be read rather than a false 0. */
export const usageLine = (m: Pick<CrewMember, 'readable' | 'requests' | 'toolCalls' | 'input' | 'output' | 'harness'>, condensed = false): string => {
  if (!m.readable) return `${NONE} req · ${NONE} tools · ${m.harness} logs not readable`
  const head = `${m.requests} req · ${m.toolCalls} tools`
  return condensed ? head : `${head} · in ${tokens(m.input)} / out ${tokens(m.output)}`
}

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

const isStaleReading = (r: Pick<QuotaReading, 'stale' | 'observedAt'>, now: number): boolean =>
  r.stale || r.observedAt === null || now - r.observedAt > STALE_READING_MS

/** One account's weekly figure: the vendor percent as measured and how old it is, or why there is none. */
export const quotaFigure = (r: QuotaReading, now: number, bar: number): { text: string; tone: string } => {
  if (!r.indexed) return { text: 'indexing local logs…', tone: 'subtle' }
  if (!r.accountKnown) return { text: `week % ${NONE}: account unknown`, tone: 'warning' }
  if (r.percent === null) return { text: `week % ${NONE}: ${r.reset ? 'window reset' : 'no reading'}`, tone: 'warning' }
  const stale = isStaleReading(r, now)
  const when = r.observedAt === null ? 'stale, age unknown' : `${stale ? 'stale' : 'measured'} ${ago(Math.max(0, now - r.observedAt))} ago`
  const reset = r.resetsAt !== null && r.resetsAt > now ? ` · resets in ${untilText(r.resetsAt - now)}` : ''
  return { text: `week ${gauge(r.percent, bar)} ${measuredText(r.percent)} · ${when}${reset}`, tone: stale ? 'warning' : 'text' }
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

/** The inline summary: one row per provider of each account's weekly percent, never summed or mixed. */
export const quotaBrief = (report: Pick<CrewReport, 'quota' | 'crew'>, now: number): string[] => {
  const byProvider = new Map<string, string[]>()
  for (const [, r] of quotaEntries(report)) {
    const name = r.accountKnown ? r.account.replace(/^codex-/, '') : 'unknown'
    const figure = r.percent === null || !r.accountKnown ? NONE : `${measuredText(r.percent)}${isStaleReading(r, now) ? ' stale' : ''}`
    byProvider.set(r.provider, [...(byProvider.get(r.provider) ?? []), `${name} ${figure}`])
  }
  const rows = [...byProvider].map(([provider, parts]) => `${provider} week: ${parts.join(' · ')}`)
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
  kind: CrewEvent['kind']
  level: 'info' | 'error'
  text: string
  /** The collector cut the text (it ends its snippets with `…`): the rest is not kept anywhere. */
  sourceTruncated: boolean
}

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
    color: harnessColor(m.harness),
    kind: event.kind,
    level: levelOf(event),
    text: event.text,
    sourceTruncated: event.text.endsWith('…'),
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

/** The tag column of a log row: a glyph and a word, so an error reads without red. */
export const logTag = (entry: Pick<LogEntry, 'kind' | 'level'>): string =>
  entry.level === 'error' ? '× ERR ' : entry.kind === 'tool' ? '▸ TOOL' : '◇ STAT'
