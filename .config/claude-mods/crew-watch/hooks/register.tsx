import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { CrewMember, CrewReport } from '../types'
import { QUOTA_NOTE, TOOLS_DIRECT_NOTE, ago, cacheHit, cacheText, callTokensText, clip, clockText, contextText, dispatchText, effortText, gauge, modelsText, quotaRows, statusLine, tokens, toolTokenNote, toolTokenText, toolTokenTotal, totalTokens } from './format'
import { DEFAULT_THEME, isNoColorSet, isThemeName, isTruecolorTerm, themePainter } from './theme'
import type { Paint } from './theme'
import { activityLane, crewState, dashboardLayout, fleetModels, harnessColor, laneGeometry, memberKey, recentLog, sortedTools, toggleExpanded } from './dashboard'

type Dollar = EngineInterface

const PANE = 'crew-watch'
const TITLE = 'Crew'
const POLL_TIMEOUT_MS = 20_000

const reportAtom = atom({ plugin: 'crew-watch', key: 'report' } as const, null)
const errorAtom = atom({ plugin: 'crew-watch', key: 'error' } as const, '')
const expandedAtom = atom({ plugin: 'crew-watch', key: 'expanded' } as const, null)

const HELP = [
  '/crew           open or close the Crew pane',
  '/crew refresh   re-read the crew logs now',
  '/crew help      this text',
].join('\n')

let intervalMs = 5000
let configuredHomes: string[] = []
let inFlight: Promise<void> | null = null
let themeName: string = DEFAULT_THEME
let paint: Paint = themePainter(DEFAULT_THEME, { isNoColor: false, isTruecolor: true })

