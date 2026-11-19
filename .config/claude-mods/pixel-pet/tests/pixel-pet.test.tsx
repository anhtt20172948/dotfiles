import { expect, mock, test } from 'claude-code/testing'
import type { TestBody } from 'claude-code/testing'

import { BODIES } from '../hooks/lib/art'
import type { Pose } from '../hooks/lib/art'
import {
  CHARACTERS,
  FORMS,
  LEVELS,
  characterChoice,
  characterFor,
  fighterFor,
  formatPower,
  levelOf,
  powerLevel,
} from '../hooks/lib/fighter'
import type { Fighter, Level } from '../hooks/lib/fighter'
import { INITIAL, REACT_MS, ROAM, SLEEP_MS, caption, look, shownMood, stats, step } from '../hooks/lib/mood'
import type { PetEvent } from '../hooks/lib/mood'
import { ALL_COLORS, TIERS, frame, mirror, palette, rows, tierFor } from '../hooks/lib/sprite'
import type { Look, Tier } from '../hooks/lib/sprite'
import type { Pet } from '../types'

const run = (pet: Pet, events: PetEvent[]) => events.reduce(step, pet)

const ticks = (from: number, count: number, every = 400): PetEvent[] =>
  Array.from({ length: count }, (_, i) => ({ type: 'tick', now: from + (i + 1) * every }))

// The small fighter's width, which the pixel-level checks below draw at.
const WIDTH = TIERS.medium.width

const STILL: Look = {
  pose: 'stand',
  step: 0,
  face: 'idle',
  isEyesClosed: false,
  hasMouth: false,
  hasTear: false,
  isPoweredDown: false,
  aura: 'none',
}

const FIGHTERS: Fighter[] = CHARACTERS.flatMap(character =>
  LEVELS.map(level => ({ character, form: FORMS[character][level] })),
)

const pixels = (grid: readonly string[], pixel: string) => grid.join('').split(pixel).length - 1

test('the model picks the character: Opus Goku, Sonnet Vegeta, anything else kid Gohan', async () => {
  expect(characterFor('claude-opus-5-5')).toBe('goku')
  expect(characterFor('claude-opus-5-5[1m]')).toBe('goku')
  expect(characterFor('Opus 5.5')).toBe('goku')
  expect(characterFor('claude-sonnet-5-5')).toBe('vegeta')
  expect(characterFor('sonnet')).toBe('vegeta')
  expect(characterFor('claude-haiku-5-5')).toBe('gohan')
  expect(characterFor('some-other-model')).toBe('gohan')
  expect(characterFor(null)).toBe('gohan')
})

test('the effort picks the form, each character its own top forms', async () => {
  expect(FORMS.goku).toEqual({ low: 'base', medium: 'ssj1', high: 'ssj2', xhigh: 'ssj3', max: 'ui' })
  expect(FORMS.vegeta).toEqual({ low: 'base', medium: 'ssj1', high: 'ssj2', xhigh: 'majin', max: 'ego' })
  expect(FORMS.gohan).toEqual({ low: 'base', medium: 'ssj1', high: 'ssj2', xhigh: 'ultimate', max: 'beast' })
  expect(fighterFor('claude-opus-5-5', 'max')).toEqual({ character: 'goku', form: 'ui' })
  expect(fighterFor('claude-sonnet-5-5', 'xhigh')).toEqual({ character: 'vegeta', form: 'majin' })
  // A model without effort, or an effort that is no level, stays in base form.
  expect(fighterFor('claude-haiku-5-5', null)).toEqual({ character: 'gohan', form: 'base' })
  // The Character option overrides the model.
  expect(fighterFor('claude-opus-5-5', 'high', 'vegeta')).toEqual({ character: 'vegeta', form: 'ssj2' })
})

test('levels and character choices are read leniently, anything else is none', async () => {
  expect(levelOf('xhigh')).toBe('xhigh')
  expect(levelOf(' High ')).toBe('high')
  expect(levelOf('auto')).toBeNull()
  expect(levelOf('')).toBeNull()
  expect(levelOf(3)).toBeNull()
  expect(levelOf(undefined)).toBeNull()
  expect(characterChoice('goku')).toBe('goku')
  expect(characterChoice('auto')).toBeNull()
  expect(characterChoice('frieza')).toBeNull()
})

