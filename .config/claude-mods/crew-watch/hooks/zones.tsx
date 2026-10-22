/**
 * The Crew pane's drawing: a header, then the five zones in order (Overview, Agents, Quota & Limits,
 * Activity, Recent Events), each in its own box with its title on its first row, and a key footer.
 * Everything here draws from the report and the view state it is handed; the module's only effects
 * are the press handlers the caller passes in.
 */
import type { Elements, RenderChildren, RenderSurface } from 'claude-code'

import type { CrewMember, CrewReport, LogFilter, PollState, ViewMode } from '../types'
import {
  QUOTA_NOTE, TOOLS_DIRECT_NOTE, ago, callTokensText, cells, clip, clockText, dispatchText, effortText, pad, previewText, quotaRows, tildeHome, tokens,
  toolTokenNote, toolTokenText, toolTokenTotal, totalTokens,
} from './format'
import { activityChart, activityCounts, fleetModels, harnessColor, memberKey, sortedTools } from './dashboard'
import type { Paint } from './theme'
import {
  KPI_DEFINITIONS, NONE, TAG_CELLS, accountsOf, barParts, cardBorder, cardStats, contextExact, contextFigure, contextLine, crewCounts, effectiveFilter,
  filterLabel, filterLogs, fitSegments, headingParts, kpiText, layoutFor, logEntries, logKey, logPreview, overviewTiles, quotaBrief, quotaEntries, quotaLine,
  quotaNames, quotaSource, sectionParts, sourceState, statusMessage, statusOf, tilesPerRow, tokenBar, tokenFormulas, tokenParts, totalsText,
} from './view'
import type { Layout, LogEntry, Segment, SourceState, Tile } from './view'

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

/** The Overview's token bar (details mode) is never wider than this, so a wide pane does not draw a wall of blocks. */
const TOKEN_BAR_CELLS = 60

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
  'A running card has a purple border, a blocked one red; a done card a dim one with a green ✓ DONE.',
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
  'Details mode adds a bar of what Tokens is made of: █ cache read, ▓ cache write, ▒ output, ░ uncached input.',
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
type Kit = { ui: Ui; c: Paint; W: number; row: Row; wrapped: Wrapped; line: Line; split: Split; bar: Bar }

