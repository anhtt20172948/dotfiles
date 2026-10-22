/**
 * The Crew pane's drawing: a header, then the five zones in order (Overview, Agents, Quota & Limits,
 * Activity, Recent Logs). Everything here draws from the report and the view state it is handed; the
 * module's only effects are the press handlers the caller passes in.
 */
import type { Elements, RenderSurface } from 'claude-code'

import type { CrewMember, CrewReport, LogFilter, PollState, ViewMode } from '../types'
import { QUOTA_NOTE, TOOLS_DIRECT_NOTE, accountText, ago, callTokensText, cells, clip, clockText, dispatchText, effortText, gauge, pad, quotaRows, tokens, toolTokenNote, toolTokenText, toolTokenTotal } from './format'
import { activityLane, fleetModels, harnessColor, laneGeometry, memberKey, sortedTools } from './dashboard'
import type { Paint } from './theme'
import {
  KPI_DEFINITIONS, NONE, accountsOf, cacheShare, contextExact, contextLine, effectiveFilter, filterLabel, filterLogs, headingParts, isActive, kpiText,
  layoutFor, logEntries, logTag, quotaBrief, quotaEntries, quotaFigure, sourceState, statusOf, usageLine,
} from './view'
import type { Layout, LogEntry, SourceState } from './view'

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
}

export type Frame = {
  width: number
  rows: number
  placement: 'dock' | 'inline'
  isFocused: boolean
  /** Wall-clock time of this drawing: what the freshness is measured against. */
  now: number
  staleMs: number
}

export type Actions = {
  toggle: (m: CrewMember) => () => Promise<void>
  mode: () => Promise<void>
  logs: () => Promise<void>
  filter: () => Promise<void>
  help: () => Promise<void>
}

/** Rows the inline summary takes at most, as before the redesign. */
const MINI_ROWS = 8

/** Log rows the expanded zone lists at most: ten events per crewmate is all the collector keeps. */
const LOG_CAP = 50

const STATUS_HELP = [
  'WORKING  logged activity under 2 min and the status line says working',
  'ACTIVE   logged activity under 2 min',
  'QUIET    last activity 2 to 15 min ago',
  'STALE    no activity for 15 min',
  'DONE · BLOCKED · PAUSED  from the task\'s own status line',
  'UNKNOWN  no activity and no status recorded yet',
]

const KEY_HELP = [
  'Keys work while the pane has the keyboard (ctrl+x tab, or a click):',
  '1-9            open or close that crewmate\'s details',
  'Tab, Shift+Tab move between controls; Enter presses the focused one',
  'd              compact or details mode',
  'l              more or fewer log entries',
  'f              log filter: All, Tools, Status, Errors, Agent',
  'h              this help',
  '↑ ↓ PgUp PgDn  scroll the pane (the engine\'s keys)',
  'Esc            back to the prompt (the engine\'s key; close details with its number)',
]

const METRIC_HELP = [
  KPI_DEFINITIONS,
  'Ctx = the latest request\'s whole input against the model\'s context window; shown only when the window is known.',
  'Quota = the vendor\'s weekly percent of one account, as measured at its time; accounts and providers are never added up.',
  'Activity = one cell per minute; ▰ marks a minute with at least one logged tool call, message or status line.',
  'Source: local transcripts and rollouts only; other machines and the web are not seen.',
]

