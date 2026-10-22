/**
 * The Crew pane's drawing: a header, then the five zones in order (Overview, Agents, Quota & Limits,
 * Activity, Recent Events), each in its own box with its title on its first row, and a key footer.
 * Everything here draws from the report and the view state it is handed; the module's only effects
 * are the press handlers the caller passes in.
 */
import type { Elements, RenderChildren, RenderSurface } from 'claude-code'

import type { CrewMember, CrewReport, LogFilter, PollState, QuotaReading, ViewMode } from '../types'
import {
  QUOTA_NOTE, TOOLS_DIRECT_NOTE, ago, callTokensText, cells, clip, clockText, effortText, pad, previewText, quotaRows, tildeHome, tokens,
  toolTokenNote, toolTokenText, toolTokenTotal, totalTokens,
} from './format'
import { activityChart, activityCounts, fleetModels, memberKey, sortedTools } from './dashboard'
import { AGENT_BORDERS, harnessStyle, paneStyles } from './theme'
import type { Paint } from './theme'
import {
  KPI_DEFINITIONS, NONE, TAG_CELLS, TOKEN_SWATCH, accountsOf, barParts, cardBorder, cardStats, contextExact, contextFigure, contextLine, crewCounts, dispatchName,
  effectiveFilter, filterLabel, filterLogs, fitSegments, harnessName, headingParts, wrapSegments, kpiText, layoutFor, logEntries, logKey, logPreview, logTokens,
  TOKEN_COLUMN_CELLS, overviewTiles, quotaBriefParts, quotaEntries, quotaLine, fiveHourLine, fiveHourSource, quotaNames, quotaSource, runnerParts, sectionParts,
  sourceState, statusMessage, statusOf, tilesPerRow, tokenBar, tokenFormulas, tokenParts, totalsText,
} from './view'
import type { Layout, LogEntry, QuotaLine, Segment, SourceState, Tile } from './view'

type Ui = Elements[RenderSurface]

export type ViewState = {
  report: CrewReport | null
  error: string
  poll: PollState | null
  expanded: string | null
  mode: ViewMode
  logsOpen: boolean
  logFilter: LogFilter
  help: boolean
  quotaInfo: boolean
  openLog: string | null
  /** The running border's frame; null while its timer is stopped, so every border stands still. */
  pulse: number | null
}

export type Frame = {
  width: number
  rows: number
  placement: 'dock' | 'inline'
  isFocused: boolean
  /** Wall-clock time of this drawing: what the freshness is measured against. */
  now: number
  staleMs: number
  /** The person's home folder, written as `~` wherever a full path is shown; empty when unknown. */
  home: string
}

export type Actions = {
  toggle: (m: CrewMember) => () => Promise<void>
  mode: () => Promise<void>
  quotaInfo: () => Promise<void>
  logs: () => Promise<void>
  openLog: (entry: LogEntry) => () => Promise<void>
  filter: () => Promise<void>
  help: () => Promise<void>
}

/** Rows the inline summary takes at most, as before the redesign. */
const MINI_ROWS = 8

/** Log rows the expanded zone lists at most: ten events per crewmate is all the collector keeps. */
const LOG_CAP = 50

/** Blank cells between two parts of the Overview's token bar, and between two items of its legend. */
const TOKEN_BAR_GAP = 1
const TOKEN_LEGEND_GAP = 3

/** Rows the activity chart is tall: two rows give each minute sixteen steps. */
const CHART_ROWS = 2

/** The longest filter label the footer shows; the full one is in the Recent Events meta. */
const FILTER_LABEL_CELLS = 18

const STATUS_HELP = [
  'WORKING  logged activity under 2 min and the status line says working',
  'ACTIVE   logged activity under 2 min',
  'QUIET    last activity 2 to 15 min ago',
  'STALE    no activity for 15 min',
  'DONE · BLOCKED · PAUSED  from the task\'s own status line',
  'UNKNOWN  no activity and no status recorded yet',
  'A running card has a purple border with a heavy ━ run moving around it, a blocked one red; a done card a dim one with a green ✓ DONE.',
  'The run stands still when nothing runs, the pane is closed or behind another tab, or Reduce motion is on (/config, prefersReducedMotion).',
  'Harness names: ✻ claude in amber, ◆ codex in blue, ▪ any other harness in plain text; a model or account takes its harness\'s colour.',
]

const KEY_HELP = [
  'Keys work while the pane has the keyboard (ctrl+x tab, or a click):',
  '1-9            open or close that crewmate\'s details',
  'd              compact or details mode (details adds every figure and note)',
  'i              quota notes: each account\'s source, age, estimates and crew shares',
  'l              more or fewer log entries',
  'f              log filter: All, Tools, Status, Errors, Agent',
  'h              this help',
  'Tab, Shift+Tab move between controls, log rows included',
  'Enter          press the focused control; on a log row, show or hide its full text',
  '↑ ↓ PgUp PgDn  scroll the pane (the engine\'s keys)',
  'Esc            back to the prompt (the engine\'s key; close details with its number)',
]

const METRIC_HELP = [
  'Tiles: LIVE crewmates listed, RUNNING those working or active, DONE those whose status line says done, CACHE READ the cache share below.',
  KPI_DEFINITIONS,
  'Card: Context = the latest request\'s whole input against the model\'s context window, with a bar only when the window is known; in = all input tokens (uncached + cache read + cache write), out = output.',
  'Quota = the vendor\'s weekly percent of one account as last measured, with a bar of it; resets is the time to its reset, ◷ stale a reading over 30 min old. Accounts and providers are never added up.',
  'Activity = the whole crew\'s logged tool calls, messages and status lines per minute, one bar per minute scaled to the busiest (the peak); ▁ is a minute with none.',
  'Details mode adds a bar of what Tokens is made of, in this order and each in its own colour: cache read, cache write, output, uncached input.',
  'Events: time, tag, crewmate, then in and out (the tokens the call\'s result added and its share of output, — where none was measured) and the command last.',
  'Events show paths cut to their last part; the full text (Enter) writes the home folder as ~.',
  'Source: local transcripts and rollouts only; other machines and the web are not seen.',
]

