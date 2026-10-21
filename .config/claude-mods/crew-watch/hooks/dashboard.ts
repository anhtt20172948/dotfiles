/** Pure dashboard geometry and reducers. No engine calls or UI elements. */
import type { ActivityBucket, CrewEvent, CrewMember } from '../types'

/** A report saved before dashboard fields existed can still draw during reload. */
export const normalizeMember = (m: CrewMember): CrewMember => ({
  ...m,
  description: m.description || m.id,
  worktree: m.worktree || '',
  contextWindow: m.contextWindow ?? null,
  events: m.events ?? [],
  recentTools: m.recentTools ?? (m.events ?? []).filter(event => event.kind === 'tool').slice(-5),
  activity: m.activity ?? [],
  tools: m.tools ?? Object.fromEntries(m.topTools.map(t => [t.name, t.count])),
})

export const memberKey = (m: Pick<CrewMember, 'home' | 'id'>): string => `${m.home}:${m.id}`

export const toggleExpanded = (current: string | null, key: string): string | null => current === key ? null : key

export const dashboardLayout = (width: number, placement: string, count: number) => {
  const columns = Math.max(1, Math.min(count, Math.floor((width + 1) / 37)))
  return {
    mode: placement === 'inline' ? 'mini' as const : count > columns ? 'lanes' as const : 'cards' as const,
    columns,
    cardWidth: Math.floor((width - columns + 1) / columns),
    shown: placement === 'inline' ? Math.min(count, 3) : count,
  }
}

export const harnessColor = (harness: string): string =>
  harness.startsWith('claude') ? 'claude' : harness === 'codex' ? 'suggestion' : harness === 'pi' ? 'merged' : 'permission'

export const activityState = (lastAt: number, now: number): { mark: string; label: string; color: string } => {
  const age = lastAt > 0 ? Math.max(0, now - lastAt) : Infinity
  return age < 120000 ? { mark: '●', label: 'active', color: 'success' }
    : age < 900000 ? { mark: '◐', label: 'quiet', color: 'warning' }
      : { mark: '○', label: 'stale', color: 'subtle' }
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

type LogSource = Pick<CrewMember, 'home' | 'id' | 'harness'> & { events: readonly CrewEvent[] }
export const recentLog = (crew: readonly LogSource[], limit = 8) =>
  crew.flatMap(m => m.events.map(event => ({ ...event, who: m.id, key: memberKey(m), color: harnessColor(m.harness) })))
    .sort((a, b) => a.at - b.at || a.key.localeCompare(b.key)).slice(-Math.max(1, limit))

export const sortedTools = (tools: Readonly<Record<string, number>>) =>
  Object.entries(tools).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