export const drawPane = (ui: Ui, c: Paint, view: ViewState, frame: Frame, act: Actions) => {
  const { Box, Text, Button } = ui
  const W = Math.max(1, frame.width)
  const { report } = view
  const crew = report?.crew ?? []
  // Ages and states are measured against the wall clock, so they keep moving while the source is stale.
  const at = frame.now
  const source = sourceState(report, view.poll, frame.now, frame.staleMs)
  const layout = layoutFor(W, frame.rows, crew.length, frame.placement)
  const active = crew.filter(m => isActive(m, at)).length
  const row = (text: string, tone = 'text', width = W, key?: string) => <Text key={key} color={c(tone)} wrap="truncate">{clip(text, width)}</Text>
  const wrapped = (text: string, tone = 'text', key?: string) => <Text key={key} color={c(tone)} wrap="wrap">{text}</Text>
  const counts = report ? `${crew.length} live · ${active} active` : `${NONE} live · ${NONE} active`
  const failure = view.poll?.failed ? view.error : ''
  const warning = !view.poll?.failed && view.error !== '' ? view.error : ''
  const viewed = crew.find(m => memberKey(m) === view.expanded)

  if (layout.mode === 'mini') return drawMini(ui, c, view, frame, source, counts, row)

  const heading = (title: string, hint: string, key: string) => {
    const part = headingParts(title, hint, W)
    return (
      <Box key={key} width={W}>
        <Text color={c('border')} wrap="truncate">{part.lead}</Text>
        <Text weight="bold" wrap="truncate">{part.title}</Text>
        <Text color={c('subtle')} wrap="truncate">{part.hint}</Text>
        <Text color={c('border')} wrap="truncate">{part.rule}</Text>
      </Box>
    )
  }

  const title = `CREW MONITOR · ${counts}`
  const state = `${source.mark} ${source.label} · ${source.age}`
  const header = cells(title) + 2 + cells(state) <= W
    ? (
      <Box key="header" width={W} justifyContent="space-between">
        <Text weight="bold" wrap="truncate">{title}</Text>
        <Text color={c(source.tone)} wrap="truncate">{state}</Text>
      </Box>
    )
    : (
      <Box key="header" flexDirection="column" width={W}>
        <Text weight="bold" wrap="truncate">{clip(title, W)}</Text>
        {row(state, source.tone)}
      </Box>
    )

  const keys = (
    <Box key="keys" width={W} columnGap={2} flexWrap="wrap">
      <Button key="key-mode" plain hotkey="d" label={view.mode === 'compact' ? 'details' : 'compact'} onPress={act.mode} />
      <Button key="key-logs" plain hotkey="l" label={view.logsOpen ? 'fewer logs' : 'more logs'} onPress={act.logs} />
      <Button key="key-filter" plain hotkey="f" label={`filter ${filterLabel(effectiveFilter(view.logFilter, viewed ? memberKey(viewed) : null), viewed?.id)}`} onPress={act.filter} />
      <Button key="key-help" plain hotkey="h" label={view.help ? 'hide help' : 'help'} onPress={act.help} />
      {!frame.isFocused ? <Text key="key-focus" color={c('subtle')} wrap="truncate">ctrl+x tab to use keys</Text> : null}
    </Box>
  )

  const help = view.help
    ? (
      <Box key="help" flexDirection="column" borderStyle="round" borderColor={c('border')} paddingX={1} width={W}>
        <Text weight="bold">HELP</Text>
        {KEY_HELP.map((line, i) => wrapped(line, 'text', `help-key-${i}`))}
        <Text weight="bold">STATUS</Text>
        {STATUS_HELP.map((line, i) => wrapped(line, 'subtle', `help-status-${i}`))}
        <Text weight="bold">METRICS</Text>
        {METRIC_HELP.map((line, i) => wrapped(line, 'subtle', `help-metric-${i}`))}
      </Box>
    )
    : null

  return (
    <Box flexDirection="column" width={W}>
      {header}
      {keys}
      {failure ? wrapped(`× SOURCE ERROR: ${failure}`, 'error', 'failure') : null}
      {warning ? wrapped(`! ${warning}`, 'warning', 'warning') : null}
      {help}
      {heading('OVERVIEW', 'fleet · since each task started', 'h-overview')}
      {drawOverview(ui, view, layout, W, row, wrapped)}
      {heading('AGENTS', crew.length > 0 ? `${crew.length} live · ${crew.length > 1 ? `keys 1-${Math.min(crew.length, 9)} open` : 'key 1 opens'} details` : '', 'h-agents')}
      {drawAgents(ui, c, view, layout, W, at, act, row, wrapped)}
      {heading('QUOTA & LIMITS', 'per account · weekly window', 'h-quota')}
      {drawQuota(ui, c, view, W, frame.now, row, wrapped)}
      {heading('ACTIVITY', `last ${laneGeometry(W).cells} min · 1 cell/min`, 'h-activity')}
      {drawActivity(ui, c, view, layout, W, at, row)}
      {drawLogs(ui, c, view, layout, W, heading, row, wrapped)}
    </Box>
  )
}

