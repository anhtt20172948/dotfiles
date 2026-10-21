import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Fleet, FleetEvent, Track } from '../types'
import { diffEvents, eventText } from './lib/events'
import {
  BAND_LABEL,
  MIN_PANE_COLUMNS,
  bandSegments,
  cell,
  columnsFor,
  fitSegments,
  pad,
} from './lib/layout'
import type { Segment } from './lib/layout'
import { parseSnapshot } from './lib/snapshot'
import type { Parsed } from './lib/snapshot'
import { accountFromLimits, mergeUsage, statusText } from './lib/usage'
import type { LiveLimit } from './lib/usage'

type Dollar = EngineInterface

const PANE = 'fleet'
const POLL_MS = 20_000
const SHARED_MS = 10_000
const SNAPSHOT_TIMEOUT_MS = 8_000
const FAILURES_BEFORE_CLEAR = 3
const ACCOUNT_CACHE_MS = 60_000
const MIN_OPEN_COLUMNS = 110
const MAX_TOASTS = 3
const TOAST_MS = 6_000
const SEEN_LIMIT = 200
const DEFAULT_HOME = '.local/share/firstmate'
const PLAYERS: readonly (readonly string[])[] = [['paplay'], ['pw-play'], ['ffplay', '-nodisp', '-autoexit', '-loglevel', 'quiet']]

const fleetAtom = atom({ plugin: 'fleet-deck', key: 'fleet' } as const, null)
const trackAtom = atom({ plugin: 'fleet-deck', key: 'track' } as const, null)

type Shared = { at: number; home: string } & Parsed
type Tone = Segment['tone'] | 'ok' | 'bad'

let script: string | null = null
let home = ''
let isRunning = false
let failures = 0
let noColor = false
let platform = ''
let account: { at: number; value: ReturnType<typeof accountFromLimits> } | null = null
const seen = new Set<string>()

type Options = { toasts?: unknown; sound?: unknown; status?: unknown }

// Theme keys only: the terminal's theme decides the actual colours.
const tone = (name: Tone) => {
  const bright = name === 'warn' || name === 'bad'

  if (noColor) {
    return bright ? { bold: true } : name === 'dim' ? { dimColor: true } : {}
  }

  switch (name) {
    case 'dim':
      return { dimColor: true }
    case 'accent':
      return { color: 'suggestion' }
    case 'warn':
      return { color: 'warning' }
    case 'ok':
      return { color: 'success' }
    case 'bad':
      return { color: 'error' }
    default:
      return {}
  }
}

const readAccount = async ($: Dollar) => {
  const now = await $.clock.now()

  if (account !== null && now - account.at < ACCOUNT_CACHE_MS) {
    return account.value
  }

  let value: ReturnType<typeof accountFromLimits> = null

  try {
    const [fingerprint, cache, userHome] = await Promise.all([
      $.env.get('AI_ACCT_FINGERPRINT'),
      $.env.get('XDG_CACHE_HOME'),
      $.env.get('HOME'),
    ])
    const dir = `${cache ?? `${userHome ?? ''}/.cache`}/ai-acct`
    const names = (await $.fs.list(dir)).map(entry => entry.name).filter(name => name.endsWith('.limits.json'))
    const files = await Promise.all(
      names.map(async name => ({ name, text: String(await $.fs.read(`${dir}/${name}`)) })),
    )

    value = accountFromLimits(fingerprint, files)
  } catch {
    value = null
  }

  account = { at: now, value }

  return value
}

const refreshStatus = async (
  $: Dollar,
  options: Options,
  context: { percent?: number },
  limits: LiveLimit[],
) => {
  // The engine keeps a pinned status across reloads, so turning it off clears it.
  if (options.status === false) {
    $.ui.status(undefined)

    return
  }

  try {
    const usage = mergeUsage(await readAccount($), limits)

    $.ui.status(statusText(await $.session.model(), context.percent, usage))
  } catch {
    $.ui.status(undefined)
  }
}

const chime = async ($: Dollar) => {
  const file = `${$.plugin.root}/sounds/chime.wav`

  try {
    if (platform === 'Darwin') {
      await $.audio.play({ asset: 'sounds/chime.wav' })

      return
    }

    for (const player of PLAYERS) {
      const run = await $.process.run([...player, file], { timeoutMs: 5_000 }).catch(() => null)

      if (run?.exitCode === 0) {
        return
      }
    }
  } catch {
    // A chime is a courtesy: never an error.
  }
}

const announce = async ($: Dollar, track: Track, options: Options) => {
  const prev = await read($, trackAtom)

  await update($, trackAtom, () => track)

  if (prev === null) {
    return
  }

  const fresh = diffEvents(prev, track).filter(event => !seen.has(event.key))

  for (const event of fresh) {
    seen.add(event.key)
  }
  for (const key of [...seen].slice(0, Math.max(seen.size - SEEN_LIMIT, 0))) {
    seen.delete(key)
  }
  if (fresh.length === 0) {
    return
  }
  if (options.toasts !== false) {
    toast($, fresh)
  }
  if (options.sound === true) {
    await chime($)
  }
}

const toast = ($: Dollar, events: FleetEvent[]) => {
  for (const event of events.slice(0, MAX_TOASTS)) {
    $.ui.toast(eventText(event), { timeoutMs: TOAST_MS })
  }
  if (events.length > MAX_TOASTS) {
    $.ui.toast(`+${events.length - MAX_TOASTS} more fleet events`, { timeoutMs: TOAST_MS })
  }
}

