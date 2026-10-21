import type { Fleet, FleetRow } from '../../types'

/** One cell wide: Text with `wrap="truncate-end"` draws the same mark. */
const ELLIPSIS = '…'
const GAP = 2

export const clip = (value: string, width: number): string => {
  if (width <= 0) {
    return ''
  }

  return value.length > width ? value.slice(0, width - 1) + ELLIPSIS : value
}

export const pad = (value: string, width: number): string => clip(value, width).padEnd(width)

export type Segment = { text: string; tone: 'plain' | 'dim' | 'accent' | 'warn' }

const plural = (n: number, one: string, many: string): string => `${n} ${n === 1 ? one : many}`

/** The band's pieces in priority order: the last ones are dropped first. */
export const bandSegments = (fleet: Fleet): Segment[] => {
  const segments: Segment[] = []

  if (fleet.attention > 0) {
    segments.push({ text: `${fleet.attention} need${fleet.attention === 1 ? 's' : ''} you`, tone: 'warn' })
  }
  if (fleet.running > 0) {
    segments.push({ text: plural(fleet.running, 'worker', 'workers'), tone: 'plain' })
  }
  if (fleet.prs > 0) {
    segments.push({ text: plural(fleet.prs, 'PR waiting', 'PRs waiting'), tone: 'accent' })
  }

  return segments
}

const SEPARATOR = ' · '
export const BAND_LABEL = 'fleet'

/** Segments that fit in `columns`, joined by the separator, label first. */
export const fitSegments = (segments: Segment[], columns: number): Segment[] => {
  const kept = [...segments]
  const width = (list: Segment[]): number =>
    BAND_LABEL.length +
    list.reduce((sum, segment) => sum + SEPARATOR.length + segment.text.length, 0)

  while (kept.length > 1 && width(kept) > columns) {
    kept.pop()
  }

  return kept
}

export type Column = { key: 'id' | 'state' | 'pr' | 'project'; title: string; width: number }

const STATE_WIDTH = 8
const PR_WIDTH = 6
const MIN_ID = 10
const ID_CAP = 30
const MIN_PROJECT = 8
export const MIN_PANE_COLUMNS = 40

const TITLES = { id: 'WORKER', project: 'PROJECT', state: 'STATE', pr: 'PR' }

/**
 * Columns for `columns` cells. The worker id is what the eye needs, so PROJECT
 * only appears when the id keeps its full width beside it, and PR goes next.
 */
export const columnsFor = (columns: number, rows: FleetRow[]): Column[] => {
  const widest = (pick: (row: FleetRow) => string, title: string): number =>
    rows.reduce((max, row) => Math.max(max, pick(row).length), title.length)
  const idWanted = Math.min(Math.max(MIN_ID, widest(row => row.id, TITLES.id)), ID_CAP)
  const projectWanted = Math.max(MIN_PROJECT, widest(row => row.project, TITLES.project))
  const layouts: Column['key'][][] = [
    ['id', 'project', 'state', 'pr'],
    ['id', 'state', 'pr'],
    ['id', 'state'],
  ]

  for (const keys of layouts) {
    const fixed = (keys.includes('state') ? STATE_WIDTH : 0) + (keys.includes('pr') ? PR_WIDTH : 0)
    const room = columns - fixed - (keys.length - 1) * GAP
    const hasProject = keys.includes('project')

    if (room < (hasProject ? idWanted + MIN_PROJECT : MIN_ID) && keys.length > 2) {
      continue
    }

    const id = hasProject ? idWanted : Math.max(MIN_ID, Math.min(room, idWanted))
    const widths = {
      id,
      project: hasProject ? Math.min(projectWanted, room - id) : 0,
      state: STATE_WIDTH,
      pr: PR_WIDTH,
    }

    return keys.map(key => ({ key, title: TITLES[key], width: widths[key] }))
  }

  return [{ key: 'id', title: TITLES.id, width: Math.max(columns, 1) }]
}

export const cell = (row: FleetRow, key: Column['key']): string =>
  key === 'pr' ? (row.pr ?? '') : row[key]

export const rowText = (row: FleetRow, columns: Column[]): string =>
  columns.map(column => pad(cell(row, column.key), column.width)).join(' '.repeat(GAP)).trimEnd()