type Row = (text: string, tone?: string, width?: number, key?: string) => ReturnType<Ui['Text']>
type Wrapped = (text: string, tone?: string, key?: string) => ReturnType<Ui['Text']>

/** The inline summary above the prompt: at most eight one-line rows, in zone order, one quota row per provider. */
const drawMini = (ui: Ui, c: Paint, view: ViewState, frame: Frame, source: SourceState, counts: string, row: Row) => {
  const { Box, Text } = ui
  const { report } = view
  const crew = report?.crew ?? []
  const W = Math.max(1, frame.width)
  const at = frame.now
  const quota = report ? quotaBrief(report, frame.now) : []
  const fixed = 2 + quota.length + (view.error !== '' ? 1 : 0) + (report && crew.length === 0 ? 1 : 0)
  const room = Math.max(0, MINI_ROWS - fixed)
  // Up to three crewmates; past what fits, one row says how many more.
  const shown = crew.length <= Math.min(3, room) ? crew.length : Math.max(0, Math.min(3, room - 1))
  const age = (m: CrewMember) => m.lastAt > 0 ? ago(Math.max(0, at - m.lastAt)) : NONE
  return (
    <Box flexDirection="column" width={W}>
      <Text weight="bold" wrap="truncate">{clip(`CREW · ${counts} · ${source.mark} ${source.label} ${source.age}`, W)}</Text>
      {row(kpiText(fleetTotals(report), true), 'suggestion', W, 'mini-kpi')}
      {crew.slice(0, shown).map(m => {
        const s = statusOf(m, at)
        return row(`${s.mark} ${'  '.repeat(m.depth)}${m.id} · ${s.label} ${age(m)} · ${dispatchText(m)}`, harnessColor(m.harness), W, `mini-${memberKey(m)}`)
      })}
      {crew.length > shown ? row(`+${crew.length - shown} more · dock /crew for details`, 'subtle') : null}
      {report && crew.length === 0 ? row('No crewmates are live.', 'subtle') : null}
      {quota.map((line, i) => row(line, 'subtle', W, `mini-quota-${i}`))}
      {view.error !== '' ? row(view.error, view.poll?.failed ? 'error' : 'warning') : null}
    </Box>
  )
}

/** The fleet totals, or none when no crewmate's usage can be read: then a sum of zeros would be made up. */
const fleetTotals = (report: CrewReport | null) =>
  report && (report.crew.length === 0 || report.crew.some(m => m.readable)) ? report.totals : null

const drawOverview = (ui: Ui, view: ViewState, layout: Layout, W: number, row: Row, wrapped: Wrapped) => {
  const { Box } = ui
  const { report } = view
  const totals = fleetTotals(report)
  const details = view.mode === 'details' && totals !== null
  const models = report ? fleetModels(report.crew) : []
  const unreadable = [...new Set((report?.crew ?? []).filter(m => !m.readable).map(m => m.harness))]
  const left = (report?.crew ?? []).filter(m => !m.readable).length
  const hasCache = totals !== null && cacheShare(totals) !== NONE
  return (
    <Box key="overview" flexDirection="column" width={W}>
      {row(kpiText(totals, layout.condensed), totals ? 'text' : 'subtle')}
      {!report ? row('Reading the crew logs…', 'subtle') : null}
      {left > 0 ? row(`${totals ? 'excludes' : 'no readable usage from'} ${left} crewmate${left === 1 ? '' : 's'}: ${unreadable.join(', ')} logs not readable`, 'subtle') : null}
      {details ? row(`in ${tokens(totals.input)} · out ${tokens(totals.output)} · thinking ${tokens(totals.reasoning)}`, 'subtle') : null}
      {details ? row(`cache ${hasCache ? `${gauge(Number.parseFloat(cacheShare(totals)), 8)} ` : ''}${cacheShare(totals)} · read ${tokens(totals.cacheRead)} · write ${tokens(totals.cacheWrite)}`, 'permission') : null}
      {details ? models.map(([model, count]) => row(`${model} ×${count}`, 'suggestion', W, `model-${model}`)) : null}
      {details ? wrapped(KPI_DEFINITIONS, 'subtle', 'kpi-definitions') : null}
    </Box>
  )
}

