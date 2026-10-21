export type FleetRow = {
  id: string
  project: string
  state: string
  pr: string | null
  needsCaptain: boolean
}

export type Fleet = {
  running: number
  prs: number
  attention: number
  rows: FleetRow[]
}

/** What the next poll is compared with: one entry per live task, plus merged ids. */
export type Track = {
  tasks: Record<string, { state: string; pr: string | null; gen: string }>
  merged: string[]
}

export type FleetEventKind = 'finished' | 'pr' | 'merged' | 'failed'

export type FleetEvent = {
  /** Stable per event, so the same event is never announced twice. */
  key: string
  kind: FleetEventKind
  id: string
  /** `#33` for a PR event. */
  detail: string | null
}

export type Usage = {
  account: string | null
  fiveHour: number | null
  sevenDay: number | null
}

declare module 'claude-code' {
  interface PluginState {
    'fleet-deck': { fleet: Fleet | null; track: Track | null }
  }
}
