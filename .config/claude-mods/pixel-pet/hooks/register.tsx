import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'

import type { Attack, Pet, Power } from '../types'
import { FRAME_MS, TECHNIQUES, milestoneShout, withAttack } from './lib/beam'
import { CELL } from './lib/cells'
import { FORM_NAMES, NAMES, characterChoice, fighterFor, formatPower, levelOf, powerLevel } from './lib/fighter'
import type { Character, Fighter, Form } from './lib/fighter'
import { INITIAL, ROAM, TICK_MS, caption, look, shownMood, stats, step } from './lib/mood'
import type { PetEvent, Tone } from './lib/mood'
import { BEAM_TEXT_COLORS, beamPalette } from './lib/palette'
import { NAME_COLORS, TIERS, formColor, frame, mirror, palette, palmsOf, renderChoice, rows, tierFor } from './lib/sprite'
import type { Look, Render, Tier } from './lib/sprite'

const UNKNOWN: Power = { model: null, effort: null }

const petAtom = atom({ plugin: 'pixel-pet', key: 'pet' } as const, INITIAL)
const isHiddenAtom = atom({ plugin: 'pixel-pet', key: 'isHidden' } as const, false)
const powerAtom = atom({ plugin: 'pixel-pet', key: 'power' } as const, UNKNOWN)

type Options = { name?: unknown; character?: unknown; render?: unknown; attacks?: unknown }
type Dollar = EngineInterface

// Room kept for the name, caption, form and counts beside the sprite
// (`Ultra Instinct · power 1,000,000!` fits).
const TEXT_COLUMNS = 36

// Where the name and captions start beside each tier's sprite: level with the face.
const TEXT_TOP: Record<Tier, number> = { large: 4, medium: 2, head: 1 }

// The columns between the sprite and its text.
const TEXT_GAP = 2

// The longest beam each tier fires, in columns; the head alone fires none. A
// beam never takes the room kept for the text, so a narrow band fires a short
// one or none.
const BEAM_COLUMNS: Record<Tier, number> = { large: 40, medium: 24, head: 0 }

// The Attacks row of /config: on unless it is turned off.
const attacksChoice = (value: unknown) => value !== false && value !== 'false'

// Set from NO_COLOR when the session starts: the sprite becomes a silhouette
// and the captions lose their colour, keeping weight.
let noColor = false

// A beam's shout takes the beam's colour instead.
const TONES: Record<Exclude<Tone, 'beam'>, { color?: string; dimColor?: boolean; bold?: boolean }> = {
  dim: { dimColor: true },
  cheer: { color: 'success', bold: true },
  warn: { color: 'warning' },
}

const tone = (name: Tone, beamColor: string) => {
  if (noColor && name !== 'dim') {
    return { bold: true }
  }

  return name === 'beam' ? { color: beamColor, bold: true } : TONES[name]
}

// The pet never holds up a prompt or a tool: a failed update is dropped.
const feed = ($: Dollar, event: (now: number) => PetEvent): Promise<Pet | undefined> =>
  $.clock
    .now()
    .then(now => update($, petAtom, pet => step(pet, event(now))))
    .catch(() => undefined)

// The timer that draws a beam's frames while one is fired; null between beams.
let frames: Timer | null = null

// Redraws the beam every frame until it has given way, then stops.
const animate = ($: Dollar) => {
  if (frames !== null) {
    return
  }
  const timer = $.clock.every(FRAME_MS, () => {
    void feed($, now => ({ type: 'frame', now })).then(pet => {
      if (pet?.mood !== 'attack') {
        timer.cancel()
        frames = frames === timer ? null : frames
      }
    })
  })
  frames = timer
}

// What the main conversation runs on. An unchanged value is kept as it is, so
// nothing redraws for it.
const setPower = ($: Dollar, next: Partial<Power>) =>
  update($, powerAtom, power => {
    const merged = { ...power, ...next }

    return merged.model === power.model && merged.effort === power.effort ? power : merged
  }).catch(() => undefined)

