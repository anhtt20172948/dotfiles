import type { Fleet, FleetRow, Track } from '../../types'

// Reads the `fm-fleet-snapshot.v1` object of a Firstmate home. Every field is
// optional on purpose: a shape this does not recognise yields null, never a throw.

type Json = Record<string, unknown>

const MAX_ROWS = 200
const ATTENTION_STATES = new Set(['blocked', 'failed'])

const isObject = (value: unknown): value is Json =>
  typeof value === 'object' && value !== null && !Array.isArray(value)

const text = (value: unknown): string | null =>
  typeof value === 'string' && value !== '' ? value : null

const field = (value: unknown, name: string): unknown =>
  isObject(value) ? value[name] : undefined

const basename = (path: string | null): string =>
  path === null ? '' : (path.replace(/\/+$/, '').split('/').pop() ?? '')

/** `https://github.com/o/r/pull/33` becomes `#33`; anything else is dropped. */
export const prLabel = (url: string | null): string | null => {
  const match = url === null ? null : /\/pull\/(\d+)/.exec(url)

  return match === null ? null : `#${match[1]}`
}

const needsCaptain = (task: Json, state: string): boolean => {
  const hints = field(task, 'hints')
  const open = field(hints, 'open_decisions')

  return (
    ATTENTION_STATES.has(state) ||
    field(hints, 'pending_decision') === true ||
    field(hints, 'blocked_event') === true ||
    (Array.isArray(open) && open.length > 0)
  )
}

const rank = (row: FleetRow): number =>
  row.needsCaptain ? 0 : row.state === 'working' ? 1 : row.state === 'done' ? 3 : 2

export type Parsed = { fleet: Fleet; track: Track }

export const parseSnapshot = (raw: unknown): Parsed | null => {
  if (!isObject(raw) || raw.schema !== 'fm-fleet-snapshot.v1' || !Array.isArray(raw.tasks)) {
    return null
  }

  const rows: FleetRow[] = []
  const tasks: Track['tasks'] = {}

  for (const task of raw.tasks) {
    const id = text(field(task, 'id'))

    if (id === null) {
      continue
    }

    const state = text(field(field(task, 'current_state'), 'state')) ?? 'unknown'
    const url = text(field(field(task, 'pr'), 'url'))
    const pr = prLabel(url)
    const gen = text(field(task, 'spawn_gen')) ?? ''

    tasks[id] = { state, pr, gen }
    rows.push({
      id,
      project: basename(text(field(task, 'project'))),
      state,
      pr,
      needsCaptain: needsCaptain(task as Json, state),
    })
  }

  const records = Array.isArray(field(field(raw, 'backlog'), 'records'))
    ? (field(field(raw, 'backlog'), 'records') as unknown[])
    : []
  const merged: string[] = []
  const heldIds = new Set<string>()

  for (const record of records) {
    const id = text(field(record, 'id'))

    if (id === null) {
      continue
    }
    if (text(field(record, 'merged')) !== null) {
      merged.push(id)
    }
    if (field(record, 'captain_actionable') === true) {
      heldIds.add(id)
    }
  }

  for (const row of rows) {
    if (row.needsCaptain) {
      heldIds.add(row.id)
    }
  }

  rows.sort((a, b) => rank(a) - rank(b) || a.id.localeCompare(b.id))

  return {
    fleet: {
      running: rows.filter(row => row.state === 'working').length,
      prs: rows.filter(row => row.pr !== null && row.state !== 'done').length,
      attention: heldIds.size,
      rows: rows.slice(0, MAX_ROWS),
    },
    track: { tasks, merged },
  }
}