const drawAgents = (ui: Ui, c: Paint, view: ViewState, layout: Layout, W: number, at: number, act: Actions, row: Row, wrapped: Wrapped) => {
  const { Box, Text, Button } = ui
  const { report } = view
  const crew = report?.crew ?? []
  const readings = report?.quota.readings ?? {}
  const details = view.mode === 'details'
  if (!report) return row('Waiting for the first read.', 'subtle', W, 'agents-empty')
  if (crew.length === 0) return row('No crewmates are live.', 'subtle', W, 'agents-empty')

  const age = (m: CrewMember) => m.lastAt > 0 ? `${ago(Math.max(0, at - m.lastAt))}` : NONE
  const isOpen = (m: CrewMember) => view.expanded === memberKey(m)

  /** The name is the control: its digit opens the details; ▸ closed, ▾ open, so the state reads without colour. */
  const title = (m: CrewMember, i: number, width: number) => {
    const s = statusOf(m, at)
    const state = ` ${s.mark} ${s.label} · ${age(m)}`
    const hotkey = i < 9 ? String(i + 1) : undefined
    const room = Math.max(1, width - cells(state) - (hotkey ? 3 : 0))
    const label = `${isOpen(m) ? '▾' : '▸'} ${'  '.repeat(m.depth)}${m.id}`
    return (
      <Box key={`title-${memberKey(m)}`} width={width}>
        <Button key={`card-${memberKey(m)}`} plain hotkey={hotkey} label={clip(label, room)} onPress={act.toggle(m)} />
        <Box flexGrow={1} />
        <Text color={c(s.color)} wrap="truncate">{state}</Text>
      </Box>
    )
  }

  const blocker = (m: CrewMember, width: number) =>
    statusOf(m, at).label === 'BLOCKED' ? row(`× ${m.status}`, 'error', width, `blocker-${memberKey(m)}`) : null

  const card = (m: CrewMember, i: number, width: number) => {
    const color = harnessColor(m.harness)
    const inner = Math.max(1, width - 4)
    const bar = Math.max(6, Math.min(14, inner - 30))
    const line = (text: string, tone = 'text', key?: string) => row(text, tone, inner, key)
    return (
      <Box key={`panel-${memberKey(m)}`} flexDirection="column" borderStyle="round" borderColor={c(color)} width={width} paddingX={1}>
        {title(m, i, inner)}
        {line(`${dispatchText(m)} · ${m.kind} / ${m.project || 'no project'}${m.depth > 0 ? ` · nested ${m.depth}` : ''}`, color)}
        {line(contextLine(m, bar), m.contextWindow && m.context / m.contextWindow >= 0.8 ? 'warning' : 'suggestion')}
        {line(usageLine(m))}
        {line(accountsOf(m, readings), 'subtle')}
        {blocker(m, inner)}
        {details && m.readable ? line(`thinking ${tokens(m.reasoning)} · cache ${cacheShare(m)} · read ${tokens(m.cacheRead)} · write ${tokens(m.cacheWrite)}`, 'subtle') : null}
        {details ? line(effortText(m.effort), color) : null}
        {details && m.lastTool ? line(`last ▸ ${m.lastTool}`, 'subtle') : null}
        {details && m.status && statusOf(m, at).label !== 'BLOCKED' ? line(`status ${m.status}`, 'permission') : null}
      </Box>
    )
  }

  const compactRow = (m: CrewMember, i: number) => {
    const bar = 6
    const summary = `${dispatchText(m)} · ${accountsOf(m, readings)} · ${contextLine(m, bar, 'ctx')} · ${usageLine(m, true)}`
    return (
      <Box key={`row-${memberKey(m)}`} flexDirection="column" width={W}>
        {title(m, i, W)}
        {row(`  ${summary}`, harnessColor(m.harness))}
        {blocker(m, W)}
        {details && m.lastTool ? row(`  last ▸ ${m.lastTool}`, 'subtle') : null}
      </Box>
    )
  }

  const pairs = Array.from({ length: Math.ceil(crew.length / layout.columns) }, (_, r) => crew.slice(r * layout.columns, (r + 1) * layout.columns))
  const viewed = crew.find(isOpen)
  const legend = [...new Set(crew.map(m => m.harness))]
  return (
    <Box key="agents" flexDirection="column" width={W}>
      <Box key="legend" columnGap={2} width={W}>{legend.map(harness => <Text key={`legend-${harness}`} color={c(harnessColor(harness))} wrap="truncate">{`■ ${harness}`}</Text>)}</Box>
      {layout.mode === 'cards'
        ? pairs.map((pair, r) => (
          <Box key={`cards-${r}`} columnGap={1} width={W}>{pair.map((m, j) => card(m, r * layout.columns + j, layout.cardWidth))}</Box>
        ))
        : crew.map((m, i) => compactRow(m, i))}
      {viewed ? drawDetails(ui, c, view, viewed, W, at, wrapped) : null}
    </Box>
  )
}