test('the power level grows with training and the form multiplies it', async () => {
  expect(powerLevel('base', { turns: 0, tools: 0, errors: 0 })).toBe(100)
  expect(powerLevel('ssj2', { turns: 2, tools: 5, errors: 1 })).toBe((100 + 100 + 50 - 25) * 100)
  expect(powerLevel('base', { turns: 0, tools: 0, errors: 99 })).toBe(1)
  expect(formatPower(9_000)).toBe('power 9,000')
  expect(formatPower(12_400)).toBe('power 12,400!')
})

test('every colour lands on the 256-colour cube or the grey ramp, as tmux sessions draw it', async () => {
  // Claude Code in tmux quantizes each channel to round(v / 51); these values sit
  // closest to the cube level they land on, so both renders match.
  const CHANNELS = new Set(['00', '4c', '7f', 'af', 'd7', 'ff'])
  for (const color of ALL_COLORS) {
    const [r, g, b] = color.slice(1).match(/../g) ?? []
    expect({ color, isSafe: r === g && g === b ? true : [r, g, b].every(c => CHANNELS.has(c ?? '')) }).toEqual({
      color,
      isSafe: true,
    })
  }
})

test('two pixel rows make one text row of half blocks, runs merged', async () => {
  const colors = { k: 'black', o: 'orange' }
  const lines = rows(['ko..', 'k.o.'].map(row => row.padEnd(WIDTH, '.')), colors)

  expect(lines).toHaveLength(1)
  expect(lines[0]?.[0]).toEqual({ text: '█', color: colors.k })
  expect(lines[0]?.[1]).toEqual({ text: '▀▄', color: colors.o })
  expect(lines[0]?.[2]).toEqual({ text: ' '.repeat(WIDTH - 3) })
  expect(rows(['ko'.padEnd(WIDTH, '.'), 'ok'.padEnd(WIDTH, '.')], colors)[0]?.[0]).toEqual({
    text: '▀',
    color: colors.k,
    backgroundColor: colors.o,
  })
})

test('every fighter, form, pose and face is 24x20 large, 16x12 small, 16x8 head alone, and mirrors', async () => {
  const faces = ['idle', 'blink', 'power', 'happy', 'hurt', 'calm'] as const
  for (const fighter of FIGHTERS) {
    for (const pose of Object.keys(BODIES) as Pose[]) {
      for (const [tier, size] of Object.entries(TIERS) as [Tier, (typeof TIERS)[Tier]][]) {
        const face = faces[(pose.length + fighter.form.length) % faces.length] ?? 'idle'
        const grid = frame(fighter, { ...STILL, pose, face, aura: 'flare' }, 3, tier)
        expect(grid).toHaveLength(size.height)
        expect(grid.every(row => row.length === size.width)).toBe(true)
        expect(rows(grid, palette(fighter, STILL))).toHaveLength(size.rows)
        // Every pixel has a colour.
        const colors = palette(fighter, STILL)
        expect([...grid.join('')].every(pixel => pixel === '.' || colors[pixel] !== undefined)).toBe(true)
        expect(mirror(grid).map(row => [...row].reverse().join(''))).toEqual(grid)
      }
    }
  }
})