type Node = ReturnType<Ui['Box']>
type Row = (text: string, tone?: string, width?: number, key?: string) => ReturnType<Ui['Text']>
type Wrapped = (text: string, tone?: string, key?: string) => ReturnType<Ui['Text']>
type Line = (segments: readonly Segment[], key: string, width?: number) => Node
/** A row of `width` cells: `left` from its start, `right` against its end. */
type Split = (key: string, width: number, left: RenderChildren, right: RenderChildren) => Node
/** A bar of `width` cells for `percent`, its fill in `tone` and the rest in the border colour. */
type Bar = (key: string, percent: number, width: number, tone: string) => Node

/** Everything a zone draws with: the elements, the painter and the one-line helpers, `W` the zone's own width. */
type Kit = { ui: Ui; c: Paint; style: ReturnType<typeof paneStyles>; W: number; row: Row; wrapped: Wrapped; line: Line; split: Split; bar: Bar }

const kitFor = (ui: Ui, c: Paint, width: number): Kit => {
  const { Box, Text } = ui
  const W = Math.max(1, width)
  const style = paneStyles(c)
  const row: Row = (text, tone = 'text', w = W, key) => <Text key={key} color={c(tone)} wrap="truncate">{clip(text, w)}</Text>
  const wrapped: Wrapped = (text, tone = 'text', key) => <Text key={key} color={c(tone)} wrap="wrap">{text}</Text>
  const line: Line = (segments, key, w = W) => (
    <Box key={key} width={w}>
      {fitSegments(segments, w).map((s, i) => (
        <Text key={`${key}-${i}`} color={c(s.tone)} weight={s.bold ? 'bold' : 'regular'} inverse={s.inverse} wrap="truncate">{s.text}</Text>
      ))}
    </Box>
  )
  const split: Split = (key, w, left, right) => (
    <Box key={key} width={w}>
      {left}
      <Box flexGrow={1} />
      {right}
    </Box>
  )
  const bar: Bar = (key, percent, w, tone) => {
    const part = barParts(percent, w)
    return (
      <Box key={key} width={w}>
        {part.fill ? <Text color={c(tone)} wrap="truncate">{part.fill}</Text> : null}
        {part.track ? <Text {...style.rule} wrap="truncate">{part.track}</Text> : null}
      </Box>
    )
  }
  return { ui, c, style, W, row, wrapped, line, split, bar }
}

/**
 * An agent's bordered box and, while it runs and the border timer ticks, the heavy run moving over its
 * top and bottom edges (runnerParts). The run is drawn from a wrapper, since nothing inside the bordered
 * box can reach its border; any other box is returned as it is.
 */
const withRunner = ({ ui, c }: Kit, key: string, width: number, border: { color: string; dim: boolean }, frame: number | null, box: Node): Node => {
  const { Box, Text } = ui
  const part = frame !== null && border === AGENT_BORDERS.running ? runnerParts(width, frame) : null
  if (!part) return box
  return (
    <Box key={`runner-${key}`} flexDirection="column" width={width}>
      {box}
      <Box key={`runner-top-${key}`} position="absolute" top={0} left={1 + part.top.left}><Text color={c(border.color)} weight="bold">{part.top.text}</Text></Box>
      <Box key={`runner-bottom-${key}`} position="absolute" bottom={0} left={1 + part.bottom.left}><Text color={c(border.color)} weight="bold">{part.bottom.text}</Text></Box>
    </Box>
  )
}

export const drawPane = (ui: Ui, c: Paint, view: ViewState, frame: Frame, act: Actions) => {
  const { Box, Text } = ui
  const W = Math.max(1, frame.width)
  const { report } = view
  const crew = report?.crew ?? []
  // Ages and states are measured against the wall clock, so they keep moving while the source is stale.
  const at = frame.now
  const source = sourceState(report, view.poll, frame.now, frame.staleMs)
  const layout = layoutFor(W, frame.rows, crew.length, frame.placement)
  const pane = kitFor(ui, c, W)
  const { style } = pane
  const kit = kitFor(ui, c, layout.inner)
  const failure = view.poll?.failed ? view.error : ''
  const warning = !view.poll?.failed && view.error !== '' ? view.error : ''
  const viewed = crew.find(m => memberKey(m) === view.expanded)

  if (layout.mode === 'mini') return drawMini(pane, view, frame, source)

  /**
   * A zone: its own box from 40 columns, its title in small capitals on the first row and its meta
   * against the right edge; on a narrower pane a heading rule (`── TITLE · meta ───`) and its rows.
   */
  const zone = (key: string, title: string, meta: string, children: RenderChildren) => {
    if (!layout.framed) {
      const part = headingParts(title, meta, W)
      return (
        <Box key={key} flexDirection="column" width={W}>
          <Box key={`${key}-title`} width={W}>
            <Text {...style.rule} wrap="truncate">{part.lead}</Text>
            <Text {...style.title} wrap="truncate">{part.title}</Text>
            <Text {...style.meta} wrap="truncate">{part.hint}</Text>
            <Text {...style.rule} wrap="truncate">{part.rule}</Text>
          </Box>
          {children}
        </Box>
      )
    }
    const part = sectionParts(title, meta, layout.inner)
    return (
      <Box key={key} flexDirection="column" {...style.frame} paddingX={1} width={W}>
        {kit.split(`${key}-title`, layout.inner,
          <Text {...style.title} wrap="truncate">{part.title}</Text>,
          part.meta ? <Text {...style.meta} wrap="truncate">{part.meta}</Text> : null)}
        {children}
      </Box>
    )
  }

  const clock = clockText(frame.now).slice(0, 5)
  const state = source.state === 'live' || source.state === 'stale' ? `${source.label} · ${source.age} · ${clock}` : `${source.label} · ${source.age}`
  const brand = '▣ CREW'
  const header = cells(brand) + cells(' / monitor') + 2 + cells(state) + 2 <= W
    ? pane.split('header', W,
      <Text key="brand" {...style.title} wrap="truncate">{brand}<Text {...style.meta}>{' / monitor'}</Text></Text>,
      <Text key="state" color={c(source.tone)} wrap="truncate">{source.mark}<Text color={c('text')}>{` ${state}`}</Text></Text>)
    : (
      <Box key="header" flexDirection="column" width={W}>
        <Text {...style.title} wrap="truncate">{clip(brand, W)}</Text>
        {pane.row(`${source.mark} ${state}`, source.tone)}
      </Box>
    )

  const help = view.help
    ? (
      <Box key="help" flexDirection="column" {...style.frame} paddingX={1} width={W}>
        <Text {...style.title}>HELP</Text>
        {KEY_HELP.map((text, i) => pane.wrapped(text, 'text', `help-key-${i}`))}
        <Text {...style.title}>STATUS</Text>
        {STATUS_HELP.map((text, i) => pane.wrapped(text, 'subtle', `help-status-${i}`))}
        <Text {...style.title}>METRICS</Text>
        {METRIC_HELP.map((text, i) => pane.wrapped(text, 'subtle', `help-metric-${i}`))}
      </Box>
    )
    : null

  const crewKeys = crew.length > 1 ? `1-${Math.min(crew.length, 9)} details` : crew.length === 1 ? '1 details' : ''
  const agentMeta = report ? `${crew.length} total${crewKeys ? ` · ${crewKeys}` : ''}` : NONE

  return (
    <Box flexDirection="column" width={W} rowGap={layout.short ? 0 : 1}>
      {header}
      {failure ? pane.wrapped(`× SOURCE ERROR: ${failure}`, 'error', 'failure') : null}
      {warning ? pane.wrapped(`! ${warning}`, 'warning', 'warning') : null}
      {zone('overview', 'OVERVIEW', 'fleet · since each task started', drawOverview(kit, view, at))}
      {zone('agents', 'AGENTS', agentMeta, drawAgents(kit, view, layout, at, act, frame.home))}
      {zone('quota', 'QUOTA & LIMITS', `5h + week · ${view.quotaInfo || view.mode === 'details' ? 'notes shown' : 'per account'}`, drawQuota(kit, view, frame.now))}
      {zone('activity', 'ACTIVITY', activityMeta(view, kit.W, at), drawActivity(kit, view, layout, at))}
      {drawLogs(kit, view, layout, zone, act, frame.home)}
      {help}
      {drawFooter(pane, view, frame, act, viewed)}
    </Box>
  )
}

