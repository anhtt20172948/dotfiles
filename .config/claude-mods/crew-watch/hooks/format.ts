import type { CrewEvent, CrewMember, CrewTotals, MemberQuota, QuotaFigure, QuotaReading, ToolTokens } from '../types'
import { isActive } from './dashboard'

/** 1234 -> 1.2k, 1234567 -> 1.23M. */
export const tokens = (n: number): string => {
  if (n < 1000) return String(n)
  if (n < 1_000_000) return `${(n / 1000).toFixed(n < 10_000 ? 1 : 0)}k`
  return `${(n / 1_000_000).toFixed(n < 10_000_000 ? 2 : 1)}M`
}

/** Share of all input tokens served from the prompt cache. */
export const cacheHit = (u: Pick<CrewTotals, 'input' | 'cacheRead' | 'cacheWrite'>): string => {
  const all = u.input + u.cacheRead + u.cacheWrite
  return all === 0 ? '-' : `${Math.round((u.cacheRead / all) * 100)}%`
}

export const ago = (ms: number): string => {
  const s = Math.max(0, Math.round(ms / 1000))
  if (s < 60) return `${s}s`
  if (s < 3600) return `${Math.floor(s / 60)}m`
  if (s < 86_400) return `${Math.floor(s / 3600)}h${Math.floor((s % 3600) / 60)}m`
  return `${Math.floor(s / 86_400)}d`
}

export const dispatchText = (m: CrewMember): string => {
  const pinned = [m.model, m.effort].filter(v => v && v !== 'default').join('/')
  return pinned ? `${m.harness} ${pinned}` : m.harness
}

/** The one-line summary the status line carries. */
export const statusLine = (crew: readonly CrewMember[], totals: CrewTotals, now: number): string | undefined => {
  if (crew.length === 0) return undefined
  const active = crew.filter(m => isActive(m, now)).length
  const all = totals.input + totals.output + totals.cacheRead + totals.cacheWrite
  return `crew ${crew.length} (${active} active) · ${tokens(all)} tok · ${totals.toolCalls} tools · /crew`
}

/** Fixed-cell gauge; no control characters or raw theme colors. */
export const gauge = (pct: number, width = 8): string => {
  const size = Math.max(0, Math.floor(width))
  const filled = Number.isFinite(pct) ? Math.max(0, Math.min(size, Math.round(pct * size / 100))) : 0
  return '▰'.repeat(filled) + '▱'.repeat(size - filled)
}

export const effortText = (effort: string): string => {
  const ranks: Record<string, number> = { minimal: 25, low: 25, medium: 50, high: 75, xhigh: 100, max: 100, ultra: 100 }
  const pct = Object.hasOwn(ranks, effort) ? ranks[effort] : undefined
  return pct === undefined ? `effort ${effort || 'default'}` : `effort ${gauge(pct, 4)} ${effort}`
}

/** Code points a terminal draws two cells wide: CJK, Hangul, fullwidth forms and pictographs. */
const WIDE: readonly (readonly [number, number])[] = [
  [0x1100, 0x115f], [0x2e80, 0x303e], [0x3041, 0x33ff], [0x3400, 0x4dbf], [0x4e00, 0x9fff], [0xa000, 0xa4cf],
  [0xac00, 0xd7a3], [0xf900, 0xfaff], [0xfe30, 0xfe4f], [0xff00, 0xff60], [0xffe0, 0xffe6], [0x1f300, 0x1f64f],
  [0x1f680, 0x1f6ff], [0x1f900, 0x1faff], [0x20000, 0x3fffd],
]

/** Code points drawn in no cell of their own: combining marks, zero-width spaces and joiners, variation selectors. */
const ZERO: readonly (readonly [number, number])[] = [[0x0300, 0x036f], [0x200b, 0x200f], [0xfe00, 0xfe0f]]

const within = (code: number, ranges: readonly (readonly [number, number])[]) => ranges.some(([lo, hi]) => code >= lo && code <= hi)

/** Terminal cells one character takes. */
export const charCells = (char: string): number => {
  const code = char.codePointAt(0) ?? 0
  return within(code, ZERO) ? 0 : within(code, WIDE) ? 2 : 1
}