const fetchSnapshot = async ($: Dollar, now: number): Promise<Parsed> => {
  // Another session may have polled a moment ago: share its answer.
  const shared = (await $.store.get('snapshot')) as Shared | undefined

  if (shared !== undefined && shared.home === home && now - shared.at < SHARED_MS) {
    return shared
  }

  const run = await $.process.run([script as string, '--json'], {
    cwd: home,
    env: { FM_HOME: home },
    timeoutMs: SNAPSHOT_TIMEOUT_MS,
  })
  const parsed = run.exitCode === 0 ? parseSnapshot(JSON.parse(run.stdout)) : null

  if (parsed === null) {
    throw new Error('fleet snapshot unavailable')
  }

  await $.store.set('snapshot', { at: now, home, ...parsed })

  return parsed
}

const poll = async ($: Dollar, options: Options) => {
  if (isRunning) {
    return
  }

  isRunning = true

  try {
    const parsed = await fetchSnapshot($, await $.clock.now())

    failures = 0
    await update($, fleetAtom, () => parsed.fleet)
    await announce($, parsed.track, options)
  } catch {
    failures += 1

    if (failures >= FAILURES_BEFORE_CLEAR) {
      await update($, fleetAtom, () => null)
      await update($, trackAtom, () => null)
    }
  } finally {
    isRunning = false
  }
}

const findScript = async ($: Dollar): Promise<boolean> => {
  const fromEnv = await $.env.get('FM_HOME')
  const userHome = await $.env.get('HOME')

  home = fromEnv ?? `${userHome ?? ''}/${DEFAULT_HOME}`
  script = `${home}/bin/fm-fleet-snapshot.sh`

  try {
    return (await $.fs.stat(script)).kind === 'file'
  } catch {
    return false
  }
}


export const register: Register = (on, options) => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)

    noColor = ((await $.env.get('NO_COLOR')) ?? '') !== ''
    platform = await $.process
      .run(['uname', '-s'], { timeoutMs: 2_000 })
      .then(run => run.stdout.trim())
      .catch(() => '')
    void refreshStatus($, options, {}, [])

    // A worker (or a headless run) has no use for the fleet views and must not
    // add its own poll to the Firstmate home.
    const isWorker = ((await $.env.get('FM_TASK_ID')) ?? '') !== ''

    if (e.isInteractive && !isWorker && (await findScript($))) {
      await $.command.register({ name: 'fleet', description: 'Toggle the Firstmate fleet pane' })
      void poll($, options)
      $.clock.every(POLL_MS, () => void poll($, options))
    }

    return started
  })

  on('session.measure', async ($, e, next) => {
    void refreshStatus($, options, e.context, e.rateLimits)

    return next(e)
  })

  on('command.run', { command: 'fleet' }, async ($, e) => {
    if ((await $.ui.panes()).some(pane => pane.id === PANE)) {
      await $.ui.close({ id: PANE })

      return { text: 'Fleet pane closed.' }
    }
    if (e.presentation.columns < MIN_OPEN_COLUMNS) {
      return {
        text: `The fleet pane needs a terminal at least ${MIN_OPEN_COLUMNS} columns wide (this one is ${e.presentation.columns}).`,
      }
    }

    const opened = await $.ui.open({ id: PANE, title: 'Fleet' })

    return { text: opened.isPlaced ? 'Fleet pane opened.' : 'The fleet pane could not be placed here.' }
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    // What draws beneath (another mod's band, the engine's) stays, below the fleet row.
    const below = await next(e)
    const fleet = await read($, fleetAtom)
    const segments = fleet === null ? [] : bandSegments(fleet)

    if (e.props.hasSurvey || segments.length === 0) {
      return below
    }

    const { Box, Text } = $.ui.resolve(e)
    const fit = fitSegments(segments, e.props.bodyColumns)

    return (
      <Box flexDirection="column">
        <Text wrap="truncate-end">
          <Text {...tone('dim')}>{BAND_LABEL}</Text>
          {fit.map(segment => (
            <Text>
              <Text {...tone('dim')}>{' · '}</Text>
              <Text {...tone(segment.tone)}>{segment.text}</Text>
            </Text>
          ))}
        </Text>
        {below}
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const fleet: Fleet | null = await read($, fleetAtom)
    const width = e.props.bodyColumns

    if (fleet === null || fleet.rows.length === 0) {
      return (
        <Box>
          <Text {...tone('dim')}>{fleet === null ? 'No fleet data.' : 'No workers.'}</Text>
        </Box>
      )
    }
    if (width < MIN_PANE_COLUMNS) {
      return (
        <Box>
          <Text {...tone('dim')} wrap="truncate-end">Too narrow for the fleet list</Text>
        </Box>
      )
    }

    const columns = columnsFor(width, fleet.rows)
    const summary = fitSegments(bandSegments(fleet), width)
      .map(segment => segment.text)
      .join(' · ')
    const gap = '  '

    return (
      <Box flexDirection="column">
        {summary !== '' && <Text wrap="truncate-end">{summary}</Text>}
        {summary !== '' && <Text>{' '}</Text>}
        <Text {...tone('dim')} wrap="truncate-end">
          {columns.map(column => pad(column.title, column.width)).join(gap).trimEnd()}
        </Text>
        {fleet.rows.map(row => (
          <Text wrap="truncate-end">
            {columns.map((column, index) => {
              const rowTone: Tone =
                column.key === 'state'
                  ? row.needsCaptain
                    ? 'warn'
                    : row.state === 'failed'
                      ? 'bad'
                      : row.state === 'working'
                        ? 'ok'
                        : 'dim'
                  : column.key === 'pr'
                    ? 'accent'
                    : column.key === 'project'
                      ? 'dim'
                      : 'plain'

              return (
                <Text {...tone(rowTone)}>
                  {(index > 0 ? gap : '') + pad(cell(row, column.key), column.width)}
                </Text>
              )
            })}
          </Text>
        ))}
      </Box>
    )
  })
}