/**
 * The key footer: a rule, then the engine's keys on the left and the pane's own hotkeys on the right.
 * When both do not fit on one row the hotkeys wrap on their own row, the engine's keys under them.
 */
const drawFooter = ({ ui, style, W, row }: Kit, view: ViewState, frame: Frame, act: Actions, viewed: CrewMember | undefined) => {
  const { Box, Button, Text } = ui
  const filter = clip(filterLabel(effectiveFilter(view.logFilter, viewed ? memberKey(viewed) : null), viewed?.id), FILTER_LABEL_CELLS)
  const keys = [
    { key: 'key-mode', hotkey: 'd', label: view.mode === 'compact' ? 'details' : 'compact', press: act.mode },
    { key: 'key-quota', hotkey: 'i', label: view.quotaInfo ? 'hide notes' : 'notes', press: act.quotaInfo },
    { key: 'key-logs', hotkey: 'l', label: view.logsOpen ? 'fewer' : 'more', press: act.logs },
    { key: 'key-filter', hotkey: 'f', label: `filter ${filter}`, press: act.filter },
    { key: 'key-help', hotkey: 'h', label: view.help ? 'hide help' : 'help', press: act.help },
  ]
  const hint = frame.isFocused ? '↑↓ scroll · Tab, Enter press' : 'ctrl+x tab to use keys'
  const need = keys.reduce((n, k) => n + cells(k.label) + 3, 0) + 2 * (keys.length - 1)
  const buttons = (
    <Box key="keys" columnGap={2} flexWrap={cells(hint) + 2 + need <= W ? 'nowrap' : 'wrap'} width={cells(hint) + 2 + need <= W ? need : W}>
      {keys.map(k => <Button key={k.key} plain hotkey={k.hotkey} label={k.label} onPress={k.press} />)}
    </Box>
  )
  return (
    <Box key="footer" flexDirection="column" width={W}>
      <Text {...style.rule} wrap="truncate">{'─'.repeat(W)}</Text>
      {cells(hint) + 2 + need <= W
        ? (
          <Box key="footer-row" width={W}>
            <Text {...style.meta} wrap="truncate">{hint}</Text>
            <Box flexGrow={1} />
            {buttons}
          </Box>
        )
        : (
          <Box key="footer-rows" flexDirection="column" width={W}>
            {buttons}
            {row(hint, 'subtle')}
          </Box>
        )}
    </Box>
  )
}

/**
 * The inline summary above the prompt: at most eight one-line rows, and no more than the rows the
 * engine shows it, in zone order, one quota row per provider. Short of rows, the providers' quota
 * share one row before any crewmate gives way, so no account is ever scrolled out of sight.
 */
const drawMini = ({ ui, c, style, row }: Kit, view: ViewState, frame: Frame, source: SourceState) => {
  const { Box, Text } = ui
  const { report } = view
  const crew = report?.crew ?? []
  const W = Math.max(1, frame.width)
  const at = frame.now
  const count = crewCounts(crew, at)
  const counts = report ? `${count.live} live · ${count.active} active · ${count.done} done` : `${NONE} live · ${NONE} active · ${NONE} done`
  const cap = frame.rows > 0 ? Math.min(MINI_ROWS, frame.rows) : MINI_ROWS
  const extra = (view.error !== '' ? 1 : 0) + (report && crew.length === 0 ? 1 : 0)
  const brief = report ? quotaBriefParts(report, frame.now).map(q => [harnessName(q.provider), { text: q.text, tone: 'subtle' }]) : []
  const briefRows = report && brief.length === 0 ? [[{ text: 'quota: no readings yet', tone: 'subtle' }]] : brief
  const quota = briefRows.length > 1 && 2 + briefRows.length + extra + Math.min(crew.length, 2) > cap
    ? [briefRows.flatMap((parts, i) => i > 0 ? [{ text: ' · ', tone: 'subtle' }, ...parts] : parts)]
    : briefRows
  const fixed = 2 + quota.length + extra
  const room = Math.max(0, cap - fixed)
  // Up to three crewmates; past what fits, one row says how many more, when there is a row for it.
  const shown = crew.length <= Math.min(3, room) ? crew.length : Math.max(0, Math.min(3, room - 1))
  const more = crew.length > shown && room > shown
  const age = (m: CrewMember) => m.lastAt > 0 ? ago(Math.max(0, at - m.lastAt)) : NONE
  return (
    <Box flexDirection="column" width={W}>
      <Text {...style.title} wrap="truncate">{clip(`CREW · ${counts} · ${source.mark} ${source.label} ${source.age}`, W)}</Text>
      {row(kpiText(fleetTotals(report), true), 'suggestion', W, 'mini-kpi')}
      {crew.slice(0, shown).map(m => {
        const s = statusOf(m, at)
        const parts = fitSegments([
          { text: `${s.mark} ${'  '.repeat(m.depth)}${m.id} · ${s.label} ${age(m)} · `, tone: s.color },
          dispatchName(m),
        ], W)
        return <Text key={`mini-${memberKey(m)}`} wrap="truncate">{parts.map((part, i) => <Text key={String(i)} color={c(part.tone)}>{part.text}</Text>)}</Text>
      })}
      {more ? row(`+${crew.length - shown} more · dock /crew for details`, 'subtle') : null}
      {report && crew.length === 0 ? row('No crewmates are live.', 'subtle') : null}
      {quota.map((parts, i) => <Text key={`mini-quota-${i}`} wrap="truncate">{fitSegments(parts, W).map((part, j) => <Text key={String(j)} color={c(part.tone)}>{part.text}</Text>)}</Text>)}
      {view.error !== '' ? row(view.error, view.poll?.failed ? 'error' : 'warning') : null}
    </Box>
  )
}

