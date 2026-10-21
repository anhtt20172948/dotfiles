import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import { INITIAL, ROAM, TICK_MS, caption, look, shownMood, stats, step } from './lib/mood'
import type { PetEvent, Tone } from './lib/mood'
import { PALETTE, WIDTH, frame, mirror, rows } from './lib/sprite'

const petAtom = atom({ plugin: 'pixel-pet', key: 'pet' } as const, INITIAL)
const isHiddenAtom = atom({ plugin: 'pixel-pet', key: 'isHidden' } as const, false)

type Options = { name?: unknown }
type Dollar = EngineInterface

// The band is four rows tall; below that it yields to whatever else draws there.
const ROWS = 4
// Room kept for the name, caption and stats beside the sprite.
const TEXT_COLUMNS = 26

// Set from NO_COLOR when the session starts: the sprite becomes a silhouette
// and the captions lose their colour, keeping weight.
let noColor = false

const TONES: Record<Tone, { color?: string; dimColor?: boolean; bold?: boolean }> = {
  dim: { dimColor: true },
  love: { color: PALETTE.p },
  warn: { color: 'warning' },
}

const tone = (name: Tone) => (noColor && name !== 'dim' ? { bold: true } : TONES[name])

// The pet never holds up a prompt or a tool: a failed update is dropped.
const feed = ($: Dollar, event: (now: number) => PetEvent) =>
  $.clock
    .now()
    .then(now => update($, petAtom, pet => step(pet, event(now))))
    .catch(() => undefined)

export const register: Register = (on, options: Options) => {
  const name = typeof options.name === 'string' && options.name.trim() !== '' ? options.name.trim() : 'Mochi'

  on('session.start', async ($, e, next) => {
    noColor = ((await $.env.get('NO_COLOR')) ?? '') !== ''
    await feed($, now => ({ type: 'start', now }))
    await $.command.register({ name: 'pet', description: `Show or hide ${name} above the prompt` })
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

    return { text: isHidden ? `${name} đi ngủ rồi. Gõ /pet để gọi lại.` : `${name} đã quay lại!` }
  })

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
      await feed($, now => ({ type: 'turn', now, isAborted: e.isAborted }))
    }

    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const below = await next(e)
    if (e.props.hasSurvey || e.props.maxRows < ROWS || (await read($, isHiddenAtom))) {
      return below
    }

    const { Box, Text } = $.ui.resolve(e)
    const pet = await read($, petAtom)
    const mood = shownMood(pet, e.props.isWorking)
    const room = Math.max(0, Math.min(ROAM, e.props.bodyColumns - WIDTH - TEXT_COLUMNS))
    const grid = frame(look(mood, pet.tick))
    const lines = rows(pet.dir === -1 ? mirror(grid) : grid, noColor)
    const said = caption(mood, pet)

    return (
      <Box flexDirection="column">
        <Box flexDirection="row">
          <Box flexDirection="column" marginLeft={Math.min(pet.x, room)}>
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
          <Box flexDirection="column" marginLeft={2}>
            <Text> </Text>
            <Text wrap="truncate-end">
              <Text bold color={noColor ? undefined : PALETTE.o}>{name}</Text>
              <Text dimColor> · </Text>
              <Text {...tone(said.tone)}>{said.text}</Text>
            </Text>
            <Text dimColor wrap="truncate-end">{stats(pet)}</Text>
          </Box>
        </Box>
        {below}
      </Box>
    )
  })
}