/** Everything known about one crewmate, for the one whose details are open. */
const drawDetails = (ui: Ui, c: Paint, view: ViewState, m: CrewMember, W: number, at: number, wrapped: Wrapped) => {
  const { Box, Text } = ui
  const color = harnessColor(m.harness)
  const readings = view.report?.quota.readings ?? {}
  const note = toolTokenNote(m)
  const spent = Object.values(m.toolTokens).reduce((n, tt) => n + toolTokenTotal(tt), 0)
  const quota = quotaRows(m.quota, readings, at)
  const cut = (text: string) => text.endsWith('…') ? `${text} (source truncated)` : text
  const section = (name: string) => <Text key={`d-${name}`} weight="bold" color={c(color)}>{name}</Text>
  return (
    <Box key={`details-${memberKey(m)}`} flexDirection="column" borderStyle="round" borderColor={c(color)} width={W} paddingX={1}>
      <Text weight="bold" wrap="wrap">{`${m.id} · details`}</Text>
      {m.description && m.description !== m.id ? wrapped(m.description, 'text', 'd-description') : null}
      {wrapped(`status ${m.status || `${NONE} no status line yet`}`, 'permission', 'd-status')}
      {section('MODEL')}
      {wrapped(`dispatched ${dispatchText(m)} · ${effortText(m.effort)}`, color, 'd-dispatch')}
      {Object.entries(m.models).length === 0 ? wrapped('no model requests yet', 'subtle', 'd-no-models') : null}
      {Object.entries(m.models).map(([model, count]) => wrapped(`${model} ×${count}`, color, `d-model-${model}`))}
      {section('CONTEXT & TOKENS')}
      {wrapped(`context ${contextExact(m)}`, 'text', 'd-context')}
      {m.readable
        ? wrapped(`in ${tokens(m.input)} · out ${tokens(m.output)} · thinking ${tokens(m.reasoning)} · ${m.requests} requests`, 'text', 'd-tokens')
        : wrapped(`usage is not readable for the ${m.harness} harness`, 'subtle', 'd-tokens')}
      {m.readable ? wrapped(`cache ${cacheShare(m)} of input read from cache · read ${tokens(m.cacheRead)} · write ${tokens(m.cacheWrite)}`, 'permission', 'd-cache') : null}
      {m.readable && m.sessions === 0 ? wrapped('no transcript found for its worktree yet', 'subtle', 'd-sessions') : null}
      {section('TOOLS')}
      {wrapped(m.readable ? `tools ${m.toolCalls} · ${tokens(spent)} tok` : `tools ${NONE}: ${m.harness} logs not readable`, 'text', 'd-tools')}
      {sortedTools(m.tools).map(([tool, count]) => wrapped(`${tool} ×${count} · ${toolTokenText(m.toolTokens[tool])}`, 'text', `d-tool-${tool}`))}
      {note ? wrapped(note, 'subtle', 'd-tool-note') : null}
      {m.recentTools.length > 0 ? <Text key="d-calls" color={c('subtle')}>recent calls, newest first (full text: l, then f to Agent)</Text> : null}
      {[...m.recentTools].reverse().map((event, i) => <Text key={`d-call-${i}`} color={c('subtle')} wrap="truncate">{clip(`${clockText(event.at)} ${event.tool ? `${callTokensText(event)} · ` : ''}${event.text}`, Math.max(1, W - 4))}</Text>)}
      {section('LAST ACTION')}
      {wrapped(m.lastTool ? `▸ ${cut(m.lastTool)}` : `${NONE} no tool call yet`, 'text', 'd-last-tool')}
      {m.lastText ? wrapped(`“${cut(m.lastText)}”`, 'subtle', 'd-last-text') : null}
      {section('SOURCE & LIMITS')}
      {quota.length === 0 ? wrapped(`${NONE} no quota figure: ${accountsOf(m, readings)}`, 'subtle', 'd-no-quota') : null}
      {quota.map((r, i) => wrapped(r.text, r.tone, `d-quota-${i}`))}
      {quota.length > 0 ? wrapped(QUOTA_NOTE, 'subtle', 'd-quota-note') : null}
      {quota.length > 0 ? wrapped(TOOLS_DIRECT_NOTE, 'subtle', 'd-tools-note') : null}
      {wrapped(`branch ${m.branch || 'unknown'}\nworktree ${m.worktree || 'unknown'}\nhome ${m.home}\nharness ${m.harness} · ${m.readable ? `${m.sessions} transcripts` : 'transcripts not readable'}`, 'subtle', 'd-where')}
    </Box>
  )
}