/** The fleet totals, or none when no crewmate's usage can be read: then a sum of zeros would be made up. */
const fleetTotals = (report: CrewReport | null) =>
  report && (report.crew.length === 0 || report.crew.some(m => m.readable)) ? report.totals : null

/**
 * The fleet at a glance: four tiles (live, running, done, cache read), each a small box with a big
 * figure over its label, and the fleet's usage under them. Details mode adds a bar of what Tokens is
 * made of, its legend and both sums written out with every term.
 */
const drawOverview = (kit: Kit, view: ViewState, at: number) => {
  const { ui, c, style, W, row, wrapped } = kit
  const { Box, Text } = ui
  const { report } = view
  const totals = fleetTotals(report)
  const details = view.mode === 'details' && totals !== null
  const models = report ? fleetModels(report.crew) : []
  const unreadable = [...new Set((report?.crew ?? []).filter(m => !m.readable).map(m => m.harness))]
  const left = (report?.crew ?? []).filter(m => !m.readable).length
  const parts = totals ? tokenParts(totals) : []
  const bar = details ? tokenBar(parts, W, TOKEN_BAR_GAP) : []
  const tiles = overviewTiles(report ? report.crew : null, totals, at)
  const across = tilesPerRow(W)
  // The cells a row of tiles leaves over go to its first tiles, one each, so the row spans the zone.
  const base = Math.floor((W - (across - 1)) / across)
  const spare = W - (across - 1) - base * across
  const tile = (t: Tile, i: number) => {
    const width = base + (i < spare ? 1 : 0)
    const inner = Math.max(1, width - 4)
    return (
      <Box key={`tile-${t.key}`} flexDirection="column" {...style.frame} paddingX={1} width={width}>
        <Text color={c(t.tone)} weight="bold" wrap="truncate">{clip(t.value, inner)}</Text>
        <Text {...style.meta} wrap="truncate">{clip(cells(t.label) <= inner ? t.label : t.short, inner)}</Text>
      </Box>
    )
  }
  const rows = Array.from({ length: Math.ceil(tiles.length / across) }, (_, r) => tiles.slice(r * across, (r + 1) * across))
  return (
    <Box key="overview-body" flexDirection="column" width={W}>
      {rows.map((group, r) => <Box key={`tiles-${r}`} columnGap={1} width={W}>{group.map(tile)}</Box>)}
      {row(totalsText(totals), totals ? 'text' : 'subtle', W, 'totals')}
      {!report ? row('Reading the crew logs…', 'subtle') : null}
      {left > 0 ? row(`${totals ? 'excludes' : 'no readable usage from'} ${left} crewmate${left === 1 ? '' : 's'}: ${unreadable.join(', ')} logs not readable`, 'subtle') : null}
      {bar.length > 0 ? <Box key="token-bar" width={W}>{bar.map((s, i) => <Text key={`token-bar-${i}`} color={s.text.trim() ? c(s.tone) : undefined} wrap="truncate">{s.text}</Text>)}</Box> : null}
      {details && totalTokens(totals) > 0
        ? (
          <Box key="token-legend" flexWrap="wrap" columnGap={TOKEN_LEGEND_GAP} width={W}>
            {parts.map(p => (
              <Box key={`token-legend-${p.label}`}>
                <Text color={c(p.tone)}>{TOKEN_SWATCH}</Text>
                <Text {...style.meta}>{` ${p.label} `}</Text>
                <Text color={c('text')}>{tokens(p.value)}</Text>
              </Box>
            ))}
          </Box>
        )
        : null}
      {details ? tokenFormulas(totals).map((text, i) => wrapped(text, i === 1 ? 'permission' : 'subtle', `token-formula-${i}`)) : null}
      {details ? models.map(([model, n]) => kit.line([harnessName(model), { text: ` ×${n}`, tone: 'subtle' }], `model-${model}`)) : null}
      {details ? wrapped(KPI_DEFINITIONS, 'subtle', 'kpi-definitions') : null}
    </Box>
  )
}

/**
 * One card or row per crewmate, about that crewmate alone: status, name, model and task, its context
 * as a figure and a bar, its own requests, tools and tokens, and its latest status line. Everything
 * else known about it opens with its number (1-9).
 */
