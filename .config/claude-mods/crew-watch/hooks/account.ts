/** The ai-acct account a session runs as, found without opening any token file. */

type Json = Record<string, unknown>

const isObject = (value: unknown): value is Json =>
  typeof value === 'object' && value !== null && !Array.isArray(value)

/** An ai-acct account name; `unknown` is reserved for a session of no known account. */
export const ACCOUNT_NAME = /^[a-z0-9][a-z0-9_-]{0,31}$/

/**
 * `agent-statusline-claude` records, per account, the rate limits a process of that account was
 * given, beside a one-way fingerprint of its token (never the token). `ai-acct` exports the same
 * fingerprint to its sessions as AI_ACCT_FINGERPRINT. Matching the two names the account; only the
 * name leaves this function, so no fingerprint is passed on, stored or shown.
 */
export const accountFromLimits = (
  fingerprint: string | undefined,
  files: readonly { name: string; text: string }[],
): string | undefined => {
  if (fingerprint === undefined || !/^[0-9a-f]{64}$/.test(fingerprint)) return undefined
  for (const file of files) {
    const name = /^claude-(.+)\.limits\.json$/.exec(file.name)?.[1]
    if (name === undefined || name === 'unknown' || !ACCOUNT_NAME.test(name)) continue
    try {
      const record: unknown = JSON.parse(file.text)
      if (isObject(record) && record.fingerprint === fingerprint) return name
    } catch {
      continue
    }
  }
  return undefined
}