test('base form has black hair and no aura; Super Saiyan turns it gold and glows', async () => {
  const base = { character: 'goku', form: 'base' } as const
  const ssj1 = { character: 'goku', form: 'ssj1' } as const
  expect(palette(base, STILL).h).not.toBe(palette(ssj1, STILL).h)
  expect(pixels(frame(base, { ...STILL, aura: 'flare' }, 0), 'o')).toBe(0)
  expect(pixels(frame(ssj1, { ...STILL, aura: 'calm' }, 0), 'o')).toBeGreaterThan(0)
  // Ultra Instinct is silver, Ultra Ego purple, Beast silver with red eyes.
  const rgb = (color: string | undefined) => (color?.slice(1).match(/../g) ?? []).map(c => parseInt(c, 16))
  const [uiR, uiG, uiB] = rgb(palette({ character: 'goku', form: 'ui' }, STILL).h)
  expect(uiR === uiG && uiG === uiB && (uiR ?? 0) > 128).toBe(true)
  const [egoR = 0, egoG = 0, egoB = 0] = rgb(palette({ character: 'vegeta', form: 'ego' }, STILL).h)
  expect(egoB > egoG && egoR > egoG).toBe(true)
  const beast = palette({ character: 'gohan', form: 'beast' }, STILL)
  expect(beast.e).toBe(beast.M)
})

test('working flares the aura two deep; Super Saiyan 2 crackles with sparks', async () => {
  const ssj1 = { character: 'goku', form: 'ssj1' } as const
  const ssj2 = { character: 'goku', form: 'ssj2' } as const
  const flare = { ...STILL, pose: 'power', aura: 'flare' } as const
  expect(pixels(frame(ssj1, flare, 0), 'i')).toBeGreaterThan(0)
  expect(pixels(frame(ssj1, flare, 0), 'o')).toBeGreaterThan(0)
  const sparks = (fighter: Fighter) =>
    Array.from({ length: 23 }, (_, tick) => pixels(frame(fighter, flare, tick), 'z')).reduce((a, b) => a + b)
  expect(sparks(ssj1)).toBe(0)
  expect(sparks(ssj2)).toBeGreaterThan(0)
  // The flames rise: the pattern moves between ticks.
  expect(frame(ssj2, flare, 0)).not.toEqual(frame(ssj2, flare, 1))
})

test('Super Saiyan 3 grows long hair and Majin Vegeta wears the M', async () => {
  const ssj3 = frame({ character: 'goku', form: 'ssj3' }, STILL, 0)
  const ssj2 = frame({ character: 'goku', form: 'ssj2' }, STILL, 0)
  expect(ssj3[10]).toMatch(/h/)
  expect(ssj2[10]).not.toMatch(/h/)
  expect(pixels(frame({ character: 'vegeta', form: 'majin' }, STILL, 0), 'M')).toBeGreaterThan(0)
  expect(pixels(frame({ character: 'vegeta', form: 'ssj2' }, STILL, 0), 'M')).toBe(0)
})

test('a failure knocks it out of its form: base hair, no aura, a tear', async () => {
  const fighter = { character: 'goku', form: 'ssj3' } as const
  const knocked = look('sad', 0)
  const grid = frame(fighter, knocked, 0)
  expect(knocked).toMatchObject({ pose: 'knocked', isPoweredDown: true, aura: 'none' })
  expect(palette(fighter, knocked).h).toBe(palette({ character: 'goku', form: 'base' }, STILL).h)
  expect(grid[10]).not.toMatch(/h/)
  expect(pixels(grid, 'b')).toBe(1)
  expect(pixels(grid, 'o') + pixels(grid, 'i')).toBe(0)
})

test('moods take their poses: power up, thumbs up, meditate', async () => {
  expect(look('working', 1)).toMatchObject({ pose: 'power', aura: 'flare', hasMouth: true })
  expect(look('happy', 0)).toMatchObject({ pose: 'thumbs', isEyesClosed: true })
  expect(look('sleep', 0)).toMatchObject({ pose: 'meditate', isEyesClosed: true, aura: 'none' })
  // Meditating sits a row lower; closed eyes are drawn, open ones are gone.
  const goku = { character: 'goku', form: 'base' } as const
  expect(frame(goku, look('sleep', 0), 0)[0]).toBe('.'.repeat(WIDTH))
  expect(frame(goku, look('sleep', 0), 0, 'large').slice(0, 2).join('')).not.toMatch(/[^.]/)
  expect(pixels(frame(goku, look('sleep', 0), 0), 'e')).toBe(0)
  expect(pixels(frame(goku, look('sleep', 0), 0), 'c')).toBe(2)
})