const drawAgents = (kit: Kit, view: ViewState, layout: Layout, at: number, act: Actions, home: string) => {
  const { ui, c, style, W, row, line, split, bar } = kit
  const { Box, Text, Button } = ui
  const { report } = view
  const crew = report?.crew ?? []
  const details = view.mode === 'details'
  if (!report) return row('Waiting for the first read.', 'subtle', W, 'agents-empty')
  if (crew.length === 0) return row('No crewmates are live.', 'subtle', W, 'agents-empty')

  const age = (m: CrewMember) => m.lastAt > 0 ? `${ago(Math.max(0, at - m.lastAt))}` : NONE
  const isOpen = (m: CrewMember) => view.expanded === memberKey(m)
  /** The harness's icon, name, model and effort in its colour, then the task: `✻ claude haiku/low · scout / dotfiles`. */
  const task = (m: CrewMember): Segment[] => [
    dispatchName(m),
    { text: ` · ${m.kind} / ${m.project || 'no project'}${m.depth > 0 ? ` · nested ${m.depth}` : ''}`, tone: 'subtle' },
  ]
  const contextTone = (m: CrewMember) => m.contextWindow && m.context / m.contextWindow >= 0.8 ? 'warning' : 'permission'

  /**
   * The status glyph, then the name as the control: its digit opens the details, and ▾ follows it while
   * they are open. The status word and age sit against the right edge in the state's colour.
   */
  const title = (m: CrewMember, i: number, width: number) => {
    const s = statusOf(m, at)
    const state = `${s.label} · ${age(m)}`
    const hotkey = i < 9 ? String(i + 1) : undefined
    // The mark and its space, one cell before the state word, and the hotkey's `1: `.
    const room = Math.max(1, width - 2 - 1 - cells(state) - (hotkey ? 3 : 0))
    const name = clip(`${'  '.repeat(m.depth)}${m.id}${isOpen(m) ? ' ▾' : ''}`, room)
    return split(`title-${memberKey(m)}`, width,
      [
        <Text key="mark" color={c(s.color)} wrap="truncate">{`${s.mark} `}</Text>,
        <Button key={`card-${memberKey(m)}`} plain hotkey={hotkey} label={name} onPress={act.toggle(m)}><Text {...style.title}>{name}</Text></Button>,
      ],
      <Text key="state" color={c(s.color)} wrap="truncate">{state}</Text>)
  }

  const card = (m: CrewMember, i: number, width: number) => {
    const border = cardBorder(m, at)
    const inner = Math.max(1, width - 4)
    const message = statusMessage(m, at, home)
    const context = contextFigure(m)
    const text = (value: string, tone = 'text', key?: string) => row(value, tone, inner, key)
    // The figure carries the reason when there is no window, so it keeps the row and the label gives way.
    const label = 'Context usage'
    const figure = clip(context.text, inner)
    return withRunner(kit, memberKey(m), width, border, view.pulse, (
      <Box key={`panel-${memberKey(m)}`} flexDirection="column" {...style.frame} borderColor={c(border.color)} borderDimColor={border.dim} width={width} paddingX={1}>
        {title(m, i, inner)}
        {line(task(m), `task-${memberKey(m)}`, inner)}
        {split(`context-${memberKey(m)}`, inner,
          cells(label) + 2 + cells(figure) <= inner ? <Text {...style.meta} wrap="truncate">{label}</Text> : null,
          <Text color={c(context.percent === null ? 'subtle' : 'text')} weight={context.percent === null ? 'regular' : 'bold'} wrap="truncate">{figure}</Text>)}
        {context.percent !== null ? bar(`context-bar-${memberKey(m)}`, context.percent, inner, contextTone(m)) : null}
        {text(cardStats(m), 'subtle', `stats-${memberKey(m)}`)}
        {text(message.text, message.tone)}
        {details ? text(effortText(m.effort), 'subtle') : null}
        {details && m.lastTool && m.status ? text(`last ▸ ${previewText(m.lastTool, home)}`, 'subtle') : null}
      </Box>
    ))
  }

  const compactRow = (m: CrewMember, i: number) => {
    const message = statusMessage(m, at, home)
    return (
      <Box key={`row-${memberKey(m)}`} flexDirection="column" width={W}>
        {title(m, i, W)}
        {line([{ text: '  ', tone: 'subtle' }, ...task(m), { text: ` · ${contextLine(m, 6, 'ctx')}`, tone: 'subtle' }], `task-${memberKey(m)}`)}
        {!layout.short || details || message.tone === 'error' ? row(`  ${message.text}`, message.tone) : null}
      </Box>
    )
  }

  const pairs = Array.from({ length: Math.ceil(crew.length / layout.columns) }, (_, r) => crew.slice(r * layout.columns, (r + 1) * layout.columns))
  // Two cards side by side leave a cell over on an even width: the left card takes it, so the pair spans the zone.
  const spare = Math.max(0, W - 1 - 2 * layout.cardWidth)
  const viewed = crew.find(isOpen)
  return (
    <Box key="agents-body" flexDirection="column" width={W}>
      {layout.mode === 'cards'
        ? pairs.map((pair, r) => (
          <Box key={`cards-${r}`} columnGap={1} width={W}>
            {pair.map((m, j) => card(m, r * layout.columns + j, layout.cardWidth + (j === 0 && layout.columns === 2 ? spare : 0)))}
          </Box>
        ))
        : crew.map((m, i) => compactRow(m, i))}
      {viewed ? drawDetails(kit, view, viewed, at, home) : null}
    </Box>
  )
}

/**
 * Everything known about one crewmate, for the one whose details are open; the home folder reads as `~`.
 * Each section opens with a ruled heading in the zones' style, a blank row before it, and every line is
 * wrapped here to the box's inner width, so no text can run past its border.
 */
