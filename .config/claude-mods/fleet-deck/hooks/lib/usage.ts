import type { Usage } from '../../types'

type Json = Record<string, unknown>

const isObject = (value: unknown): value is Json =>
  typeof value === 'object' && value !== null && !Array.isArray(value)

const percent = (value: unknown): number | null =>
  typeof value === 'number' && value >= 0 && value <= 100 ? Math.round(value) : null

/** `claude-opus-4-7[1m]` becomes `opus 4.7`. */
export const modelLabel = (id: string): string => {
  const bare = id.replace(/\[.*\]$/, '').replace(/^claude-/, '').replace(/-\d{8}$/, '')

  return bare.replace(/-(\d+)-(\d+)$/, ' $1.$2').replace(/-(\d+)$/, ' $1')
}

/**
 * agent-statusline-claude records, per account, the rate limits Claude Code gave
 * a process of that account, keyed by a one-way fingerprint (never a token).
 * `ai-acct` exports the same fingerprint as AI_ACCT_FINGERPRINT.
 */
export const accountFromLimits = (
  fingerprint: string | undefined,
  files: { name: string; text: string }[],
): { account: string; fiveHour: number | null; sevenDay: number | null } | null => {
  if (fingerprint === undefined || !/^[0-9a-f]{64}$/.test(fingerprint)) {
    return null
  }

  for (const file of files) {
    const name = /^claude-([a-z0-9][a-z0-9_-]*)\.limits\.json$/.exec(file.name)?.[1]

    if (name === undefined) {
      continue
    }

    try {
      const record: unknown = JSON.parse(file.text)
      const windows = isObject(record) && isObject(record.windows) ? record.windows : {}
      const used = (name: string): number | null =>
        isObject(windows[name]) ? percent((windows[name] as Json).used) : null

      if (isObject(record) && record.fingerprint === fingerprint) {
        return {
          account: name,
          fiveHour: used('five_hour'),
          sevenDay: used('seven_day'),
        }
      }
    } catch {
      continue
    }
  }

  return null
}

export type LiveLimit = { kind: string; percentUsed: number }

/** Live figures win; the cache only fills a window the engine has not reported yet. */
export const mergeUsage = (
  account: { account: string; fiveHour: number | null; sevenDay: number | null } | null,
  live: LiveLimit[],
): Usage => {
  const pick = (kind: string): number | null =>
    percent(live.find(limit => limit.kind === kind)?.percentUsed)

  return {
    account: account?.account ?? null,
    fiveHour: pick('five_hour') ?? account?.fiveHour ?? null,
    sevenDay: pick('seven_day') ?? account?.sevenDay ?? null,
  }
}

export const statusText = (model: string, contextPercent: number | undefined, usage: Usage): string => {
  const quota = [
    usage.fiveHour === null ? null : `5h ${usage.fiveHour}%`,
    usage.sevenDay === null ? null : `7d ${usage.sevenDay}%`,
  ].filter((part): part is string => part !== null)
  const account = usage.account === null ? [] : [usage.account]

  return [
    modelLabel(model),
    contextPercent === undefined ? null : `ctx ${Math.round(contextPercent)}%`,
    [...account, ...quota].join(' ') || null,
  ]
    .filter((part): part is string => part !== null && part !== '')
    .join(' · ')
}
