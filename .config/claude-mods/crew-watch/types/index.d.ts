/** One tool and how often a crewmate called it. */
export type ToolCount = { name: string; count: number }

export type CrewEvent = { at: number; kind: 'tool' | 'status'; text: string }
export type ActivityBucket = { minute: number; count: number }

/** One live Firstmate task, as scripts/crew_usage.py reports it. */
export type CrewMember = {
  id: string
  home: string
  /** 0 for the watched home's own crew, 1 for a secondmate's crew, ... */
  depth: number
  kind: string
  harness: string
  /** The model the task was dispatched with ("default" when unpinned). */
  model: string
  effort: string
  project: string
  branch: string
  worktree: string
  description: string
  /** The last line of the task's status log. */
  status: string
  statusAt: number
  /** False for a harness whose transcripts the script cannot read. */
  readable: boolean
  /** Transcript files found for the task (subagent transcripts included). */
  sessions: number
  /** Model id to the number of requests it served. */
  models: Record<string, number>
  requests: number
  input: number
  output: number
  cacheRead: number
  cacheWrite: number
  reasoning: number
  /** The latest request's whole input: its live context size. */
  context: number
  /** Null unless the transcript explicitly supplies the window. */
  contextWindow: number | null
  events: CrewEvent[]
  recentTools: CrewEvent[]
  activity: ActivityBucket[]
  tools: Record<string, number>
  toolCalls: number
  topTools: ToolCount[]
  lastTool: string
  lastText: string
  lastAt: number
}

export type CrewTotals = {
  requests: number
  input: number
  output: number
  cacheRead: number
  cacheWrite: number
  reasoning: number
  toolCalls: number
}

export type CrewReport = {
  generatedAt: number
  crew: CrewMember[]
  totals: CrewTotals
  errors: string[]
}

declare module 'claude-code' {
  interface PluginState {
    'crew-watch': {
      report: CrewReport | null
      /** Why the last poll failed; empty after a good one. */
      error: string
      expanded: string | null
    }
  }
}