const drawDetails = (kit: Kit, view: ViewState, m: CrewMember, at: number, home: string) => {
  const { ui, c, style, W } = kit
  const { Box, Text } = ui
  const inner = Math.max(1, W - 4)
  const border = cardBorder(m, at)
  const readings = view.report?.quota.readings ?? {}
  const note = toolTokenNote(m)
  const spent = Object.values(m.toolTokens).reduce((n, tt) => n + toolTokenTotal(tt), 0)
  const quota = quotaRows(m.quota, readings, at)
  const own = (text: string) => tildeHome(text, home)
  const cut = (text: string) => text.endsWith('…') ? `${text} (source truncated)` : text
  const block = (segments: readonly Segment[], key: string) => (
    <Box key={key} flexDirection="column" width={inner}>
      {wrapSegments(segments, inner).map((parts, i) => (
        <Text key={String(i)} wrap="truncate">
          {parts.map((s, j) => <Text key={String(j)} color={c(s.tone)} weight={s.bold ? 'bold' : 'regular'}>{s.text}</Text>)}
        </Text>
      ))}
    </Box>
  )
  const text = (body: string, tone: string, key: string) => block([{ text: body, tone }], key)
  const section = (name: string, rows: RenderChildren[]) => {
    const part = headingParts(name, '', inner)
    return (
      <Box key={`d-${name}`} flexDirection="column" width={inner}>
        <Text key="gap"> </Text>
        <Box key="heading" width={inner}>
          <Text {...style.rule} wrap="truncate">{part.lead}</Text>
          <Text {...style.title} wrap="truncate">{part.title}</Text>
          <Text {...style.rule} wrap="truncate">{part.rule}</Text>
        </Box>
        {rows}
      </Box>
    )
  }
  const harness = harnessName(m.harness)
  return withRunner(kit, `details-${memberKey(m)}`, W, border, view.pulse, (
    <Box key={`details-${memberKey(m)}`} flexDirection="column" {...style.frame} borderColor={c(border.color)} borderDimColor={border.dim} width={W} paddingX={1}>
      {block([{ text: `${m.id} · details`, tone: 'text', bold: true }], 'd-title')}
      {section('STATUS', [
        m.description && m.description !== m.id ? text(own(m.description), 'text', 'd-description') : null,
        text(`status ${m.status ? own(m.status) : `${NONE} no status line yet`}`, 'permission', 'd-status'),
      ])}
      {section('MODEL', [
        block([{ text: 'dispatched ', tone: 'text' }, dispatchName(m), { text: ` · ${effortText(m.effort)}`, tone: 'text' }], 'd-dispatch'),
        Object.entries(m.models).length === 0 ? text('no model requests yet', 'subtle', 'd-no-models') : null,
        ...Object.entries(m.models).map(([model, n]) => block([{ text: model, tone: harness.tone }, { text: ` ×${n}`, tone: 'subtle' }], `d-model-${model}`)),
      ])}
      {section('CONTEXT & TOKENS', [
        text(`context ${contextExact(m)}`, 'text', 'd-context'),
        m.readable
          ? text(`${m.requests} requests · uncached in ${tokens(m.input)} · out ${tokens(m.output)} · thinking ${m.reasoning > 0 ? `${tokens(m.reasoning)} (in out)` : 'not reported'}`, 'text', 'd-tokens')
          : text(`usage is not readable for the ${m.harness} harness`, 'subtle', 'd-tokens'),
        m.readable ? text(`cache ${tokenFormulas(m)[1]?.replace(/^Cache /, '') ?? NONE}`, 'permission', 'd-cache') : null,
        m.readable && m.sessions === 0 ? text('no transcript found for its worktree yet', 'subtle', 'd-sessions') : null,
      ])}
      {section('TOOLS', [
        text(m.readable ? `tools ${m.toolCalls} · ${tokens(spent)} tok` : `tools ${NONE}: ${m.harness} logs not readable`, 'text', 'd-tools'),
        ...sortedTools(m.tools).map(([tool, n]) => text(`${tool} ×${n} · ${toolTokenText(m.toolTokens[tool])}`, 'text', `d-tool-${tool}`)),
        note ? text(note, 'subtle', 'd-tool-note') : null,
      ])}
      {m.recentTools.length > 0
        ? section('RECENT CALLS', [
          text('recent calls, newest first (full text: Tab to the event row, then Enter)', 'subtle', 'd-calls'),
          ...[...m.recentTools].reverse().map((event, i) => <Text key={`d-call-${i}`} {...style.meta} wrap="truncate">{clip(`${clockText(event.at)} ${event.tool ? `${callTokensText(event)} · ` : ''}${previewText(event.text, home)}`, inner)}</Text>),
        ])
        : null}
      {section('LAST ACTION', [
        text(m.lastTool ? `▸ ${cut(own(m.lastTool))}` : `${NONE} no tool call yet`, 'text', 'd-last-tool'),
        m.lastText ? text(`“${cut(own(m.lastText))}”`, 'subtle', 'd-last-text') : null,
      ])}
      {section('SOURCE & LIMITS', [
        quota.length === 0 ? text(`${NONE} no quota figure: ${accountsOf(m, readings)}`, 'subtle', 'd-no-quota') : null,
        ...quota.map((r, i) => r.provider
          ? block([harnessName(r.provider), { text: r.text.slice(r.provider.length), tone: r.tone }], `d-quota-${i}`)
          : text(r.text, r.tone, `d-quota-${i}`)),
        quota.length > 0 ? text(QUOTA_NOTE, 'subtle', 'd-quota-note') : null,
        quota.length > 0 ? text(TOOLS_DIRECT_NOTE, 'subtle', 'd-tools-note') : null,
      ])}
      {section('WORKSPACE', [
        block([
          { text: `branch ${m.branch || 'unknown'}\nworktree ${m.worktree ? own(m.worktree) : 'unknown'}\nhome ${own(m.home)}\nharness `, tone: 'subtle' },
          harness,
          { text: ` · ${m.readable ? `${m.sessions} transcript${m.sessions === 1 ? '' : 's'}` : 'transcripts not readable'}`, tone: 'subtle' },
        ], 'd-where'),
      ])}
    </Box>
  ))
}

/** The cells of a window row's label (`  5h   `, `  week `), and the fewest cells a bar is drawn in beside its figure. */
const WINDOW_LABEL_CELLS = 7
const MIN_INLINE_BAR = 8

/**
 * One block per account: its name, then a 5h row and a week row. Each row has its label, a bar of the
 * vendor's percent in the provider's accent and, in a column shared by every row, the percent, a stale
 * mark once the reading is over half an hour old and the time to its reset. A window with no percent
 * shows `—` and why, and draws no bar. Too narrow for a bar beside the figure, the bar takes the next
 * row. The notes (source and age, estimates, crew shares, caveats) show under each account with `i`,
 * and in details mode.
 */