const kitFor = (ui: Ui, c: Paint, width: number): Kit => {
  const { Box, Text } = ui
  const W = Math.max(1, width)
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
        {part.track ? <Text color={c('border')} wrap="truncate">{part.track}</Text> : null}
      </Box>
    )
  }
  return { ui, c, W, row, wrapped, line, split, bar }
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
            <Text color={c('border')} wrap="truncate">{part.lead}</Text>
            <Text weight="bold" color={c('subtle')} wrap="truncate">{part.title}</Text>
            <Text color={c('subtle')} wrap="truncate">{part.hint}</Text>
            <Text color={c('border')} wrap="truncate">{part.rule}</Text>
          </Box>
          {children}
        </Box>
      )
    }
    const part = sectionParts(title, meta, layout.inner)
    return (
      <Box key={key} flexDirection="column" borderStyle="round" borderColor={c('border')} paddingX={1} width={W}>
        {kit.split(`${key}-title`, layout.inner,
          <Text weight="bold" color={c('subtle')} wrap="truncate">{part.title}</Text>,
          part.meta ? <Text color={c('subtle')} wrap="truncate">{part.meta}</Text> : null)}
        {children}
      </Box>
    )
  }

  const clock = clockText(frame.now).slice(0, 5)
  const state = source.state === 'live' || source.state === 'stale' ? `${source.label} · ${source.age} · ${clock}` : `${source.label} · ${source.age}`
  const brand = '▣ CREW'
  const header = cells(brand) + cells(' / monitor') + 2 + cells(state) + 2 <= W
    ? pane.split('header', W,
      <Text key="brand" weight="bold" wrap="truncate">{brand}<Text color={c('subtle')} weight="regular">{' / monitor'}</Text></Text>,
      <Text key="state" color={c(source.tone)} wrap="truncate">{source.mark}<Text color={c('text')}>{` ${state}`}</Text></Text>)
    : (
      <Box key="header" flexDirection="column" width={W}>
        <Text weight="bold" wrap="truncate">{clip(brand, W)}</Text>
        {pane.row(`${source.mark} ${state}`, source.tone)}
      </Box>
    )

  const help = view.help
    ? (
      <Box key="help" flexDirection="column" borderStyle="round" borderColor={c('border')} paddingX={1} width={W}>
        <Text weight="bold">HELP</Text>
        {KEY_HELP.map((text, i) => pane.wrapped(text, 'text', `help-key-${i}`))}
        <Text weight="bold">STATUS</Text>
        {STATUS_HELP.map((text, i) => pane.wrapped(text, 'subtle', `help-status-${i}`))}
        <Text weight="bold">METRICS</Text>
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
      {zone('quota', 'QUOTA & LIMITS', `weekly · ${view.quotaInfo || view.mode === 'details' ? 'notes shown' : 'per account'}`, drawQuota(kit, view, frame.now))}
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
const drawFooter = ({ ui, c, W, row }: Kit, view: ViewState, frame: Frame, act: Actions, viewed: CrewMember | undefined) => {
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
      <Text color={c('border')} wrap="truncate">{'─'.repeat(W)}</Text>
      {cells(hint) + 2 + need <= W
        ? (
          <Box key="footer-row" width={W}>
            <Text color={c('subtle')} wrap="truncate">{hint}</Text>
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
const drawMini = ({ ui, row }: Kit, view: ViewState, frame: Frame, source: SourceState) => {
  const { Box, Text } = ui
  const { report } = view
  const crew = report?.crew ?? []
  const W = Math.max(1, frame.width)
  const at = frame.now
  const count = crewCounts(crew, at)
  const counts = report ? `${count.live} live · ${count.active} active · ${count.done} done` : `${NONE} live · ${NONE} active · ${NONE} done`
  const cap = frame.rows > 0 ? Math.min(MINI_ROWS, frame.rows) : MINI_ROWS
  const extra = (view.error !== '' ? 1 : 0) + (report && crew.length === 0 ? 1 : 0)
  const brief = report ? quotaBrief(report, frame.now) : []
  const quota = brief.length > 1 && 2 + brief.length + extra + Math.min(crew.length, 2) > cap ? [brief.join(' · ')] : brief
  const fixed = 2 + quota.length + extra
  const room = Math.max(0, cap - fixed)
  // Up to three crewmates; past what fits, one row says how many more, when there is a row for it.
  const shown = crew.length <= Math.min(3, room) ? crew.length : Math.max(0, Math.min(3, room - 1))
  const more = crew.length > shown && room > shown
  const age = (m: CrewMember) => m.lastAt > 0 ? ago(Math.max(0, at - m.lastAt)) : NONE
  return (
    <Box flexDirection="column" width={W}>
      <Text weight="bold" wrap="truncate">{clip(`CREW · ${counts} · ${source.mark} ${source.label} ${source.age}`, W)}</Text>
      {row(kpiText(fleetTotals(report), true), 'suggestion', W, 'mini-kpi')}
      {crew.slice(0, shown).map(m => {
        const s = statusOf(m, at)
        return row(`${s.mark} ${'  '.repeat(m.depth)}${m.id} · ${s.label} ${age(m)} · ${dispatchText(m)}`, harnessColor(m.harness), W, `mini-${memberKey(m)}`)
      })}
      {more ? row(`+${crew.length - shown} more · dock /crew for details`, 'subtle') : null}
      {report && crew.length === 0 ? row('No crewmates are live.', 'subtle') : null}
      {quota.map((text, i) => row(text, 'subtle', W, `mini-quota-${i}`))}
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
const drawOverview = ({ ui, c, W, row, wrapped, line }: Kit, view: ViewState, at: number) => {
  const { Box, Text } = ui
  const { report } = view
  const totals = fleetTotals(report)
  const details = view.mode === 'details' && totals !== null
  const models = report ? fleetModels(report.crew) : []
  const unreadable = [...new Set((report?.crew ?? []).filter(m => !m.readable).map(m => m.harness))]
  const left = (report?.crew ?? []).filter(m => !m.readable).length
  const parts = totals ? tokenParts(totals) : []
  const bar = details ? tokenBar(parts, Math.min(W, TOKEN_BAR_CELLS)) : []
  const legend = parts.flatMap((p, i): Segment[] => [...(i > 0 ? [{ text: ' · ', tone: 'subtle' }] : []), { text: `${p.glyph} ${p.label} ${tokens(p.value)}`, tone: p.tone }])
  const tiles = overviewTiles(report ? report.crew : null, totals, at)
  const across = tilesPerRow(W)
  // The cells a row of tiles leaves over go to its first tiles, one each, so the row spans the zone.
  const base = Math.floor((W - (across - 1)) / across)
  const spare = W - (across - 1) - base * across
  const tile = (t: Tile, i: number) => {
    const width = base + (i < spare ? 1 : 0)
    const inner = Math.max(1, width - 4)
    return (
      <Box key={`tile-${t.key}`} flexDirection="column" borderStyle="round" borderColor={c('border')} paddingX={1} width={width}>
        <Text color={c(t.tone)} weight="bold" wrap="truncate">{clip(t.value, inner)}</Text>
        <Text color={c('subtle')} wrap="truncate">{clip(cells(t.label) <= inner ? t.label : t.short, inner)}</Text>
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
      {bar.length > 0 ? <Box key="token-bar" width={W}>{bar.map((s, i) => <Text key={`token-bar-${i}`} color={c(s.tone)} wrap="truncate">{s.text}</Text>)}</Box> : null}
      {details && totalTokens(totals) > 0 ? line(legend, 'token-legend') : null}
      {details ? tokenFormulas(totals).map((text, i) => wrapped(text, i === 1 ? 'permission' : 'subtle', `token-formula-${i}`)) : null}
      {details ? models.map(([model, n]) => row(`${model} ×${n}`, 'suggestion', W, `model-${model}`)) : null}
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
  const { ui, c, W, row, line, split, bar } = kit
  const { Box, Text, Button } = ui
  const { report } = view
  const crew = report?.crew ?? []
  const details = view.mode === 'details'
  if (!report) return row('Waiting for the first read.', 'subtle', W, 'agents-empty')
  if (crew.length === 0) return row('No crewmates are live.', 'subtle', W, 'agents-empty')

  const age = (m: CrewMember) => m.lastAt > 0 ? `${ago(Math.max(0, at - m.lastAt))}` : NONE
  const isOpen = (m: CrewMember) => view.expanded === memberKey(m)
  /** The provider in its accent, then the model, effort and task: `claude haiku/low · scout / dotfiles`. */
  const task = (m: CrewMember): Segment[] => [
    { text: m.harness, tone: harnessColor(m.harness) },
    { text: `${dispatchText(m).slice(m.harness.length)} · ${m.kind} / ${m.project || 'no project'}${m.depth > 0 ? ` · nested ${m.depth}` : ''}`, tone: 'subtle' },
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
        <Button key={`card-${memberKey(m)}`} plain hotkey={hotkey} label={name} onPress={act.toggle(m)}><Text weight="bold">{name}</Text></Button>,
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
    return (
      <Box key={`panel-${memberKey(m)}`} flexDirection="column" borderStyle="round" borderColor={c(border.color)} borderDimColor={border.dim} width={width} paddingX={1}>
        {title(m, i, inner)}
        {line(task(m), `task-${memberKey(m)}`, inner)}
        {split(`context-${memberKey(m)}`, inner,
          cells(label) + 2 + cells(figure) <= inner ? <Text color={c('subtle')} wrap="truncate">{label}</Text> : null,
          <Text color={c(context.percent === null ? 'subtle' : 'text')} weight={context.percent === null ? 'regular' : 'bold'} wrap="truncate">{figure}</Text>)}
        {context.percent !== null ? bar(`context-bar-${memberKey(m)}`, context.percent, inner, contextTone(m)) : null}
        {text(cardStats(m), 'subtle', `stats-${memberKey(m)}`)}
        {text(message.text, message.tone)}
        {details ? text(effortText(m.effort), harnessColor(m.harness)) : null}
        {details && m.lastTool && m.status ? text(`last ▸ ${previewText(m.lastTool, home)}`, 'subtle') : null}
      </Box>
    )
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

/** Everything known about one crewmate, for the one whose details are open; the home folder reads as `~`. */
const drawDetails = ({ ui, c, W, wrapped }: Kit, view: ViewState, m: CrewMember, at: number, home: string) => {
  const { Box, Text } = ui
  const color = harnessColor(m.harness)
  const readings = view.report?.quota.readings ?? {}
  const note = toolTokenNote(m)
  const spent = Object.values(m.toolTokens).reduce((n, tt) => n + toolTokenTotal(tt), 0)
  const quota = quotaRows(m.quota, readings, at)
  const own = (text: string) => tildeHome(text, home)
  const cut = (text: string) => text.endsWith('…') ? `${text} (source truncated)` : text
  const section = (name: string) => <Text key={`d-${name}`} weight="bold" color={c(color)}>{name}</Text>
  return (
    <Box key={`details-${memberKey(m)}`} flexDirection="column" borderStyle="round" borderColor={c(color)} width={W} paddingX={1}>
      <Text weight="bold" wrap="wrap">{`${m.id} · details`}</Text>
      {m.description && m.description !== m.id ? wrapped(own(m.description), 'text', 'd-description') : null}
      {wrapped(`status ${m.status ? own(m.status) : `${NONE} no status line yet`}`, 'permission', 'd-status')}
      {section('MODEL')}
      {wrapped(`dispatched ${dispatchText(m)} · ${effortText(m.effort)}`, color, 'd-dispatch')}
      {Object.entries(m.models).length === 0 ? wrapped('no model requests yet', 'subtle', 'd-no-models') : null}
      {Object.entries(m.models).map(([model, n]) => wrapped(`${model} ×${n}`, color, `d-model-${model}`))}
      {section('CONTEXT & TOKENS')}
      {wrapped(`context ${contextExact(m)}`, 'text', 'd-context')}
      {m.readable
        ? wrapped(`${m.requests} requests · uncached in ${tokens(m.input)} · out ${tokens(m.output)} · thinking ${m.reasoning > 0 ? `${tokens(m.reasoning)} (in out)` : 'not reported'}`, 'text', 'd-tokens')
        : wrapped(`usage is not readable for the ${m.harness} harness`, 'subtle', 'd-tokens')}
      {m.readable ? wrapped(`cache ${tokenFormulas(m)[1]?.replace(/^Cache /, '') ?? NONE}`, 'permission', 'd-cache') : null}
      {m.readable && m.sessions === 0 ? wrapped('no transcript found for its worktree yet', 'subtle', 'd-sessions') : null}
      {section('TOOLS')}
      {wrapped(m.readable ? `tools ${m.toolCalls} · ${tokens(spent)} tok` : `tools ${NONE}: ${m.harness} logs not readable`, 'text', 'd-tools')}
      {sortedTools(m.tools).map(([tool, n]) => wrapped(`${tool} ×${n} · ${toolTokenText(m.toolTokens[tool])}`, 'text', `d-tool-${tool}`))}
      {note ? wrapped(note, 'subtle', 'd-tool-note') : null}
      {m.recentTools.length > 0 ? wrapped('recent calls, newest first (full text: Tab to the event row, then Enter)', 'subtle', 'd-calls') : null}
      {[...m.recentTools].reverse().map((event, i) => <Text key={`d-call-${i}`} color={c('subtle')} wrap="truncate">{clip(`${clockText(event.at)} ${event.tool ? `${callTokensText(event)} · ` : ''}${previewText(event.text, home)}`, Math.max(1, W - 4))}</Text>)}
      {section('LAST ACTION')}
      {wrapped(m.lastTool ? `▸ ${cut(own(m.lastTool))}` : `${NONE} no tool call yet`, 'text', 'd-last-tool')}
      {m.lastText ? wrapped(`“${cut(own(m.lastText))}”`, 'subtle', 'd-last-text') : null}
      {section('SOURCE & LIMITS')}
      {quota.length === 0 ? wrapped(`${NONE} no quota figure: ${accountsOf(m, readings)}`, 'subtle', 'd-no-quota') : null}
      {quota.map((r, i) => wrapped(r.text, r.tone, `d-quota-${i}`))}
      {quota.length > 0 ? wrapped(QUOTA_NOTE, 'subtle', 'd-quota-note') : null}
      {quota.length > 0 ? wrapped(TOOLS_DIRECT_NOTE, 'subtle', 'd-tools-note') : null}
      {wrapped(`branch ${m.branch || 'unknown'}\nworktree ${m.worktree ? own(m.worktree) : 'unknown'}\nhome ${own(m.home)}\nharness ${m.harness} · ${m.readable ? `${m.sessions} transcripts` : 'transcripts not readable'}`, 'subtle', 'd-where')}
    </Box>
  )
}

/**
 * One block per account: its name, and against the right edge the vendor's weekly percent, a stale
 * mark once the reading is over half an hour old and the time to its reset; under it a bar of the
 * percent in the provider's accent, drawn only when there is a percent. The notes (source and age,
 * estimates, crew shares, caveats) show under each account with `i`, and in details mode.
 */
const drawQuota = ({ ui, c, W, row, wrapped, split, bar }: Kit, view: ViewState, now: number) => {
  const { Box, Text } = ui
  const { report } = view
  if (!report) return row(`${NONE} waiting for the first read`, 'subtle', W, 'quota-empty')
  const entries = quotaEntries(report)
  if (entries.length === 0) return row('No quota readings yet.', 'subtle', W, 'quota-empty')
  const names = quotaNames(entries)
  const info = view.quotaInfo || view.mode === 'details'
  const fleet = report.quota.fleet
  return (
    <Box key="quota-body" flexDirection="column" width={W}>
      {entries.map(([key, r]) => {
        const q = quotaLine(r, now)
        const source = quotaSource(r, now)
        const name = names.get(key) ?? key
        // The stale mark comes before the reset time, so a narrow row cuts the reset first.
        const tail = [q.note, q.reset].filter(Boolean).map(text => ` · ${text}`).join('')
        const right = `${q.figure}${tail}`
        const together = cells(name) + 2 + cells(right) <= W
        const figure = (
          <Text key="figure" wrap="truncate">
            <Text color={c(q.tone)} weight={q.percent !== null ? 'bold' : 'regular'}>{q.figure}</Text>
            <Text color={c(q.percent === null ? 'subtle' : q.note ? 'warning' : 'subtle')}>{clip(tail, Math.max(0, (together ? W - cells(name) - 2 : W - 2) - cells(q.figure)))}</Text>
          </Text>
        )
        const shares = info && fleet[key] ? quotaRows({ [key]: fleet[key] }, report.quota.readings, now, true).slice(1).filter(s => !/^(week|source) /.test(s.text)) : []
        return (
          <Box key={`quota-${key}`} flexDirection="column" width={W}>
            {together
              ? split(`quota-line-${key}`, W, <Text key="name" wrap="truncate">{name}</Text>, figure)
              : (
                <Box key={`quota-line-${key}`} flexDirection="column" width={W}>
                  {row(name)}
                  <Box key="figure-row" width={W}><Text key="indent">{'  '}</Text>{figure}</Box>
                </Box>
              )}
            {q.percent !== null ? bar(`quota-bar-${key}`, q.percent, W, harnessColor(r.provider)) : null}
            {info ? row(`  ${source.text}`, source.tone, W, `quota-source-${key}`) : null}
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
const drawActivity = ({ ui, c, W, row }: Kit, view: ViewState, layout: Layout, at: number) => {
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
        ? <Box key="chart-axis" width={span}><Text color={c('subtle')} wrap="truncate">{start}</Text><Box flexGrow={1} /><Text color={c('subtle')} wrap="truncate">now</Text></Box>
        : row('now ┘', 'subtle', W, 'chart-axis')}
      {unknown > 0 ? row(`excludes ${unknown} crewmate${unknown === 1 ? '' : 's'} whose logs are not readable`, 'subtle', W, 'activity-unknown') : null}
    </Box>
  )
}

type Zone = (key: string, title: string, meta: string, children: RenderChildren) => Node

/**
 * The newest events, one short row each: time, the tag as a badge, the crewmate (when more than one is
 * live), the command or path in bold and the rest dim. Each row is a Button: Enter on it shows the
 * full text under it, the home folder written as `~`; `l` lists more rows.
 */
const drawLogs = ({ ui, c, W, row, wrapped }: Kit, view: ViewState, layout: Layout, zone: Zone, act: Actions, home: string) => {
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
  const entry = (e: LogEntry) => {
    const p = logPreview(e, home)
    const isError = e.level === 'error'
    const badge = ` ${p.tag} `
    const parts = fitSegments([
      { text: `${clockText(e.at)}  `, tone: 'subtle' },
      { text: badge, tone: p.tone, inverse: true },
      { text: ' '.repeat(Math.max(0, TAG_CELLS + 2 - cells(badge)) + 2), tone: 'subtle' },
      ...(many ? [{ text: `${pad(e.who, whoWidth)}  `, tone: e.color }] : []),
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
      {shown.map(entry)}
    </Box>
  ))
}