// The effort the settings ask for, until a model request says what it runs at.
const settingsEffort = async ($: Dollar) =>
  levelOf(await $.settings.read({ key: 'effortLevel' }).catch(() => undefined)) ??
  levelOf(await $.env.get('CLAUDE_CODE_EFFORT_LEVEL').catch(() => undefined))

const sessionModel = ($: Dollar) => $.session.model().catch(() => null)

type Sprite = {
  fighter: Fighter
  seen: Look
  pet: Pet
  attack: Attack | null
  tier: Tier
  render: Render
  // How many columns a beam may push the text right.
  beamColumns: number
}

// The sprite's rows: the fighter facing the way it walks or, firing, facing
// its text with the beam widening the sprite and pushing the text right. The
// head alone fires no beam, and its aura flickers with the beam's frames.
const spriteRows = ({ fighter, seen, pet, attack, tier, render, beamColumns }: Sprite) => {
  if (attack === null) {
    const grid = frame(fighter, seen, pet.tick, tier, render)

    return rows(pet.dir === -1 ? mirror(grid) : grid, palette(fighter, seen), render, noColor)
  }
  const grid = frame(fighter, seen, pet.tick + Math.floor(attack.elapsed / FRAME_MS), tier, render)
  const fired =
    tier === 'head'
      ? grid
      : withAttack(grid, { attack, spot: palmsOf(tier, render).spot, cell: CELL[render], maxColumns: beamColumns })
  const colors = { ...palette(fighter, seen), ...beamPalette(TECHNIQUES[fighter.character]) }

  return rows(fired, colors, render, noColor)
}

// The form the power level is reckoned in, as the band draws it.
const formOf = ($: Dollar, choice: Character | null): Promise<Form> =>
  read($, powerAtom)
    .then(power => fighterFor(power.model, power.effort, choice).form)
    .catch(() => 'base' as const)