test('the large fighter wears each mood on its face', async () => {
  const goku = { character: 'goku', form: 'ssj2' } as const
  const face = (mood: 'idle' | 'working' | 'happy' | 'sad' | 'sleep') => frame(goku, look(mood, 1), 1, 'large')
  // Idle eyes are open with a glint; working, narrowed with the teeth bared.
  expect(pixels(face('idle'), 'w')).toBe(2)
  expect(pixels(face('idle'), 'e')).toBe(4)
  expect(pixels(face('working'), 't')).toBe(2)
  expect(pixels(face('working'), 'w')).toBe(0)
  // A finished turn grins and blushes; a failure squeezes the eyes and cries.
  expect(pixels(face('happy'), 'p')).toBe(2)
  expect(pixels(face('happy'), 'e')).toBe(0)
  expect(pixels(face('sad'), 'b')).toBe(1)
  expect(pixels(face('sad'), 'e')).toBe(0)
  // Meditating, the eyes are shut and the mouth closed.
  expect(pixels(face('sleep'), 'e') + pixels(face('sleep'), 'm')).toBe(0)
})

test('the large fighter keeps the details of each character', async () => {
  const idle = look('idle', 1)
  // Brows sit over cols 9-10 and 13-14 of row 8; a scowl's inner ends drop to
  // cols 10 and 13 of row 9, where level brows leave the lashes.
  const inner = (grid: readonly string[]) => `${grid[9]?.[10]}${grid[9]?.[13]}`
  const blink = look('idle', 0)
  for (const seen of [idle, blink]) {
    // Goku's brows are level; Vegeta's slant down to the middle even at rest.
    const gokuBrows = frame({ character: 'goku', form: 'base' }, seen, 1, 'large')[8] ?? ''
    expect(`${gokuBrows.slice(9, 11)} ${gokuBrows.slice(13, 15)}`).toBe('dd dd')
    expect(inner(frame({ character: 'vegeta', form: 'base' }, seen, 1, 'large'))).toBe('dd')
    expect(inner(frame({ character: 'goku', form: 'base' }, seen, 1, 'large'))).not.toContain('d')
  }
  // Super Saiyan 3 has no brows at all.
  expect(frame({ character: 'goku', form: 'ssj3' }, idle, 1, 'large')[8]?.slice(8, 16)).not.toMatch(/d/)
  // Super Saiyan 3's mane falls to the heels; Majin Vegeta wears the M.
  expect(frame({ character: 'goku', form: 'ssj3' }, idle, 1, 'large')[17]).toMatch(/h/)
  expect(frame({ character: 'goku', form: 'ssj2' }, idle, 1, 'large')[17]).not.toMatch(/h/)
  expect(pixels(frame({ character: 'vegeta', form: 'majin' }, idle, 1, 'large'), 'M')).toBe(4)
  // The thumbs up rises beside the face.
  expect(frame({ character: 'gohan', form: 'base' }, look('happy', 0), 0, 'large')[9]?.[20]).toBe('S')
})

test('without colour the fighter is a silhouette, eyes cut out and aura left off', async () => {
  const fighter = { character: 'goku', form: 'ssj2' } as const
  const lit = { ...STILL, aura: 'flare' } as const
  const grid = frame(fighter, lit, 0)
  const lines = rows(grid, palette(fighter, lit), true)
  const text = lines.map(line => line.map(segment => segment.text).join(''))

  expect(lines.flat().every(segment => segment.color === undefined && segment.backgroundColor === undefined)).toBe(true)
  // Text row 2 holds pixel rows 4 (forehead) and 5 (eyes): the eyes leave upper halves.
  expect(text[2]?.[6]).toBe('▀')
  expect(text[2]?.[9]).toBe('▀')
  // The aura's columns at the edge are blank.
  expect(text.every(line => line[0] === ' ')).toBe(true)
  // Every large face keeps its eyes or lashes cut out (text rows 4-6; meditating sits lower).
  for (const mood of ['idle', 'working', 'happy', 'sad', 'sleep'] as const) {
    const seen = look(mood, 1)
    const eyes = rows(frame(fighter, seen, 1, 'large'), palette(fighter, seen), true)
      .slice(4, 7)
      .map(line => line.map(segment => segment.text).join('').slice(8, 16))
    expect({ mood, isCutOut: eyes.some(line => /[ ▀▄]/.test(line)) }).toEqual({ mood, isCutOut: true })
  }
})