const drawQuota = (ui: Ui, c: Paint, view: ViewState, W: number, now: number, row: Row, wrapped: Wrapped) => {
  const { Box } = ui
  const { report } = view
  if (!report) return row(`${NONE} waiting for the first read`, 'subtle', W, 'quota-empty')
  const entries = quotaEntries(report)
  if (entries.length === 0) return row('No quota readings yet.', 'subtle', W, 'quota-empty')
  const headWidth = 34
  const bar = W >= 100 ? 10 : 6
  const details = view.mode === 'details'
  const fleet = report.quota.fleet
  return (
    <Box key="quota" flexDirection="column" width={W}>
      {entries.map(([key, r]) => {
        const head = accountText(r)
        const figure = quotaFigure(r, now, bar)
        const inline = headWidth + cells(figure.text) <= W
        const shares = details && fleet[key] ? quotaRows({ [key]: fleet[key] }, report.quota.readings, now, true).slice(1).filter(r => !r.text.startsWith('week ')) : []
        return (
          <Box key={`quota-${key}`} flexDirection="column" width={W}>
            {inline
              ? row(`${pad(head, headWidth)}${figure.text}`, figure.tone)
              : <Box flexDirection="column" width={W}>{row(head, 'subtle')}{row(`  ${figure.text}`, figure.tone)}</Box>}
            {details && !fleet[key] ? row('  no crew usage in this window', 'subtle') : null}
            {shares.map((s, i) => row(`  ${s.text}`, s.tone, W, `quota-${key}-${i}`))}
          </Box>
        )
      })}
      {details ? wrapped(QUOTA_NOTE, 'subtle', 'quota-note') : null}
      {details ? wrapped(TOOLS_DIRECT_NOTE, 'subtle', 'tools-note') : null}
    </Box>
  )
}

