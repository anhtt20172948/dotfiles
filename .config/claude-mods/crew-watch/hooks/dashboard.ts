/** Pure dashboard geometry and reducers. No engine calls or UI elements. */
import type { ActivityBucket, CrewMember } from '../types'

export const memberKey = (m: Pick<CrewMember, 'home' | 'id'>): string => `${m.home}:${m.id}`

export const toggleExpanded = (current: string | null, key: string): string | null => current === key ? null : key

export const activityState = (lastAt: number, now: number): { mark: string; label: string; color: string } => {
  const age = lastAt > 0 ? Math.max(0, now - lastAt) : Infinity
  return age < 120000 ? { mark: '●', label: 'active', color: 'success' }
    : age < 900000 ? { mark: '◐', label: 'quiet', color: 'warning' }
      : { mark: '○', label: 'stale', color: 'subtle' }
}

/** A terminal status remains authoritative while the worker awaits its supervisor. */
export const crewState = (m: Pick<CrewMember, 'lastAt' | 'status'>, now: number) => {
  const status = /^\s*([a-z-]+)\b/i.exec(m.status)?.[1]?.toLowerCase()
  if (status === 'done') return { mark: '✓', label: 'done · waiting for firstmate', color: 'success' }
  if (status === 'blocked' || status === 'failed' || status === 'needs-decision') return { mark: '×', label: 'blocked', color: 'error' }
  if (status === 'paused' || status === 'waiting') return { mark: '◷', label: 'paused / waiting', color: 'permission' }
  const idle = activityState(m.lastAt, now)
  return status === 'working' && idle.label === 'active' ? { ...idle, label: 'working' } : idle
}

/** Counted as active: the working and active states, never quiet, stale, blocked or done. */
export const isActive = (m: Pick<CrewMember, 'lastAt' | 'status'>, now: number): boolean =>
  ['working', 'active'].includes(crewState(m, now).label)

/** Bar heights in eighths of a cell, from none to full. */
const BLOCKS = [' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'] as const

/**
 * The crew's logged events per minute over the last `minutes` minutes, oldest first and ending in the
 * current minute: every crewmate's buckets added together. Buckets outside the window are left out.
 */
export const activityCounts = (activity: readonly (readonly ActivityBucket[])[], now: number, minutes: number): number[] => {
  const size = Math.max(1, Math.min(60, Math.floor(minutes)))
  const first = Math.floor(now / 60000) - size + 1
  return activity.flat().reduce((counts, b) => {
    const at = b.minute - first
    return at >= 0 && at < size && b.count > 0 ? counts.map((n, i) => i === at ? n + b.count : n) : counts
  }, Array.from({ length: size }, () => 0))
}

/** One column of the chart: a glyph per row, top first, and whether its minute had activity. */
export type ChartColumn = { glyphs: string[]; busy: boolean }

/**
 * A bar chart `rows` cells tall, one column per minute, each bar scaled to the busiest minute. A
 * minute with activity is at least two eighths tall, so it never reads as the one-eighth baseline
 * (`▁`) a quiet minute draws.
 */
export const activityChart = (counts: readonly number[], rows: number): ChartColumn[] => {
  const height = Math.max(1, Math.floor(rows))
  const peak = Math.max(0, ...counts)
  return counts.map(count => {
    const eighths = count > 0 && peak > 0 ? Math.max(2, Math.round(count * height * 8 / peak)) : 1
    const glyphs = Array.from({ length: height }, (_, r) => BLOCKS[Math.max(0, Math.min(8, eighths - (height - 1 - r) * 8))] ?? ' ')
    return { glyphs, busy: count > 0 }
  })
}

type ModelSource = { models: Readonly<Record<string, number>> }
export const fleetModels = (crew: readonly ModelSource[]): [string, number][] => {
  const totals = crew.reduce<Record<string, number>>((sum, m) =>
    Object.entries(m.models).reduce((next, [model, n]) => ({ ...next, [model]: (next[model] ?? 0) + n }), sum), {})
  return Object.entries(totals).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
}

export const sortedTools = (tools: Readonly<Record<string, number>>) =>
  Object.entries(tools).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