const drawQuota = ({ ui, c, style, W, row, wrapped, line, bar }: Kit, view: ViewState, now: number) => {
  const { Box, Text } = ui
  const { report } = view
  if (!report) return row(`${NONE} waiting for the first read`, 'subtle', W, 'quota-empty')
  const entries = quotaEntries(report)
  if (entries.length === 0) return row('No quota readings yet.', 'subtle', W, 'quota-empty')
  const names = quotaNames(entries)
  const info = view.quotaInfo || view.mode === 'details'
  const fleet = report.quota.fleet
  // The stale mark comes before the reset time, so a narrow row cuts the reset first.
  const right = (q: QuotaLine) => `${q.figure}${[q.note, q.reset].filter(Boolean).map(text => ` · ${text}`).join('')}`
  const windows = (r: QuotaReading) => [{ id: '5h', label: '5h', q: fiveHourLine(r, now) }, { id: 'week', label: 'week', q: quotaLine(r, now) }]
  const column = Math.min(W - WINDOW_LABEL_CELLS, Math.max(...entries.flatMap(([, r]) => windows(r).map(w => cells(right(w.q))))))
  const inline = W - WINDOW_LABEL_CELLS - 2 - column >= MIN_INLINE_BAR
  const windowRow = (key: string, r: QuotaReading, w: ReturnType<typeof windows>[number]) => {
    const { q } = w
    const id = w.id === 'week' ? key : `5h-${key}`
    const figureCells = inline ? column : W - WINDOW_LABEL_CELLS
    const figure = (
      <Text key="figure" wrap="truncate">
        <Text color={c(q.tone)} weight={q.percent !== null ? 'bold' : 'regular'}>{q.figure}</Text>
        <Text color={c(q.percent === null ? 'subtle' : q.note ? 'warning' : 'subtle')}>{pad(right(q).slice(q.figure.length), Math.max(0, figureCells - cells(q.figure)))}</Text>
      </Text>
    )
    const label = <Text key="label" {...style.meta} wrap="truncate">{pad(`  ${w.label}`, Math.min(W, WINDOW_LABEL_CELLS))}</Text>
    const barCells = W - WINDOW_LABEL_CELLS - 2 - column
    return (
      <Box key={`quota-${w.id}-${key}`} flexDirection="column" width={W}>
        <Box key="window-line" width={W}>
          {label}
          {inline ? q.percent !== null ? bar(`quota-bar-${id}`, q.percent, barCells, harnessStyle(r.provider).role) : <Text key="no-bar">{' '.repeat(barCells)}</Text> : null}
          {inline ? <Text key="gap">{'  '}</Text> : null}
          {figure}
        </Box>
        {!inline && q.percent !== null ? bar(`quota-bar-${id}`, q.percent, W, harnessStyle(r.provider).role) : null}
      </Box>
    )
  }
  return (
    <Box key="quota-body" flexDirection="column" width={W}>
      {entries.map(([key, r]) => {
        const shares = info && fleet[key] ? quotaRows({ [key]: fleet[key] }, report.quota.readings, now, true).slice(1).filter(s => !/^(week|source) /.test(s.text)) : []
        return (
          <Box key={`quota-${key}`} flexDirection="column" width={W}>
            {line([harnessName(r.provider), { text: (names.get(key) ?? key).slice(r.provider.length), tone: 'text' }], `quota-line-${key}`)}
            {windows(r).map(w => windowRow(key, r, w))}
            {info ? row(`  ${fiveHourSource(r, now).text}`, fiveHourSource(r, now).tone, W, `quota-source-5h-${key}`) : null}
            {info ? row(`  ${quotaSource(r, now).text}`, quotaSource(r, now).tone, W, `quota-source-${key}`) : null}
            {info && !fleet[key] ? row('  no crew usage in this window', 'subtle', W, `quota-idle-${key}`) : null}
            {shares.map((s, i) => row(`  ${s.text}`, s.tone, W, `quota-${key}-${i}`))}
          </Box>
        )
      })}
      {info ? wrapped(QUOTA_NOTE, 'subtle', 'quota-note') : null}
      {info ? wrapped(TOOLS_DIRECT_NOTE, 'subtle', 'tools-note') : null}
    </Box>
  )
}

/** Minutes the activity chart covers: one cell per minute, an hour at most, never wider than the zone. */
const chartMinutes = (width: number): number => Math.max(1, Math.min(60, width))

/** Cells per minute: a bar and a gap once the zone holds an hour that way, so a wide chart spans the zone. */
const chartStep = (width: number): 1 | 2 => width >= 2 * 60 - 1 ? 2 : 1

/** The crew's readable per-minute buckets, the only source of the chart; an unreadable harness has none. */
const readableActivity = (view: ViewState) => (view.report?.crew ?? []).filter(m => m.readable).map(m => m.activity)

/** The Activity zone's meta: the window and the busiest minute in it, which the bars are scaled to. */
const activityMeta = (view: ViewState, width: number, at: number): string => {
  const minutes = chartMinutes(width)
  const peak = Math.max(0, ...activityCounts(readableActivity(view), at, minutes))
  return `LAST ${minutes} MIN${peak > 0 ? ` · peak ${peak}/min` : ''}`
}

/**
 * The whole crew's logged activity per minute as a bar chart drawn with block characters, oldest on the
 * left and the current minute on the right, `60m ago` and `now` under it. Only real per-minute buckets
 * are drawn: no readable log, no live crew or no event in the window each say so in words instead.
 */
const drawActivity = ({ ui, c, style, W, row }: Kit, view: ViewState, layout: Layout, at: number) => {
  const { Box, Text } = ui
  const crew = view.report?.crew ?? []
  const minutes = chartMinutes(W)
  if (!view.report) return row('No activity data yet.', 'subtle', W, 'activity-empty')
  if (crew.length === 0) return row('No activity data: no crewmates are live.', 'subtle', W, 'activity-empty')
  const readable = crew.filter(m => m.readable)
  if (readable.length === 0) return row('Activity history unavailable: no crewmate\'s logs are readable.', 'subtle', W, 'activity-empty')
  const counts = activityCounts(readable.map(m => m.activity), at, minutes)
  const unknown = crew.length - readable.length
  const besides = unknown > 0 ? ` · ${unknown} not readable` : ''
  const busy = readable.filter(m => m.activity.some(b => b.count > 0 && b.minute > Math.floor(at / 60000) - minutes && b.minute <= Math.floor(at / 60000)))
  if (busy.length === 0) return row(`No logged activity in the last ${minutes} min${besides}.`, 'subtle', W, 'activity-empty')
  if (layout.activityCollapsed) {
    const newest = Math.max(...busy.map(m => m.lastAt))
    return row(`${busy.length} of ${readable.length} readable crewmates logged activity in ${minutes} min · newest ${ago(Math.max(0, at - newest))} ago${besides}`, 'subtle', W, 'activity-summary')
  }
  const chart = activityChart(counts, CHART_ROWS)
  const step = chartStep(W)
  // Runs of busy or quiet minutes, so a row is a few Texts rather than one per minute.
  const runs = (r: number) => chart.reduce<{ busy: boolean; text: string }[]>((out, col, i) => {
    const last = out.at(-1)
    const glyph = (i > 0 && step === 2 ? ' ' : '') + (col.glyphs[r] ?? ' ')
    return last && last.busy === col.busy ? [...out.slice(0, -1), { ...last, text: last.text + glyph }] : [...out, { busy: col.busy, text: glyph }]
  }, [])
  const span = minutes * step - (step - 1)
  const start = `${minutes}m ago`
  return (
    <Box key="activity-body" flexDirection="column" width={W}>
      {Array.from({ length: CHART_ROWS }, (_, r) => (
        <Box key={`chart-${r}`} width={W}>
          {runs(r).map((run, i) => <Text key={`chart-${r}-${i}`} color={c(run.busy ? 'permission' : 'border')} wrap="truncate">{run.text}</Text>)}
        </Box>
      ))}
      {span >= cells(start) + 5
        ? <Box key="chart-axis" width={span}><Text {...style.meta} wrap="truncate">{start}</Text><Box flexGrow={1} /><Text {...style.meta} wrap="truncate">now</Text></Box>
        : row('now ┘', 'subtle', W, 'chart-axis')}
      {unknown > 0 ? row(`excludes ${unknown} crewmate${unknown === 1 ? '' : 's'} whose logs are not readable`, 'subtle', W, 'activity-unknown') : null}
    </Box>
  )
}