/** Builds the painter from the Theme option and what the terminal says (NO_COLOR, COLORTERM). */
async function loadPaint($: Dollar): Promise<void> {
  paint = themePainter(themeName, {
    isNoColor: isNoColorSet(await $.env.get('NO_COLOR')),
    isTruecolor: isTruecolorTerm(await $.env.get('COLORTERM')),
  })
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

async function readCrew($: Dollar): Promise<void> {
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
      ...homes.flatMap(home => ['--home', home]),
    ]
    const run = await $.process.run(argv, { timeoutMs: POLL_TIMEOUT_MS })
    if (run.exitCode !== 0) {
      const why = run.stderr.trim().split('\n').pop() || `exit ${run.exitCode}`
      await update($, errorAtom, () => `crew_usage.py failed: ${why}`)
      return
    }
    const report = JSON.parse(run.stdout) as CrewReport
    await update($, reportAtom, () => report)
    await update($, errorAtom, () => report.errors.join('; '))
    $.ui.status(statusLine(report.crew, report.totals, report.generatedAt))
  } catch (err) {
    await update($, errorAtom, () => `crew poll failed: ${err instanceof Error ? err.message : String(err)}`)
  }
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

    return { text: 'Crew pane opened.' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
    const c = paint
    const report = await read($, reportAtom)
    const error = await read($, errorAtom)
    const expanded = await read($, expandedAtom)
    const W = Math.max(1, e.props.bodyColumns)
    const crew = report?.crew ?? []
    const now = report?.generatedAt ?? 0
    const providers = report?.quota.providers ?? {}
    const layout = dashboardLayout(W, e.props.placement, crew.length)
    const active = crew.filter(m => ['working', 'active'].includes(crewState(m, now).label)).length
    const row = (text: string, color = 'text', width = W) => <Text color={c(color)} wrap="truncate">{clip(text, width)}</Text>
    const title = `CREW · ${crew.length} live · ${active} active`
    const age = (m: CrewMember) => m.lastAt > 0 ? `${ago(Math.max(0, now - m.lastAt))} ago` : 'no activity'
    const keyOf = (m: CrewMember) => `card-${memberKey(m)}`
    const press = (m: CrewMember) => async () => {
      await update($, expandedAtom, value => toggleExpanded(value, memberKey(m)))
    }
    const control = (m: CrewMember, i: number, width: number) => (
      <Button key={keyOf(m)} plain hotkey={i < 9 ? String(i + 1) : undefined}
        label={'  '.repeat(m.depth) + clip(m.id, Math.max(1, width - 3 - m.depth * 2))} onPress={press(m)} />
    )
    const header = <Text weight="bold" wrap="truncate">{title}</Text>
    const failure = error !== '' ? row(error, 'error') : null

    // Each child is exactly one clipped row: at most eight, including an error.
    if (layout.mode === 'mini') {
      return (
        <Box flexDirection="column" width={W}>
          {header}
          {report ? row(`${tokens(totalTokens(report.totals))} tok · ${report.totals.requests} req · ${report.totals.toolCalls} tools`, 'suggestion') : row('Reading the crew logs…', 'subtle')}
          {report ? row(cacheText(report.totals, 6), 'permission') : null}
          {crew.slice(0, layout.shown).map(m => row(`${crewState(m, now).mark} ${'  '.repeat(m.depth)}${m.id} · ${dispatchText(m)} · ${age(m)}`, harnessColor(m.harness)))}
          {crew.length > layout.shown ? row(`+${crew.length - layout.shown} more · dock /crew for details`, 'subtle') : null}
          {report && crew.length === 0 ? row('No crewmates are live.', 'subtle') : null}
          {failure}
        </Box>
      )
    }

    const card = (m: CrewMember, i: number, width: number, detail = false) => {
      const color = harnessColor(m.harness)
      const state = crewState(m, now)
      const inner = Math.max(1, width - 4)
      const line = (text: string, tone = 'text') => row(text, tone, inner)
      const top = detail ? sortedTools(m.tools) : m.topTools.map(t => [t.name, t.count] as const)
      const maximum = Math.max(1, ...top.map(([, n]) => n))
      const spent = Object.values(m.toolTokens).reduce((n, tt) => n + toolTokenTotal(tt), 0)
      const note = toolTokenNote(m)
      return (
        <Box key={`panel-${memberKey(m)}`} flexDirection="column" borderStyle="round" borderColor={c(color)} width={width} paddingX={1}>
          {detail ? <Text weight="bold" wrap="wrap">{m.description}</Text> : control(m, i, inner)}
          {line(`${m.kind} · ${m.project || 'no project'}${m.depth > 0 ? ` · nested ${m.depth}` : ''}`, 'subtle')}
          {line(`${state.mark} ${state.label}`, state.color)}
          {line(age(m), 'subtle')}
          {line(dispatchText(m), color)}
          {line(effortText(m.effort), color)}
          {line(modelsText(m.models) || 'no model requests yet', color)}
          {line(contextText(m), m.contextWindow && m.context / m.contextWindow >= 0.8 ? 'warning' : 'suggestion')}
          {line(`in ${tokens(m.input)} · out ${tokens(m.output)} · ${m.requests} req`)}
          {line(`thinking ${tokens(m.reasoning)}`, 'subtle')}
          {line(`cache ${gauge(Number.parseFloat(cacheHit(m)), 8)} ${cacheHit(m)}`, 'permission')}
          {line(`read ${tokens(m.cacheRead)} · write ${tokens(m.cacheWrite)}`, 'subtle')}
          {line(`tools ${m.toolCalls} · ${tokens(spent)} tok`)}
          {top.map(([name, count]) => line(`${clip(name, Math.max(4, inner - 22))} ${gauge(count * 100 / maximum, 5)} ${count} ${tokens(toolTokenTotal(m.toolTokens[name]))}`, color))}
          {quotaRows(m.quota, providers, now).map(r => line(r.text, r.tone))}
          {!m.readable ? line(`usage is not readable for the ${m.harness} harness`, 'subtle') : m.sessions === 0 ? line('no transcript found for its worktree yet', 'subtle') : null}
          {m.lastTool ? line(`▸ ${m.lastTool}`, 'subtle') : null}
          {m.lastText ? line(`“${m.lastText}”`, 'subtle') : null}
          {m.status ? line(`status ${m.status}`, 'permission') : null}
          {detail ? <Text wrap="wrap">{`branch ${m.branch || 'unknown'}\nworktree ${m.worktree || 'unknown'}\nhome ${m.home}\nharness ${m.harness} · ${m.sessions} transcripts`}</Text> : null}
          {detail ? Object.entries(m.models).map(([model, count]) => <Text color={c(color)} wrap="wrap">{`${model} ×${count}`}</Text>) : null}
          {detail ? sortedTools(m.tools).map(([tool, count]) => <Text wrap="wrap">{`${tool} ×${count} · ${toolTokenText(m.toolTokens[tool])}`}</Text>) : null}
          {detail && note ? <Text color={c('subtle')} wrap="wrap">{note}</Text> : null}
          {detail && Object.keys(m.quota).length > 0 ? <Text color={c('subtle')} wrap="wrap">{QUOTA_NOTE}</Text> : null}
          {detail && Object.keys(m.quota).length > 0 ? <Text color={c('subtle')} wrap="wrap">{TOOLS_DIRECT_NOTE}</Text> : null}
          {detail ? m.recentTools.map(event => <Text color={c('subtle')} wrap="wrap">{`${clockText(event.at)} ${event.tool ? `${callTokensText(event)} · ` : ''}${event.text}`}</Text>) : null}
          {detail && m.lastText ? <Text wrap="wrap">{m.lastText}</Text> : null}
          {detail && m.status ? <Text color={c('permission')} wrap="wrap">{m.status}</Text> : null}
        </Box>
      )
    }

    const geometry = laneGeometry(W)
    const laneWidth = geometry.cells
    const lanes = (
      <Box flexDirection="column" width={W}>
        {row(`ACTIVITY · last ${laneWidth} minutes · 1 cell/min`, 'subtle')}
        <Box width={W}><Box key="lane-axis-gutter" width={geometry.offset} flexShrink={0} /><Text key="lane-axis" color={c('subtle')}>{geometry.axis}</Text></Box>
        {crew.map((m, i) => (
          <Box width={W}>
            <Box width={geometry.markWidth} flexShrink={0}><Text color={c(crewState(m, now).color)}>{crewState(m, now).mark + ' '}</Text></Box>
            <Box width={geometry.nameWidth} flexShrink={0}>{layout.mode === 'lanes' ? control(m, i, geometry.nameWidth) : row(`${'  '.repeat(m.depth)}${m.id}`, harnessColor(m.harness), geometry.nameWidth)}</Box>
            <Box key={`lane-gap-${memberKey(m)}`} width={geometry.gap} flexShrink={0} />
            <Text color={c(harnessColor(m.harness))}>{activityLane(m.activity, now, laneWidth)}</Text>
            <Text dimColor wrap="truncate">{' ' + age(m)}</Text>
          </Box>
        ))}
      </Box>
    )
    const viewed = crew.find(m => memberKey(m) === expanded)
    const models = fleetModels(crew)
    const log = recentLog(crew, 8)
    const legend = [...new Set(crew.map(m => m.harness))]
    const inner = Math.max(1, W - 4)
    return (
      <Box flexDirection="column" width={W}>
        <Box justifyContent="center" width={W}>{header}</Box>
        <Box columnGap={2} width={W}>{legend.map(harness => <Text color={c(harnessColor(harness))} wrap="truncate">{`■ ${harness}`}</Text>)}</Box>
        {failure}
        <Box flexDirection="column" borderStyle="round" borderColor={c('claude')} paddingX={1} width={W}>
          <Text weight="bold" color={c('claude')}>FLEET</Text>
          {report ? row(`${tokens(totalTokens(report.totals))} tokens · ${report.totals.requests} requests`, 'text', inner) : row('Reading the crew logs…', 'subtle', inner)}
          {report ? row(`${report.totals.toolCalls} tool calls`, 'text', inner) : null}
          {report ? row(`in ${tokens(report.totals.input)} · out ${tokens(report.totals.output)} · thinking ${tokens(report.totals.reasoning)}`, 'subtle', inner) : null}
          {report ? row(`cache ${gauge(Number.parseFloat(cacheHit(report.totals)))} ${cacheHit(report.totals)}`, 'permission', inner) : null}
          {report ? row(`read ${tokens(report.totals.cacheRead)} · write ${tokens(report.totals.cacheWrite)}`, 'subtle', inner) : null}
          {report ? quotaRows(report.quota.fleet, providers, now).map(r => row(r.text, r.tone, inner)) : null}
          {report && Object.keys(report.quota.fleet).length > 0 ? <Text color={c('subtle')} wrap="wrap">{QUOTA_NOTE}</Text> : null}
          {report && Object.keys(report.quota.fleet).length > 0 ? <Text color={c('subtle')} wrap="wrap">{TOOLS_DIRECT_NOTE}</Text> : null}
          {models.map(([model, count]) => row(`${model} ×${count}`, 'suggestion', inner))}
          {report && crew.length === 0 ? row('No crewmates are live.', 'subtle', inner) : null}
        </Box>
        {crew.length > 0 ? row(`CREWMATES · 1-${Math.min(crew.length, 9)} expand / collapse`, 'subtle') : null}
        {layout.mode === 'cards' && crew.length > 0 ? <Box columnGap={1} width={W}>{crew.map((m, i) => card(m, i, layout.cardWidth))}</Box> : null}
        {crew.length > 0 ? lanes : null}
        {viewed ? card(viewed, crew.indexOf(viewed), W, true) : null}
        <Box flexDirection="column" borderStyle="round" borderColor={c('border')} paddingX={1} width={W} marginTop={1}>
          <Text dimColor>CREW LOG</Text>
          {log.length === 0 ? row('No events yet.', 'subtle', inner) : null}
          {log.map(event => row(`${clockText(event.at)} ${event.who} · ${event.kind === 'tool' ? '▸' : '◇'} ${event.text}`, event.color, inner))}
        </Box>
      </Box>
    )
  })
}
