/** One tool and how often a crewmate called it. */
export type ToolCount = { name: string; count: number }

/**
 * One logged event. A tool call also carries the tokens charged to it: the
 * output of the request that emitted it plus the input its result added to
 * the next request; `estimated` marks an input guessed from the result size.
 * The token fields are absent when the transcript has no usage for the call.
 */
export type CrewEvent = {
  at: number
  kind: 'tool' | 'status'
  text: string
  tool?: string
  outTokens?: number
  inTokens?: number
  estimated?: boolean
}

/** Tokens charged to one tool's calls; `estimated` of `input` was guessed from result size. */
export type ToolTokens = { calls: number; output: number; input: number; estimated: number; estCalls: number }

/** A share of local usage (0 to 1) and, when the weekly percent is known, of the weekly limit (0 to 100). */
export type QuotaShare = { share: number | null; percent: number | null }

/** `tools` is the direct cost of the calls: later cache re-reads of their results count to `session` only. */
export type MemberQuota = { session: QuotaShare; tools: QuotaShare }

/** One provider's weekly window as local sources report it. */
export type QuotaProvider = {
  /** Plan label from local metadata, empty when none is recorded. */
  plan: string
  /** How the account signs in: token (CLAUDE_CODE_OAUTH_TOKEN, no local plan record), api-key, account, rollout (Codex), or empty. */
  login: string
  /** Null when no current reading exists. */
  percentUsed: number | null
  resetsAt: number | null
  windowStart: number
  windowStartKnown: boolean
  /** Where the reading came from, and when; readAt is null when the source does not say. */
  source: string
  readAt: number | null
  /** The reading is older than half an hour, or its age is unknown. */
  stale: boolean
  /** Readings exist but the window they describe has reset. */
  reset: boolean
  /** False while local logs are still being indexed. */
  indexed: boolean
  localCost: number
}

export type QuotaReport = {
  providers: Record<string, QuotaProvider>
  fleet: Record<string, MemberQuota>
}

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
  /** From the transcript, else the model's catalog entry; null when no source knows the model. */
  contextWindow: number | null
  /** The model that served most requests, else the dispatched one; empty before any request. */
  contextModel: string
  /** Where contextWindow came from: transcript, claude model table, codex model catalog, or empty. */
  windowSource: string
  events: CrewEvent[]
  recentTools: CrewEvent[]
  activity: ActivityBucket[]
  tools: Record<string, number>
  toolCalls: number
  toolTokens: Record<string, ToolTokens>
  topTools: ToolCount[]
  /** Estimated weekly-limit share by provider; absent for a provider the crewmate never used. */
  quota: Record<string, MemberQuota>
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
  quota: QuotaReport
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
