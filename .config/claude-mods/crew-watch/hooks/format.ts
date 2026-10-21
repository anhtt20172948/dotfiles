import type { CrewMember, CrewTotals } from '../types'
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