type Zone = (key: string, title: string, meta: string, children: RenderChildren) => Node

/** Cells a log row keeps for its command before the token columns give way. */
const MIN_COMMAND_CELLS = 16

/**
 * The newest events, one short row each: time, the tag as a badge, the crewmate (when more than one is
 * live), the call's input and output tokens in two right-aligned columns under an `in`/`out` header
 * (`—` where nothing measured them), then last the command or path in bold and the rest dim, taking
 * what the row has left. A pane too narrow to keep the command readable drops the token columns and
 * says so. Each row is a Button: Enter on it shows the full text under it, the home folder written as
 * `~`; `l` lists more rows.
 */
const drawLogs = ({ ui, c, style, W, row, wrapped }: Kit, view: ViewState, layout: Layout, zone: Zone, act: Actions, home: string) => {
  const { Box, Text, Button } = ui
  const { report } = view
  const crew = report?.crew ?? []
  const viewed = crew.find(m => memberKey(m) === view.expanded)
  const all = logEntries(crew)
  const filter = effectiveFilter(view.logFilter, viewed ? memberKey(viewed) : null)
  const kept = filterLogs(all, filter, viewed ? memberKey(viewed) : null)
  const limit = view.logsOpen ? LOG_CAP : layout.logRows
  const shown = kept.slice(0, limit)
  const label = filterLabel(filter, viewed?.id)
  const events = `${kept.length} event${kept.length === 1 ? '' : 's'}`
  // Folded to one line, the zone lists no rows, so its meta counts the events alone.
  const meta = limit === 0 ? `${label} · ${events}` : `${label} · ${shown.length} of ${events}`
  const many = crew.length > 1
  const whoWidth = Math.max(8, Math.min(20, Math.floor(W / 6)))
  // Time and tag take 10 cells each, the crewmate its width and two after; the two token columns a cell between them and two after.
  const lead = 10 + TAG_CELLS + 4 + (many ? whoWidth + 2 : 0)
  const columns = 2 * TOKEN_COLUMN_CELLS + 3
  const withTokens = W - lead - columns >= MIN_COMMAND_CELLS
  const right = (text: string) => ' '.repeat(Math.max(0, TOKEN_COLUMN_CELLS - cells(text))) + text
  const entry = (e: LogEntry) => {
    const p = logPreview(e, home)
    const isError = e.level === 'error'
    const badge = ` ${p.tag} `
    const t = logTokens(e)
    const parts = fitSegments([
      { text: `${clockText(e.at)}  `, tone: 'subtle' },
      { text: badge, tone: p.tone, inverse: true },
      { text: ' '.repeat(Math.max(0, TAG_CELLS + 2 - cells(badge)) + 2), tone: 'subtle' },
      ...(many ? [{ text: `${pad(e.who, whoWidth)}  `, tone: e.color }] : []),
      ...(withTokens ? [
        { text: right(t.input), tone: t.input === NONE ? 'subtle' : 'text' },
        { text: ' ', tone: 'subtle' },
        { text: right(t.output), tone: t.output === NONE ? 'subtle' : 'text' },
        { text: '  ', tone: 'subtle' },
      ] : []),
      { text: p.head, tone: isError ? 'error' : 'text', bold: true },
      ...(p.rest ? [{ text: ` ${p.rest}`, tone: isError ? 'error' : 'subtle' }] : []),
    ], W)
    return (
      <Box key={`entry-${logKey(e)}`} flexDirection="column" width={W}>
        <Button key={logKey(e)} plain label={parts.map(s => s.text).join('')} onPress={act.openLog(e)}>
          {parts.map((s, i) => <Text key={`${logKey(e)}-${i}`} color={c(s.tone)} weight={s.bold ? 'bold' : 'regular'} inverse={s.inverse}>{s.text}</Text>)}
        </Button>
        {view.openLog === e.id
          ? <Box key={`full-${logKey(e)}`} paddingLeft={2} width={W}>{wrapped(`${e.who} · ${tildeHome(e.text, home)}${e.sourceTruncated ? ' (source truncated)' : ''}`, isError ? 'error' : 'text')}</Box>
          : null}
      </Box>
    )
  }
  const empty = !report ? 'No events yet.'
    : all.length === 0 ? 'No events yet.'
      : kept.length === 0 ? `No matching events (filter: ${label}).` : ''
  return zone('logs', 'RECENT EVENTS', meta, (
    <Box key="logs-body" flexDirection="column" width={W}>
      {empty ? row(empty, 'subtle') : null}
      {!empty && limit === 0 ? row(`${kept.length} events · newest ${clockText(kept[0]?.at ?? 0)} · l to expand`, 'subtle') : null}
      {shown.length > 0
        ? withTokens
          ? <Box key="logs-columns" width={W}><Text {...style.meta} wrap="truncate">{`${' '.repeat(lead)}${right('in')} ${right('out')}  tokens`}</Text></Box>
          : <Box key="logs-columns" width={W}>{row('in/out tokens hidden: the pane is too narrow', 'subtle')}</Box>
        : null}
      {shown.map(entry)}
    </Box>
  ))
}