test('a turn works, celebrates, then settles back to idle', async () => {
  const started = run(INITIAL, [{ type: 'start', now: 0 }])
  const working = run(started, [
    { type: 'prompt', now: 10 },
    { type: 'tool', now: 20, tool: 'Bash' },
  ])
  expect(working).toMatchObject({ mood: 'working', tool: 'Bash', tools: 1 })
  expect(caption('working', working).text).toMatch(/^running Bash\.+$/)
  expect(caption('working', { ...working, tool: null }).text).toMatch(/^powering up\.+$/)

  const happy = run(working, [
    { type: 'toolDone', now: 30, tool: 'Bash', isError: false },
    { type: 'turn', now: 40, isAborted: false },
  ])
  expect(happy).toMatchObject({ mood: 'happy', tool: null, turns: 1 })
  expect(caption('happy', happy)).toEqual({ text: 'done!', tone: 'cheer' })

  const settled = run(happy, ticks(40, Math.ceil(REACT_MS / 400)))
  expect(settled.mood).toBe('idle')
  expect(stats(settled)).toBe('1 turn · 1 tool')
})

test('a failed tool and an interrupted turn knock it back', async () => {
  const failed = run(INITIAL, [
    { type: 'tool', now: 0, tool: 'Bash' },
    { type: 'toolDone', now: 5, tool: 'Bash', isError: true },
  ])
  expect(failed).toMatchObject({ mood: 'sad', errors: 1 })
  expect(caption('sad', failed).text).toBe('Bash failed…')
  expect(stats(failed)).toBe('0 turns · 1 tool · 1 error')

  const aborted = run(INITIAL, [{ type: 'turn', now: 0, isAborted: true }])
  expect(caption(aborted.mood, aborted).text).toBe('interrupted…')
})

test('idle it walks within its room and meditates, a prompt wakes it', async () => {
  const walked = run(run(INITIAL, [{ type: 'start', now: 0 }]), ticks(0, 200))
  expect(walked.x).toBeGreaterThanOrEqual(0)
  expect(walked.x).toBeLessThanOrEqual(ROAM)

  const asleep = run(walked, [{ type: 'tick', now: SLEEP_MS + 1 }])
  expect(asleep.mood).toBe('sleep')
  expect(caption('sleep', asleep).text).toMatch(/^z/)
  expect(run(asleep, [{ type: 'prompt', now: SLEEP_MS + 2 }]).mood).toBe('working')
})

test('a running turn shows as work, a stale working mood as idle', async () => {
  expect(shownMood({ ...INITIAL, mood: 'sleep' }, true)).toBe('working')
  expect(shownMood({ ...INITIAL, mood: 'working' }, false)).toBe('idle')
  expect(shownMood({ ...INITIAL, mood: 'happy' }, false)).toBe('happy')
})

// What the engine hands the band: a 14-row band (a 40-row terminal), 100 columns wide.
const PROPS = {
  hasSurvey: false,
  isCollapsed: false,
  isWorking: false,
  maxRows: 14,
  bodyColumns: 100,
  scroll: { offset: 0, bodyRows: 13 },
  view: {},
}

const BAND = { plugin: 'pixel-pet', component: 'AbovePrompt', props: PROPS } as const

type Engine = Parameters<TestBody>[0]
type On = Parameters<TestBody>[1]


