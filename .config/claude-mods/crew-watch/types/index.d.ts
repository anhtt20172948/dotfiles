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

/**
 * One quota figure of a crewmate (or the fleet) against one account's weekly limit. `share` is its
 * fraction of that account's local usage in the window (0 to 1). `percent` is points of the week:
 * the points settled by past rises of the vendor percent (`settled`) plus, while the reading is
 * current, the open interval priced by an uncalibrated slope (`open`). `since` is the weighted
 * tokens it spent after the reading; null when the reading's time is unknown.
 * `basis`: estimated (settled + open), settled (a stale reading: nothing extrapolated), raw (no
 * usable reading: only `share` is meaningful).
 */
export type QuotaFigure = {
  share: number | null
  percent: number | null
  settled: number | null
  open: number | null
  since: number | null
  basis: 'estimated' | 'settled' | 'raw'
}

/** `tools` is the direct cost of the calls: later cache re-reads of their results count to `session` only. */
export type MemberQuota = { session: QuotaFigure; tools: QuotaFigure }

/** How far the forecast can be trusted: the evidence is the residuals recorded when a reading met its forecast. */
export type Confidence = { label: 'uncalibrated' | 'low' | 'calibrated'; samples: number }

/**
 * An account's 5-hour window as the vendor last reported it: shown beside the weekly one, never
 * estimated. `reset` marks a reading whose window has passed, so its percent says nothing now.
 */
export type FiveHourReading = {
  percent: number | null
  resetsAt: number | null
  observedAt: number | null
  /** session, account cache or codex log; empty once the window has reset. */
  source: string
  stale: boolean
  reset: boolean
}

/**
 * One account's weekly window for one provider and scope, keyed `provider|account|scope`. The account
 * is the ai-acct name (Claude), a hash of the rollout's creator id (Codex) or `unknown`.
 */
export type QuotaReading = {
  provider: string
  account: string
  /** False for `unknown`: no percent is ever attached to it. */
  accountKnown: boolean
  scope: string
  /** Plan label from local metadata, empty when none is recorded. */
  plan: string
  /** How the pane signs in (Claude only): token, api-key, account; rollout for Codex; else empty. */
  login: string
  /** The vendor's percent at `observedAt`; null when no reading is in force. */
  percent: number | null
  /** When the response that carried the reading was logged; null when that is not known. */
  observedAt: number | null
  /** session, history, account cache or codex log; empty without a reading. */
  source: string
  resetsAt: number | null
  windowMs: number
  windowStart: number
  windowStartKnown: boolean
  /** Older than half an hour, or of unknown age: kept with its time, never called current. */
  stale: boolean
  /** Readings exist but the window they describe has reset. */
  reset: boolean
  /** False while local logs are still being indexed. */
  indexed: boolean
  /** The account's weighted tokens since the window started. */
  localCost: number
  /** The account's weighted tokens since the reading; null when its time is unknown. */
  sinceCost: number | null
  /** The reading plus what those tokens cost at the period's own rate; null without a slope, and when stale unless the forecast is calibrated and the reading under 2 hours old. */
  forecast: number | null
  confidence: Confidence
  /** The same account's 5-hour window; null when no source has one for it. */
  fiveHour: FiveHourReading | null
}

export type QuotaReport = {
  readings: Record<string, QuotaReading>
  fleet: Record<string, MemberQuota>
}

export type ActivityBucket = { minute: number; count: number }

/** Tokens one model served: its requests, uncached input, output, cache read and write, and the thinking inside output. */
export type ModelTokens = { requests: number; input: number; output: number; cacheRead: number; cacheWrite: number; reasoning: number }

/** One model's sums over a window of the crew ledger: `crewmates` is how many tasks it served there. */
export type ModelUsage = ModelTokens & { model: string; provider: string; crewmates: number }

/**
 * The crew ledger summed per model over one window: `week` counts requests since each account's dated
 * quota-week boundary, `all` every record kept (90 days after last seen). `finished` and `live` count
 * crewmates in the window; `unreadable` have no usage, `unwindowed` lack a dated quota week.
 */
export type HistoryWindow = { window: 'week' | 'all'; models: ModelUsage[]; finished: number; live: number; unreadable: number; unwindowed: number; crewmates: number; measured: number }

export type CrewHistory = { week: HistoryWindow; all: HistoryWindow }

/** Which window the Usage by Model zone sums: the quota week or all time (`u`). */
export type UsageWindow = HistoryWindow['window']

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
  /** Model id to the tokens it served; they add up to the crewmate's totals. */
  modelTokens: Record<string, ModelTokens>
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
  /** Weekly-limit figures by `provider|account|scope`; absent for an account the crewmate never used. */
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
  /** Live and torn-down crewmates of the watched homes, from the crew ledger. */
  history: CrewHistory
  errors: string[]
}

/** How much each zone shows: `compact` scans, `details` adds the level-C figures. */
export type ViewMode = 'compact' | 'details'

/** Which log entries the Recent Logs zone lists; `agent` is the crewmate whose details are open. */
export type LogFilter = 'all' | 'tools' | 'status' | 'errors' | 'agent'

/**
 * The end of the last read: whether it failed (the report then is the last good one) and when it
 * settled. Each read writes a new `at`, so the pane redraws and its freshness moves on.
 */
export type PollState = { at: number; failed: boolean }

declare module 'claude-code' {
  interface PluginState {
    'crew-watch': {
      report: CrewReport | null
      /** Why the last poll failed, or the report's own warnings; empty after a clean one. */
      error: string
      expanded: string | null
      poll: PollState | null
      mode: ViewMode
      logsOpen: boolean
      logFilter: LogFilter
      help: boolean
      /** Quota & Limits shows each account's notes (`i`). */
      quotaInfo: boolean
      /** The log entry whose full text is shown, by its id; null for none. */
      openLog: string | null
      /** The running border's frame while its timer runs; null while it is stopped (no pane, nothing running, reduced motion). */
      pulse: number | null
      /** The window Usage by Model sums (`u`). */
      usageWindow: UsageWindow
    }
  }
}
