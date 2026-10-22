import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'

import type { CrewMember, CrewReport } from '../types'
import { accountFromLimits } from './account'
import { statusLine } from './format'
import { DEFAULT_THEME, isNoColorSet, isThemeName, isTruecolorTerm, themePainter } from './theme'
import type { Paint } from './theme'
import { isActive, memberKey, toggleExpanded } from './dashboard'
import { nextFilter } from './view'
import type { LogEntry } from './view'
import { drawPane } from './zones'

type Dollar = EngineInterface

const PANE = 'crew-watch'
const TITLE = 'Crew'
const POLL_TIMEOUT_MS = 20_000
const ACCOUNT_CACHE_MS = 60_000
/** How often a running card's border highlight moves: once a second, calm enough never to read as flicker. */
const PULSE_MS = 1000

const reportAtom = atom({ plugin: 'crew-watch', key: 'report' } as const, null)
const errorAtom = atom({ plugin: 'crew-watch', key: 'error' } as const, '')
const expandedAtom = atom({ plugin: 'crew-watch', key: 'expanded' } as const, null)
const pollAtom = atom({ plugin: 'crew-watch', key: 'poll' } as const, null)
const modeAtom = atom({ plugin: 'crew-watch', key: 'mode' } as const, 'compact')
const logsOpenAtom = atom({ plugin: 'crew-watch', key: 'logsOpen' } as const, false)
const logFilterAtom = atom({ plugin: 'crew-watch', key: 'logFilter' } as const, 'all')
const helpAtom = atom({ plugin: 'crew-watch', key: 'help' } as const, false)
const quotaInfoAtom = atom({ plugin: 'crew-watch', key: 'quotaInfo' } as const, false)
const openLogAtom = atom({ plugin: 'crew-watch', key: 'openLog' } as const, null)
const pulseAtom = atom({ plugin: 'crew-watch', key: 'pulse' } as const, null)

const HELP = [
  '/crew           open or close the Crew pane',
  '/crew refresh   re-read the crew logs now',
  '/crew help      this text',
].join('\n')

let intervalMs = 5000
let configuredHomes: string[] = []
let inFlight: Promise<void> | null = null
let accountCache: { at: number; fingerprint: string; name: string } | null = null
let themeName: string = DEFAULT_THEME
let home = ''
let paint: Paint = themePainter(DEFAULT_THEME, { isNoColor: false, isTruecolor: true })
let pulseTimer: Timer | null = null
/** Counts the timer's stops, so a start that began before a stop (the pane closing meanwhile) does not go through. */
let pulseStops = 0

/** Builds the painter from the Theme option and what the terminal says (NO_COLOR, COLORTERM). */
async function loadPaint($: Dollar): Promise<void> {
  paint = themePainter(themeName, {
    isNoColor: isNoColorSet(await $.env.get('NO_COLOR')),
    isTruecolor: isTruecolorTerm(await $.env.get('COLORTERM')),
  })
}

/** The home folder, so full paths the pane shows read `~` rather than the person's user name. */
async function loadHome($: Dollar): Promise<void> {
  home = (await $.env.get('HOME')) ?? ''
}

/** Whether the person asked Claude Code for less motion: the `prefersReducedMotion` setting (`/config`, Reduce motion). */
async function isMotionReduced($: Dollar): Promise<boolean> {
  try {
    return (await $.settings.read({ key: 'prefersReducedMotion' })) === true
  } catch {
    return false
  }
}

/** Whether the Crew pane is drawn and in front: a pane waiting undrawn or behind another tab shows no motion. */
async function isPaneShown($: Dollar): Promise<boolean> {
  try {
    return (await $.ui.panes()).some(pane => pane.id === PANE && pane.isPlaced && pane.isShown)
  } catch {
    return false
  }
}

/**
 * Runs the running border's timer only while it shows something: the pane is in front, a crewmate is
 * working or active, and motion is not reduced. Each tick moves every running card's highlight one
 * step; otherwise the timer is stopped and the frame cleared, so every border stands still.
 */