// The engine beneath the pet: a session on `model` with `effortLevel` in its settings.
const engine = (on: On, session: { model: string; effortLevel?: string }, env: Record<string, string> = {}) => {
  mock.clock(on)
  mock.env(on, env)
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.model', () => ({ value: session.model }))
  on('settings.read', () => ({ value: session.effortLevel === undefined ? {} : { effortLevel: session.effortLevel } }))
  on('command.register', () => ({ value: { command: 'pet' } }))
  on('command.run', () => ({ text: '' }))
  on('turn.step', async function* (_, e) {
    const answer = 'engine answer'

    return { turnId: e.turnId, index: e.index, answer, toolUses: [], stopReason: 'end_turn', usage: null }
  })
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)

    return <Text>engine</Text>
  })
}

const start = ($: Engine) => $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

const requestOn = async ($: Engine, model: string, effort?: Level, agentId?: string) => {
  const stream = $.turn.step({ turnId: 't', index: 0, model, effort, messageCount: 1, agentId })
  // Read to its end; the pet only looks at the request.
  for (let chunk = await stream.next(); ; chunk = await stream.next()) {
    if (chunk.done === true) {
      return chunk.value
    }
  }
}

const command = ($: Engine, name: string, args = '') =>
  $.command.run({
    command: name,
    args,
    origin: { kind: 'composer' },
    presentation: { isFullscreen: false, columns: 100 },
  })

// The band's text beside the sprite, and how many sprite rows it drew.
const band = async ($: Engine, props: Partial<typeof PROPS> = {}, surface: 'terminal' | 'desktop' = 'terminal') => {
  const mounted = await $.ui.mount({ ...BAND, surface, props: { ...BAND.props, ...props } })
  const title = (await mounted.find({ type: 'Text', text: / · (waiting|done|power|running)/ }))?.text
  const form = (await mounted.find({ type: 'Text', text: / · power / }))?.text
  const sprite = (await mounted.findAll({ type: 'Text' })).filter(
    text => /^[ ▀▄█]+$/.test(text.text) && [16, 24].includes(text.text.length) && text.children.length > 1,
  )
  const engineText = (await mounted.find({ type: 'Text', text: /engine/ }))?.text
  await mounted.unmount()

  return { title, form, spriteRows: sprite.length, engineText }
}

test('the band draws Goku over what lies beneath, and /pet hides him', async ($, on) => {
  engine(on, { model: 'claude-opus-5-5', effortLevel: 'high' })
  await start($)

  for (const surface of ['terminal', 'desktop'] as const) {
    const drawn = await band($, {}, surface)
    expect(drawn.title).toMatch(/^Goku · waiting for you/)
    expect(drawn.form).toBe('Super Saiyan 2 · power 10,000!')
    expect(drawn.spriteRows).toBe(TIERS.large.rows)
    expect(drawn.engineText).toBe('engine')
  }

  expect((await command($, 'pet')).text).toMatch(/Goku is resting/)
  const hidden = await band($)
  expect(hidden.title).toBeUndefined()
  expect(hidden.engineText).toBe('engine')
  expect((await command($, 'pet')).text).toBe('Goku is back!')
})

test('each request of the main conversation sets the fighter and form', async ($, on) => {
  engine(on, { model: 'claude-opus-5-5' })
  await start($)
  // No effort in the settings: base form until a request says otherwise.
  expect((await band($)).form).toMatch(/^Base form/)

  await requestOn($, 'claude-sonnet-5-5', 'xhigh')
  expect((await band($)).title).toMatch(/^Vegeta · /)
  expect((await band($)).form).toMatch(/^Majin · /)

  await requestOn($, 'claude-opus-5-5', 'max')
  expect((await band($)).form).toMatch(/^Ultra Instinct · /)

  // The request goes out and its response comes back untouched.
  expect((await requestOn($, 'claude-opus-5-5', 'max')).answer).toBe('engine answer')

  // A subagent's requests are not the main conversation's.
  await requestOn($, 'claude-haiku-5-5', 'low', 'agent-1')
  expect((await band($)).title).toMatch(/^Goku · /)
  expect((await band($)).form).toMatch(/^Ultra Instinct · /)

  // A model without effort is the kid in base form.
  await requestOn($, 'claude-haiku-5-5')
  expect((await band($)).title).toMatch(/^Gohan · /)
  expect((await band($)).form).toMatch(/^Base form/)
})