const drawActivity = (ui: Ui, c: Paint, view: ViewState, layout: Layout, W: number, at: number, row: Row) => {
  const { Box, Text } = ui
  const crew = view.report?.crew ?? []
  const geometry = laneGeometry(W)
  const lastMinute = Math.floor(at / 60000)
  const inWindow = (m: CrewMember) => m.activity.filter(b => b.count > 0 && b.minute > lastMinute - geometry.cells && b.minute <= lastMinute)
  if (!view.report) return row('No activity data yet.', 'subtle', W, 'activity-empty')
  if (crew.length === 0) return row('No activity data: no crewmates are live.', 'subtle', W, 'activity-empty')
  const readable = crew.filter(m => m.readable)
  const busy = readable.filter(m => inWindow(m).length > 0)
  if (readable.length === 0) return row('Activity history unavailable: no crewmate\'s logs are readable.', 'subtle', W, 'activity-empty')
  const unknown = crew.length - readable.length
  const besides = unknown > 0 ? ` · ${unknown} not readable` : ''
  if (busy.length === 0) return row(`No logged activity in the last ${geometry.cells} min${besides}.`, 'subtle', W, 'activity-empty')
  if (layout.activityCollapsed) {
    const newest = Math.max(...busy.map(m => m.lastAt))
    return row(`${busy.length} of ${readable.length} readable crewmates logged activity in ${geometry.cells} min · newest ${ago(Math.max(0, at - newest))} ago${besides}`, 'subtle', W, 'activity-summary')
  }
  return (
    <Box key="activity" flexDirection="column" width={W}>
      <Box width={W}><Box key="lane-axis-gutter" width={geometry.offset} flexShrink={0} /><Text key="lane-axis" color={c('subtle')}>{geometry.axis}</Text></Box>
      {crew.map(m => {
        const s = statusOf(m, at)
        return (
          <Box key={`lane-${memberKey(m)}`} width={W}>
            <Box width={geometry.markWidth} flexShrink={0}><Text color={c(s.color)}>{s.mark + ' '}</Text></Box>
            <Box width={geometry.nameWidth} flexShrink={0}>{row(`${'  '.repeat(m.depth)}${m.id}`, harnessColor(m.harness), geometry.nameWidth)}</Box>
            <Box key={`lane-gap-${memberKey(m)}`} width={geometry.gap} flexShrink={0} />
            {m.readable
              ? <Text color={c(harnessColor(m.harness))} wrap="truncate">{activityLane(m.activity, at, geometry.cells)}</Text>
              : <Text color={c('subtle')} wrap="truncate">{clip(`history unavailable: ${m.harness} logs not readable`, geometry.cells)}</Text>}
            <Text dimColor wrap="truncate">{m.lastAt > 0 ? ` ${ago(Math.max(0, at - m.lastAt))} ago` : ` ${NONE}`}</Text>
          </Box>
        )
      })}
      {row(`▰ a minute with logged activity · · none`, 'subtle')}
    </Box>
  )
}

type Heading = (title: string, hint: string, key: string) => ReturnType<Ui['Box']>

const drawLogs = (ui: Ui, c: Paint, view: ViewState, layout: Layout, W: number, heading: Heading, row: Row, wrapped: Wrapped) => {
  const { Box } = ui
  const { report } = view
  const crew = report?.crew ?? []
  const viewed = crew.find(m => memberKey(m) === view.expanded)
  const all = logEntries(crew)
  const filter = effectiveFilter(view.logFilter, viewed ? memberKey(viewed) : null)
  const kept = filterLogs(all, filter, viewed ? memberKey(viewed) : null)
  const limit = view.logsOpen ? LOG_CAP : layout.logRows
  const shown = kept.slice(0, limit)
  const label = filterLabel(filter, viewed?.id)
  const hint = `newest first · ${label} · ${shown.length} of ${kept.length}${view.logsOpen ? '' : ' · l more'}`
  const whoWidth = Math.max(10, Math.min(30, Math.floor(W / 4)))
  const preview = (entry: LogEntry) => {
    const text = `${clockText(entry.at)} ${logTag(entry)} ${pad(entry.who, whoWidth)} ${entry.text}`
    return row(text, entry.level === 'error' ? 'error' : entry.color, W, `log-${entry.id}`)
  }
  const full = (entry: LogEntry) => (
    <Box key={`log-${entry.id}`} flexDirection="column" width={W}>
      {row(`${clockText(entry.at)} ${logTag(entry)} ${entry.who}`, entry.level === 'error' ? 'error' : entry.color)}
      <Box paddingLeft={2} width={W}>{wrapped(`${entry.text}${entry.sourceTruncated ? ' (source truncated)' : ''}`, entry.level === 'error' ? 'error' : 'text')}</Box>
    </Box>
  )
  const empty = !report ? 'No log events yet.'
    : all.length === 0 ? 'No log events yet.'
      : kept.length === 0 ? `No matching logs (filter: ${label}).` : ''
  return (
    <Box key="logs" flexDirection="column" width={W}>
      {heading('RECENT LOGS', hint, 'h-logs')}
      {empty ? row(empty, 'subtle') : null}
      {!empty && limit === 0 ? row(`${kept.length} entries · newest ${clockText(kept[0]?.at ?? 0)} · l to expand`, 'subtle') : null}
      {shown.map(entry => view.logsOpen ? full(entry) : preview(entry))}
    </Box>
  )
}