async function syncPulse($: Dollar): Promise<void> {
  const stops = pulseStops
  const report = await read($, reportAtom)
  const now = await $.clock.now()
  const isRunning = report?.crew.some(m => isActive(m, now)) ?? false
  const shouldRun = isRunning && await isPaneShown($) && !(await isMotionReduced($))
  if (!shouldRun) return stopPulse($)
  // Set before any await, so a poll and an open that both get here start one timer, not two.
  if (pulseTimer !== null || stops !== pulseStops) return
  // A tick or this first frame landing after a stop finds the frame cleared and leaves it so.
  const timer = $.clock.every(PULSE_MS, () => {
    void update($, pulseAtom, value => value === null ? null : value + 1)
  })
  pulseTimer = timer
  await update($, pulseAtom, value => pulseTimer === timer ? value ?? 0 : value)
}

/** syncPulse for a caller with other work: a failure is logged to the debug log and never fails a read or an open. */
async function checkPulse($: Dollar): Promise<void> {
  try {
    await syncPulse($)
  } catch (err) {
    $.ui.log(`crew-watch: border timer: ${err instanceof Error ? err.message : String(err)}`, { to: 'debug' })
  }
}

async function stopPulse($: Dollar): Promise<void> {
  pulseStops += 1
  pulseTimer?.cancel()
  pulseTimer = null
  await update($, pulseAtom, () => null)
}

/** Reads the crew once; a call made while a read runs waits for that read. */
function poll($: Dollar): Promise<void> {
  inFlight ??= readCrew($).finally(() => {
    inFlight = null
  })
  return inFlight
}

/** The rate-limit windows of this session's last API response, as JSON; none is fine, the script has other sources. */
async function claudeLimits($: Dollar): Promise<string> {
  try {
    return JSON.stringify((await $.session.usage()).rateLimits ?? [])
  } catch {
    return '[]'
  }
}

/**
 * How this session signs in, as `crew_usage.py --claude-login` takes it. The
 * engine keeps CLAUDE_CODE_OAUTH_TOKEN (what `ai-acct` sets) out of the script's
 * environment, so only presence is read here: the value is never kept or shown.
 */
async function claudeLogin($: Dollar): Promise<string> {
  if (await $.env.get('CLAUDE_CODE_OAUTH_TOKEN')) return 'token'
  return (await $.env.get('ANTHROPIC_API_KEY')) ? 'api-key' : ''
}

/**
 * The ai-acct account this session runs as: its AI_ACCT_FINGERPRINT (a one-way hash, never the token)
 * matched against the fingerprints beside each account's stored limits. Only the name is passed on.
 * Empty when the session has no fingerprint or no account matches; then its quota stays "unknown".
 */
async function claudeAccount($: Dollar): Promise<string> {
  try {
    const fingerprint = await $.env.get('AI_ACCT_FINGERPRINT')
    if (!fingerprint) return ''
    const now = await $.clock.now()
    if (accountCache !== null && now - accountCache.at < ACCOUNT_CACHE_MS && accountCache.fingerprint === fingerprint) return accountCache.name
    const base = (await $.env.get('XDG_CACHE_HOME')) || `${(await $.env.get('HOME')) ?? ''}/.cache`
    const dir = `${base}/ai-acct`
    const names = (await $.fs.list(dir)).map(entry => entry.name).filter(name => name.endsWith('.limits.json'))
    const files = await Promise.all(names.map(async name => ({ name, text: String(await $.fs.read(`${dir}/${name}`)) })))
    const name = accountFromLimits(fingerprint, files) ?? ''
    accountCache = { at: now, fingerprint, name }
    return name
  } catch {
    return ''
  }
}

async function readCrew($: Dollar): Promise<void> {
  let report: CrewReport
  try {
    const homes = configuredHomes.length > 0 ? configuredHomes : [await $.session.root()]
    const argv = [
      'python3',
      '-I',
      `${$.plugin.root}/scripts/crew_usage.py`,
      '--claude-limits',
      await claudeLimits($),
      '--claude-session',
      await $.session.id(),
      '--claude-login',
      await claudeLogin($),
      '--claude-account',
      await claudeAccount($),
      ...homes.flatMap(home => ['--home', home]),
    ]
    const run = await $.process.run(argv, { timeoutMs: POLL_TIMEOUT_MS })
    if (run.exitCode !== 0) {
      const why = run.stderr.trim().split('\n').pop() || `exit ${run.exitCode}`
      await update($, errorAtom, () => `crew_usage.py failed: ${why}`)
      await settle($, true)
      return
    }
    report = JSON.parse(run.stdout) as CrewReport
  } catch (err) {
    await update($, errorAtom, () => `crew poll failed: ${err instanceof Error ? err.message : String(err)}`)
    await settle($, true)
    return
  }
  await update($, reportAtom, () => report)
  await update($, errorAtom, () => report.errors.join('; '))
  await settle($, false)
  $.ui.status(statusLine(report.crew, report.totals, report.generatedAt))
}