test('/model and /effort change it at once, before the next request', async ($, on) => {
  const session = { model: 'claude-opus-5-5', effortLevel: 'medium' }
  engine(on, session)
  await start($)
  expect((await band($)).form).toMatch(/^Super Saiyan · /)

  session.model = 'claude-sonnet-5-5'
  await command($, 'model', 'sonnet')
  expect((await band($)).title).toMatch(/^Vegeta · /)

  await command($, 'effort', 'max')
  expect((await band($)).form).toMatch(/^Ultra Ego · /)

  // The picker (no argument) and `auto` are read back from the settings.
  session.effortLevel = 'low'
  await command($, 'effort')
  expect((await band($)).form).toMatch(/^Base form · /)
  session.effortLevel = 'high'
  await command($, 'effort', 'auto')
  expect((await band($)).form).toMatch(/^Super Saiyan 2 · /)

  // The effort carries across a model switch, as the session's does.
  session.model = 'claude-opus-5-5'
  await command($, 'model', 'opus')
  expect((await band($)).title).toMatch(/^Goku · /)
  expect((await band($)).form).toMatch(/^Super Saiyan 2 · /)
})

test('the band draws the largest fighter it has rows for, and gives way below the head', async ($, on) => {
  engine(on, { model: 'claude-opus-5-5', effortLevel: 'xhigh' })
  await start($)

  expect(tierFor(37)).toBe('large')
  // A tall but narrow band keeps room for the text with the small fighter.
  expect(tierFor(37, 100, 36)).toBe('large')
  expect(tierFor(37, 50, 36)).toBe('medium')
  const narrow = await band($, { maxRows: 14, bodyColumns: 50 })
  expect(narrow.spriteRows).toBe(TIERS.medium.rows)
  // The sprite keeps its width in a narrow band, so its rows never wrap.
  const mounted = await $.ui.mount({ ...BAND, surface: 'terminal', props: { ...PROPS, bodyColumns: 50 } })
  expect((await mounted.findAll({ type: 'Box' })).some(box => box.props.flexShrink === 0)).toBe(true)
  await mounted.unmount()
  for (const [maxRows, tier] of [[10, 'large'], [9, 'medium'], [6, 'medium'], [5, 'head'], [4, 'head']] as const) {
    const drawn = await band($, { maxRows })
    expect({ maxRows, rows: drawn.spriteRows }).toEqual({ maxRows, rows: TIERS[tier].rows })
    expect(drawn.form).toMatch(/^Super Saiyan 3 · /)
  }
  expect(tierFor(3)).toBeNull()

  const giveWay: Partial<typeof PROPS>[] = [{ maxRows: 3 }, { hasSurvey: true }]
  for (const props of giveWay) {
    const yielded = await band($, props)
    expect(yielded.title).toBeUndefined()
    expect(yielded.engineText).toBe('engine')
  }
})

test('the name option names the pet', { options: { name: 'Bơ' } }, async ($, on) => {
  engine(on, { model: 'claude-opus-5-5' })
  await start($)
  expect((await band($)).title).toMatch(/^Bơ · /)
})

test('the character option picks the fighter whatever the model', { options: { character: 'vegeta' } }, async (
  $,
  on,
) => {
  engine(on, { model: 'claude-opus-5-5', effortLevel: 'xhigh' })
  await start($)
  expect((await band($)).title).toMatch(/^Vegeta · /)
  expect((await band($)).form).toMatch(/^Majin · /)
})

test('NO_COLOR draws the pet without colour', async ($, on) => {
  engine(on, { model: 'claude-opus-5-5', effortLevel: 'max' }, { NO_COLOR: '1' })
  await start($)
  const mounted = await $.ui.mount({ ...BAND, surface: 'terminal' })
  const blocks = (await mounted.findAll({ type: 'Text' })).filter(text => /^[ ▀▄█]+$/.test(text.text))
  expect(blocks.length).toBeGreaterThan(0)
  expect(blocks.every(block => block.props.color === undefined && block.props.backgroundColor === undefined)).toBe(true)
  await mounted.unmount()
})
