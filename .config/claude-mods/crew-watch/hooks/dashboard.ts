/** Pure dashboard geometry and reducers. No engine calls or UI elements. */
import type { ActivityBucket, CrewMember } from '../types'

export const memberKey = (m: Pick<CrewMember, 'home' | 'id'>): string => `${m.home}:${m.id}`

export const toggleExpanded = (current: string | null, key: string): string | null => current === key ? null : key

export const harnessColor = (harness: string): string =>
  harness.startsWith('claude') ? 'claude' : harness === 'codex' ? 'suggestion' : harness === 'pi' ? 'merged' : 'permission'

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

/** The axis gutter is the same geometry as each mark, name and explicit gap. */
export const laneGeometry = (width: number) => {
  const markWidth = 2
  const nameWidth = 16
  const gap = 1
  const offset = markWidth + nameWidth + gap
  const cells = Math.max(4, Math.min(60, width - offset - 10))
  const start = `-${cells - 1}m`
  const axis = start.padEnd(Math.max(start.length, cells - 3), ' ').slice(0, cells - 3) + 'now'
  return { markWidth, nameWidth, gap, offset, cells, axis }
}

/** Every lane ends in the same current minute; at most 60 cells, one per minute. */
export const activityLane = (activity: readonly ActivityBucket[], now: number, width: number): string => {
  const cells = Math.max(1, Math.min(60, Math.floor(width)))
  const end = Math.floor(now / 60000)
  const counts = new Map(activity.map(b => [b.minute, b.count]))
  return Array.from({ length: cells }, (_, i) => (counts.get(end - cells + i + 1) ?? 0) > 0 ? '▰' : '·').join('')
}

type ModelSource = { models: Readonly<Record<string, number>> }
export const fleetModels = (crew: readonly ModelSource[]): [string, number][] => {
  const totals = crew.reduce<Record<string, number>>((sum, m) =>
    Object.entries(m.models).reduce((next, [model, n]) => ({ ...next, [model]: (next[model] ?? 0) + n }), sum), {})
  return Object.entries(totals).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
}

export const sortedTools = (tools: Readonly<Record<string, number>>) =>
  Object.entries(tools).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