/** Records when the read ended and whether it failed: each one redraws the pane, so its freshness moves on. */
async function settle($: Dollar, failed: boolean): Promise<void> {
  const at = await $.clock.now()
  await update($, pollAtom, () => ({ at, failed }))
  // Every read, failed or not, decides again whether the border timer runs.
  await checkPulse($)
}

export const register: Register = (on, options) => {
  intervalMs = Math.max(1, Number(options.intervalSeconds) || 5) * 1000
  const chosen = String(options.theme ?? DEFAULT_THEME)
  themeName = isThemeName(chosen) ? chosen : DEFAULT_THEME
  paint = themePainter(themeName, { isNoColor: false, isTruecolor: true })
  configuredHomes = String(options.homes ?? '')
    .split(',')
    .map(h => h.trim())
    .filter(Boolean)

  on('session.start', async ($, e, next) => {
    await loadPaint($)
    await loadHome($)
    await $.command.register({
      name: 'crew',
      description: 'Show what each Firstmate crewmate is doing: models, tokens, cache and tool calls',
      argumentHint: '[refresh|help]',
    })
    $.clock.every(intervalMs, () => poll($))
    void poll($)

    return next(e)
  })

  on('command.run', { command: 'crew' }, async ($, e) => {
    const arg = e.args.trim()
    if (arg === 'help') return { text: HELP }
    if (arg === 'refresh') {
      await poll($)
      const report = await read($, reportAtom)
      return { text: `Crew refreshed: ${report?.crew.length ?? 0} live crewmate(s).` }
    }
    if (arg !== '') return { text: `Unknown argument "${arg}".\n${HELP}` }

    const isOpen = (await $.ui.panes()).some(pane => pane.id === PANE)
    if (isOpen) {
      await $.ui.close({ id: PANE })
      return { text: 'Crew pane closed.' }
    }
    void poll($)
    await $.ui.open({ id: PANE, title: TITLE })
    await checkPulse($)

    return { text: 'Crew pane opened.' }
  })

  // However the pane closes (`/crew`, its close mark, ctrl+x x), the border timer stops with it.
  // A failure here never keeps the pane open: the close goes on.
  on('ui.close', { id: PANE }, async ($, e, next) => {
    await stopPulse($)
    return next(e)
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const view = {
      report: await read($, reportAtom),
      error: await read($, errorAtom),
      poll: await read($, pollAtom),
      expanded: await read($, expandedAtom),
      mode: await read($, modeAtom),
      logsOpen: await read($, logsOpenAtom),
      logFilter: await read($, logFilterAtom),
      help: await read($, helpAtom),
      quotaInfo: await read($, quotaInfoAtom),
      openLog: await read($, openLogAtom),
      pulse: await read($, pulseAtom),
    }
    const frame = {
      width: e.props.bodyColumns,
      rows: e.props.scroll.bodyRows,
      placement: e.props.placement,
      isFocused: e.props.isFocused,
      now: await $.clock.now(),
      // Two refreshes and one read's timeout without a new report: the data is no longer current.
      staleMs: 2 * intervalMs + POLL_TIMEOUT_MS,
      home,
    }
    return drawPane($.ui.resolve(e), paint, view, frame, {
      toggle: (m: CrewMember) => async () => {
        const next = await update($, expandedAtom, value => toggleExpanded(value, memberKey(m)))
        // The Agent filter names the open crewmate: closing it ends that filter.
        if (next === null) await update($, logFilterAtom, value => value === 'agent' ? 'all' : value)
      },
      mode: async () => {
        await update($, modeAtom, value => value === 'compact' ? 'details' : 'compact')
      },
      quotaInfo: async () => {
        await update($, quotaInfoAtom, value => !value)
      },
      logs: async () => {
        await update($, logsOpenAtom, value => !value)
      },
      openLog: (entry: LogEntry) => async () => {
        await update($, openLogAtom, value => value === entry.id ? null : entry.id)
      },
      filter: async () => {
        const expanded = await read($, expandedAtom)
        const isShown = (await read($, reportAtom))?.crew.some(m => memberKey(m) === expanded) ?? false
        await update($, logFilterAtom, value => nextFilter(value, isShown))
      },
      help: async () => {
        await update($, helpAtom, value => !value)
      },
    })
  })
}