/** Terminal cells a one-line text takes. */
export const cells = (text: string): number => Array.from(text).reduce((n, char) => n + charCells(char), 0)

/** One line cut to `width` terminal cells, an ellipsis where it was cut; a wide character never straddles the edge. */
export const clip = (text: string, width: number): string => {
  // Leading spaces are kept: they indent a nested crewmate or a sub-row.
  const chars = Array.from(text.replace(/[\r\n\t]+/g, ' ').trimEnd())
  if (cells(chars.join('')) <= width) return chars.join('')
  if (width <= 0) return ''
  const kept: string[] = []
  let used = 0
  for (const char of chars) {
    const size = charCells(char)
    if (used + size > width - 1) break
    kept.push(char)
    used += size
  }
  return kept.join('') + '…'
}

/** A text clipped and padded with spaces to exactly `width` cells. */
export const pad = (text: string, width: number): string => {
  const cut = clip(text, width)
  return cut + ' '.repeat(Math.max(0, width - cells(cut)))
}

export const clockText = (at: number, timeZone?: string): string => at > 0
  ? new Intl.DateTimeFormat('en-GB', { hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23', ...(timeZone ? { timeZone } : {}) }).format(new Date(at))
  : '--:--:--'

export const totalTokens = (u: CrewTotals): number => u.input + u.output + u.cacheRead + u.cacheWrite

const percentText = (n: number): string => n <= 0 ? '0%' : n < 0.1 ? '<0.1%' : `${n < 10 ? n.toFixed(1) : Math.round(n)}%`

/** Tokens charged to a tool call: its request's output share and the input its result added (~ estimated). */
export const callTokensText = (e: Pick<CrewEvent, 'outTokens' | 'inTokens' | 'estimated'>): string =>
  e.outTokens === undefined || e.inTokens === undefined
    ? 'tok n/a'
    : `out ${tokens(e.outTokens)} in ${e.estimated ? '~' : ''}${tokens(e.inTokens)}`

export const toolTokenTotal = (tt: ToolTokens | undefined): number => (tt?.output ?? 0) + (tt?.input ?? 0)

/** Per-tool total and the average per call; ~ when some of the input was estimated. */
export const toolTokenText = (tt: ToolTokens | undefined): string =>
  tt && tt.calls > 0 ? `${tokens(toolTokenTotal(tt))} tok · avg ${tt.estCalls > 0 ? '~' : ''}${tokens(Math.round(toolTokenTotal(tt) / tt.calls))}` : 'tok n/a'

/** Says why a crewmate's per-call tokens are missing or approximate; empty when they are all measured. */
export const toolTokenNote = (m: Pick<CrewMember, 'toolCalls' | 'toolTokens'>): string => {
  const rows = Object.values(m.toolTokens)
  const attributed = rows.reduce((n, tt) => n + tt.calls, 0)
  if (m.toolCalls > 0 && attributed === 0) return 'per-call tokens unavailable: the transcript has no usage fields'
  return rows.some(tt => tt.estCalls > 0) ? '~ estimated from result size: no later request measured it' : ''
}

/** A share of local usage: a measured fraction, so one decimal under 10%. */
const shareText = (fraction: number): string => percentText(fraction * 100)

/** The vendor's own number at its own time, as given (one decimal at most). */
export const measuredText = (n: number): string => `${Number(n.toFixed(1))}%`

/** An estimate never carries a decimal: it is rounded, and under a point it says so. */
export const estimateText = (n: number): string => n <= 0 ? '0%' : n < 1 ? '<1%' : `~${Math.min(100, Math.round(n))}%`

const SOURCES: Record<string, string> = {
  session: 'this session',
  history: 'reading history',
  'account cache': 'ai-acct cache',
  'codex log': 'codex log',
}

const HEAD_CELLS = 32

/** `acct` is the ai-acct name, `codex-1a2b3c4d` a hashed Codex creator, `unknown` a session of no known account. */
export const accountText = (r: Pick<QuotaReading, 'provider' | 'account' | 'plan' | 'login'>): string => {
  if (r.account === 'unknown') return `${r.provider} account unknown`
  const how = r.plan || (r.login === 'token' ? 'token login' : r.login === 'api-key' ? 'API key' : '')
  const tail = how ? ` · ${how}` : ''
  // A long account name gives way to the plan: the row must fit a collapsed card.
  return `${r.provider} ${clip(r.account.replace(/^codex-/, ''), Math.max(6, HEAD_CELLS - r.provider.length - 1 - Array.from(tail).length))}${tail}`
}

/** How old a measured reading is, or that it is not known; past half an hour or unknown it is stale. */
const ageText = (r: Pick<QuotaReading, 'observedAt' | 'stale'>, now: number): string =>
  r.observedAt === null ? 'stale, age unknown' : `${r.stale ? 'stale' : 'measured'} ${ago(now - r.observedAt)} ago`

/** Whole weighted tokens as a compact count: the unit is price-weighted, so it carries a label. */
const wtokText = (n: number): string => `${tokens(Math.round(n))} wtok`

const figureRow = (label: string, f: QuotaFigure): { text: string; tone: string } => {
  if (f.percent === null) return { text: `${label} ${f.share === null ? '-' : `${shareText(f.share)} of local`}`, tone: 'text' }
  return { text: `${label} ${estimateText(f.percent)} ${f.basis === 'estimated' ? 'of week est' : 'as of reading'}`, tone: 'text' }
}

/**
 * The account, reading and quota lines of one crewmate or the whole fleet, one block per account it
 * used. Each row stays within 32 cells, a collapsed card's narrowest row, so no figure is cut. A
 * figure says whether it is measured (the vendor's percent at a time), estimated (that plus local
 * tokens since, at an uncalibrated rate) or only a raw share of local usage; a reading older than
 * half an hour, or of unknown age, is stale and never called current.
 */
export const quotaRows = (
  quota: Record<string, MemberQuota>,
  readings: Record<string, QuotaReading>,
  now: number,
  fleet = false,
): { text: string; tone: string }[] =>
  Object.entries(quota).flatMap(([key, q]) => {
    const r = readings[key]
    if (!r) return []
    const head = { text: accountText(r), tone: 'subtle' }
    const shares = [figureRow('session', q.session), figureRow('tools direct', q.tools)]
    if (!r.indexed) return [head, { text: 'indexing local logs…', tone: 'subtle' }]
    if (r.percent === null) {
      const why = r.reset ? 'week % unknown: window reset' : r.accountKnown ? 'week % unknown: no reading' : 'week %: account unknown'
      return [head, ...shares, { text: why, tone: 'warning' }]
    }
    const measured = [
      { text: `week ${measuredText(r.percent)} ${ageText(r, now)}`, tone: r.stale ? 'warning' : 'subtle' },
      { text: `source ${SOURCES[r.source] ?? r.source}`, tone: 'subtle' },
    ]
    const account = !fleet ? [] : [
      ...(r.forecast !== null ? [{ text: `account now est ${estimateText(r.forecast)}`, tone: 'text' }] : []),
      ...(r.sinceCost !== null ? [{ text: `local since ${wtokText(r.sinceCost)}`, tone: 'subtle' }] : []),
    ]
    const since = q.session.basis === 'settled' && q.session.since ? [{ text: `session since ${wtokText(q.session.since)}`, tone: 'subtle' }] : []
    const sure = [q.session, q.tools].some(f => f.basis !== 'raw')
      ? [{ text: `${r.confidence.label} · ${r.confidence.samples} sample${r.confidence.samples === 1 ? '' : 's'}`, tone: r.confidence.label === 'low' ? 'warning' : 'subtle' }]
      : []
    return [head, ...measured, ...account, ...shares, ...since, ...sure]
  })

export const QUOTA_NOTE = 'measured is the vendor percent at its own time; est adds the local tokens since, at a rate not yet fitted to your usage (uncalibrated). Other machines, the web and sessions that never ran this mod are not tied to an account, so a figure is neither exact nor an upper bound; a stale reading shows only the local tokens since it'
export const TOOLS_DIRECT_NOTE = 'tools direct: call output and the first read of its result; later cache re-reads count to the session only'
