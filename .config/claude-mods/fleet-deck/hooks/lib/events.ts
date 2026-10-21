import type { FleetEvent, Track } from '../../types'
import { clip } from './layout'

// A toast is a narrow box: a long worker id must not push the sentence onto two lines.
const TOAST_ID_WIDTH = 22

/**
 * What changed between two polls. Keys name the thing that happened (a worker
 * generation, a PR, a merge) rather than the poll, so a repeat is recognisable.
 */
export const diffEvents = (prev: Track, next: Track): FleetEvent[] => {
  const events: FleetEvent[] = []

  for (const [id, before] of Object.entries(prev.tasks)) {
    const after = next.tasks[id]
    const gen = before.gen

    if (after === undefined || (after.state === 'done' && before.state !== 'done')) {
      events.push({ key: `finished:${id}:${gen}`, kind: 'finished', id, detail: null })
    } else if (after.state === 'failed' && before.state !== 'failed') {
      events.push({ key: `failed:${id}:${gen}`, kind: 'failed', id, detail: null })
    }
  }

  for (const [id, after] of Object.entries(next.tasks)) {
    const before = prev.tasks[id]

    if (after.pr !== null && after.pr !== before?.pr && before !== undefined) {
      events.push({ key: `pr:${id}:${after.pr}`, kind: 'pr', id, detail: after.pr })
    }
  }

  const known = new Set(prev.merged)

  for (const id of next.merged) {
    if (!known.has(id)) {
      const pr = prev.tasks[id]?.pr ?? null

      events.push({ key: `merged:${id}`, kind: 'merged', id, detail: pr })
    }
  }

  return events
}

export const eventText = (event: FleetEvent): string => {
  const id = clip(event.id, TOAST_ID_WIDTH)
  const pr = event.detail === null ? '' : ` ${event.detail}`

  switch (event.kind) {
    case 'finished':
      return `${id} finished`
    case 'pr':
      return `${id}: PR${pr} ready`
    case 'merged':
      return `${id}: merge landed${pr}`
    case 'failed':
      return `${id} failed`
  }
}
