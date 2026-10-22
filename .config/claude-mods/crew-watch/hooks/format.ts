import type { CrewEvent, CrewMember, CrewTotals, MemberQuota, QuotaProvider, QuotaShare, ToolTokens } from '../types'
import { crewState } from './dashboard'

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

/** claude-opus-5-5 -> opus-5-5; models listed by requests served. */
export const modelsText = (models: Record<string, number>): string =>
  Object.entries(models)
    .sort((a, b) => b[1] - a[1])
    .map(([model, n]) => `${model.replace(/^claude-/, '')} ×${n}`)
    .join(' · ')

export const dispatchText = (m: CrewMember): string => {
  const pinned = [m.model, m.effort].filter(v => v && v !== 'default').join('/')
  return pinned ? `${m.harness} ${pinned}` : m.harness
}

/** The one-line summary the status line carries. */
export const statusLine = (crew: readonly CrewMember[], totals: CrewTotals, now: number): string | undefined => {
  if (crew.length === 0) return undefined
  const active = crew.filter(m => ['working', 'active'].includes(crewState(m, now).label)).length
  const all = totals.input + totals.output + totals.cacheRead + totals.cacheWrite
  return `crew ${crew.length} (${active} active) · ${tokens(all)} tok · ${totals.toolCalls} tools · /crew`
}

/** Fixed-cell gauge; no control characters or raw theme colors. */
export const gauge = (pct: number, width = 8): string => {
  const size = Math.max(0, Math.floor(width))
  const filled = Number.isFinite(pct) ? Math.max(0, Math.min(size, Math.round(pct * size / 100))) : 0
  return '▰'.repeat(filled) + '▱'.repeat(size - filled)
}

export const contextText = (m: Pick<CrewMember, 'context' | 'contextWindow'>): string => {
  if (!m.contextWindow || m.contextWindow <= 0) return `ctx ${tokens(m.context)} · window unknown`
  const pct = Math.round(m.context * 100 / m.contextWindow)
  return `ctx ${gauge(pct)} ${pct}% · ${tokens(m.context)}/${tokens(m.contextWindow)}`
}

export const effortText = (effort: string): string => {
  const ranks: Record<string, number> = { minimal: 25, low: 25, medium: 50, high: 75, xhigh: 100, max: 100, ultra: 100 }
  const pct = Object.hasOwn(ranks, effort) ? ranks[effort] : undefined
  return pct === undefined ? `effort ${effort || 'default'}` : `effort ${gauge(pct, 4)} ${effort}`
}

export const clip = (text: string, width: number): string => {
  const cells = Array.from(text.replace(/[\r\n\t]+/g, ' ').trim())
  return cells.length <= width ? cells.join('') : cells.slice(0, Math.max(0, width - 1)).join('') + (width > 0 ? '…' : '')
}

export const clockText = (at: number, timeZone?: string): string => at > 0
  ? new Intl.DateTimeFormat('en-GB', { hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23', ...(timeZone ? { timeZone } : {}) }).format(new Date(at))
  : '--:--:--'

export const totalTokens = (u: CrewTotals): number => u.input + u.output + u.cacheRead + u.cacheWrite

export const cacheText = (u: CrewTotals, width = 8): string => {
  const hit = cacheHit(u)
  return `cache ${gauge(Number.parseFloat(hit), width)} ${hit} · r ${tokens(u.cacheRead)} w ${tokens(u.cacheWrite)}`
}

const percentText = (n: number): string => n > 0 && n < 0.1 ? '<0.1%' : `${n < 10 ? n.toFixed(1) : Math.round(n)}%`

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

const shareText = (s: QuotaShare): string =>
  s.percent !== null ? `${percentText(s.percent)} of week` : s.share !== null ? `${percentText(s.share * 100)} of local` : '-'

/** Where the weekly percent came from and how old it is; stale past half an hour or when its age is unknown. */
export const readingText = (info: Pick<QuotaProvider, 'source' | 'readAt'>, now: number): string =>
  `read ${info.readAt ? `${ago(now - info.readAt)} ago` : 'time unknown'} · ${info.source}`

/**
 * The plan and weekly-limit lines for one crewmate or the whole fleet. Each
 * stays within 32 cells, a collapsed card's narrowest row, so no figure is cut.
 */
export const quotaRows = (quota: Record<string, MemberQuota>, providers: Record<string, QuotaProvider>, now: number): { text: string; tone: string }[] =>
  Object.entries(quota).flatMap(([name, q]) => {
    const info = providers[name]
    const head = { text: `${name} ${info?.plan || 'plan unknown'}`, tone: 'subtle' }
    if (!info) return [head]
    if (!info.indexed) return [head, { text: 'indexing local logs…', tone: 'subtle' }]
    const shares = [{ text: `session ${shareText(q.session)}`, tone: 'text' }, { text: `tools direct ${shareText(q.tools)}`, tone: 'text' }]
    return info.percentUsed === null
      ? [head, ...shares, { text: info.reset ? 'week % unknown: window reset' : 'week % unknown', tone: 'warning' }]
      : [
          head,
          { text: `week ${percentText(info.percentUsed)} used · ${info.stale ? 'stale' : 'current'}`, tone: info.stale ? 'warning' : 'subtle' },
          { text: readingText(info, now), tone: 'subtle' },
          ...shares,
        ]
  })

export const QUOTA_NOTE = 'local logs only: other machines and the web are not seen, so with a current reading shares are upper bounds; a stale one can understate them'
export const TOOLS_DIRECT_NOTE = 'tools direct: call output and the first read of its result; later cache re-reads count to the session only'