export const register: Register = (on, options: Options) => {
  const named = typeof options.name === 'string' && options.name.trim() !== '' ? options.name.trim() : null
  const choice = characterChoice(options.character)
  // Sextants unless /config asks for half blocks, for a font without them.
  const render = renderChoice(options.render)
  // A finished turn fires a signature beam unless /config turns Attacks off.
  const attacks = attacksChoice(options.attacks)

  on('session.start', async ($, e, next) => {
    noColor = ((await $.env.get('NO_COLOR')) ?? '') !== ''
    await feed($, now => ({ type: 'start', now }))
    await setPower($, { model: await sessionModel($), effort: await settingsEffort($) })
    await $.command.register({ name: 'pet', description: 'Show or hide the pet above the prompt' })
    $.clock.every(TICK_MS, () => {
      void (async () => {
        if (!(await read($, isHiddenAtom))) {
          await feed($, now => ({ type: 'tick', now }))
        }
      })()
    })

    return next(e)
  })

  on('command.run', { command: 'pet' }, async $ => {
    const isHidden = !(await read($, isHiddenAtom))
    await update($, isHiddenAtom, () => isHidden)
    const power = await read($, powerAtom)
    const name = named ?? NAMES[fighterFor(power.model, power.effort, choice).character]

    return { text: isHidden ? `${name} is resting. Type /pet to call them back.` : `${name} is back!` }
  })

  // Every request of the main conversation names its model and effort: the
  // truest reading, and it follows /model, /effort and /config as they change.
  on('turn.step', async function* ($, e, next) {
    if (e.agentId === undefined) {
      void setPower($, { model: e.model, effort: levelOf(e.effort) })
    }

    return yield* next(e)
  })

  // Between requests, `/model <name>` and `/effort <level>` show at once; the
  // session's effort carries across a model switch. A picker's choice shows by
  // the next request. The pet never stands in a command's way: a failure
  // replays what the command settled to.
  on('command.run', { command: 'model' }, async ($, e, next) => {
    const ran = await next(e)
    await setPower($, { model: await sessionModel($) })

    return ran
  }).catch(($, e, next) => next(e))

  on('command.run', { command: 'effort' }, async ($, e, next) => {
    const ran = await next(e)
    await setPower($, { effort: levelOf(e.args) ?? (await settingsEffort($)) })

    return ran
  }).catch(($, e, next) => next(e))

  // Prompts and tools are never waited on for the pet: its updates run beside them.
  on('prompt.submit', ($, e, next) => {
    void feed($, now => ({ type: 'prompt', now }))

    return next(e)
  })

  on('tool.call', async ($, e, next) => {
    const started = feed($, now => ({ type: 'tool', now, tool: e.tool }))
    const ran = await next(e)
    const isError = ran.deny !== undefined || ran.isError === true
    void started.then(() => feed($, now => ({ type: 'toolDone', now, tool: e.tool, isError })))

    return ran
  })

  on('turn.complete', async ($, e, next) => {
    // Subagents end turns too; only the main conversation's count.
    if (e.agentId === undefined) {
      const form = await formOf($, choice)
      const pet = await feed($, now => ({ type: 'turn', now, isAborted: e.isAborted, form, attacks }))
      if (pet?.mood === 'attack') {
        animate($)
      }
    }

    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const below = await next(e)
    // The largest fighter the band has room for; below the head alone it gives way.
    const tier = tierFor(e.props.maxRows, e.props.bodyColumns, TEXT_COLUMNS)
    if (e.props.hasSurvey || tier === null || (await read($, isHiddenAtom))) {
      return below
    }

    const { Box, Text } = $.ui.resolve(e)
    const pet = await read($, petAtom)
    const power = await read($, powerAtom)
    const fighter = fighterFor(power.model, power.effort, choice)
    const mood = shownMood(pet, e.props.isWorking)
    const seen = look(mood, pet.tick)
    const room = Math.max(0, Math.min(ROAM, e.props.bodyColumns - TIERS[tier].columns - TEXT_COLUMNS))
    const left = Math.min(pet.x, room)
    const attack = mood === 'attack' ? pet.attack : null
    // A beam never takes the columns kept for the text.
    const free = e.props.bodyColumns - left - TIERS[tier].columns - TEXT_GAP - TEXT_COLUMNS
    const beamColumns = Math.max(0, Math.min(BEAM_COLUMNS[tier], free))
    const lines = spriteRows({ fighter, seen, pet, attack, tier, render, beamColumns })
    const said = caption(mood, pet, fighter.character)
    const name = named ?? NAMES[fighter.character]
    const shade = formColor(fighter.form)
    const beamColor = BEAM_TEXT_COLORS[TECHNIQUES[fighter.character]]

    return (
      <Box flexDirection="column">
        <Box flexDirection="row">
          {/* The sprite keeps its width; the text beside it truncates instead. */}
          <Box flexDirection="column" flexShrink={0} marginLeft={left}>
            {lines.map(line => (
              <Text>
                {line.map(segment => (
                  <Text color={segment.color} backgroundColor={segment.backgroundColor}>
                    {segment.text}
                  </Text>
                ))}
              </Text>
            ))}
          </Box>
          <Box flexDirection="column" marginLeft={TEXT_GAP} marginTop={TEXT_TOP[tier]}>
            <Text wrap="truncate-end">
              <Text bold color={noColor ? undefined : NAME_COLORS[fighter.character]}>
                {name}
              </Text>
              <Text dimColor> · </Text>
              <Text {...tone(said.tone, beamColor)}>{said.text}</Text>
            </Text>
            <Text wrap="truncate-end">
              <Text bold={shade !== undefined} color={noColor ? undefined : shade}>
                {FORM_NAMES[fighter.form]}
              </Text>
              <Text dimColor> · {formatPower(powerLevel(fighter.form, pet))}</Text>
            </Text>
            {attack?.milestone == null ? (
              <Text dimColor wrap="truncate-end">
                {stats(pet)}
              </Text>
            ) : (
              <Text wrap="truncate-end" {...tone('beam', beamColor)}>
                {milestoneShout(attack.milestone)}
              </Text>
            )}
          </Box>
        </Box>
        {below}
      </Box>
    )
  })
}
