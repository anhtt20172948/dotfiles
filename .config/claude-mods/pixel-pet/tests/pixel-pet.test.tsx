import { expect, mock, test } from 'claude-code/testing'
import type { TestBody } from 'claude-code/testing'

import { BODIES } from '../hooks/lib/art'
import type { Pose } from '../hooks/lib/art'
import { FRAME_MS, TECHNIQUES, attackMs, chant, milestoneOf, milestoneShout, phaseOf, withAttack } from '../hooks/lib/beam'
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
import { CELL, clashes, renderChoice, sextant } from '../hooks/lib/cells'
import { EXPRESSION_NAMES } from '../hooks/lib/layers'
import { beamPalette } from '../hooks/lib/palette'
import { ALL_COLORS, RENDERS, TIERS, frame, mirror, palette, palmsOf, pixelSize, rows, tierFor } from '../hooks/lib/sprite'
import type { Look, Render, Tier } from '../hooks/lib/sprite'
import type { Attack, Pet } from '../types'

const run = (pet: Pet, events: PetEvent[]) => events.reduce(step, pet)

const ticks = (from: number, count: number, every = 400): PetEvent[] =>
  Array.from({ length: count }, (_, i) => ({ type: 'tick', now: from + (i + 1) * every }))

// The small half-block fighter's width, which the pixel-level checks below draw at.
const WIDTH = pixelSize('medium', 'halfblock').width

// The half-block fighter at a tier (the small one unless named), as the
// pixel-level checks below draw it.
const halfBlock = (fighter: Fighter, seen: Look, tick: number, tier: Tier = 'medium') =>
  frame(fighter, seen, tick, tier, 'halfblock')

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
  const lines = rows(['ko..', 'k.o.'].map(row => row.padEnd(WIDTH, '.')), colors, 'halfblock')

  expect(lines).toHaveLength(1)
  expect(lines[0]?.[0]).toEqual({ text: '█', color: colors.k })
  expect(lines[0]?.[1]).toEqual({ text: '▀▄', color: colors.o })
  expect(lines[0]?.[2]).toEqual({ text: ' '.repeat(WIDTH - 3) })
  expect(rows(['ko'.padEnd(WIDTH, '.'), 'ok'.padEnd(WIDTH, '.')], colors, 'halfblock')[0]?.[0]).toEqual({
    text: '▀',
    color: colors.k,
    backgroundColor: colors.o,
  })
})

test('six pixels make one sextant cell: its glyph lights them, in two colours at most', async () => {
  // The 2x3 masks run through U+1FB00-1FB3B, skipping the two half blocks and the full block.
  expect([0, 1, 21, 22, 42, 62, 63].map(sextant)).toEqual([' ', '\u{1FB00}', '▌', '\u{1FB14}', '▐', '\u{1FB3B}', '█'])
  expect(new Set(Array.from({ length: 64 }, (_, mask) => sextant(mask))).size).toBe(64)

  // Base Goku's outline, gi, skin, eyes and blush.
  const base = palette({ character: 'goku', form: 'base' }, STILL)
  const colors = { k: base.k ?? '', o: base.T ?? '', s: base.s ?? '', e: base.e ?? '', p: base.p ?? '' }
  // One colour over the terminal: the lit pixels in that colour.
  expect(rows(['kk', 'k.', '..'], colors, 'sextant')).toEqual([[{ text: sextant(0b000111), color: colors.k }]])
  // Two colours: the fewer drawn over the other, runs merged.
  expect(rows(['kooo', 'oooo', 'oooo'], colors, 'sextant')).toEqual([
    [{ text: sextant(0b000001), color: colors.k, backgroundColor: colors.o }, { text: '█', color: colors.o }],
  ])
  // Three colours in a cell keep the two that matter most: the eye over the
  // skin, losing the blush beside it.
  const [cell] = rows(['se', 'sp', 'ss'], colors, 'sextant')[0] ?? []
  expect(cell).toEqual({ text: sextant(0b000010), color: colors.e, backgroundColor: colors.s })
  expect(clashes(['se', 'sp', 'ss'], colors, 'sextant')).toEqual([[0, 0]])
})

test('every fighter, form, pose and face fills its tier in either render, and mirrors', async () => {
  for (const render of RENDERS) {
    for (const fighter of FIGHTERS) {
      for (const pose of Object.keys(BODIES) as Pose[]) {
        for (const [tier, cells] of Object.entries(TIERS) as [Tier, (typeof TIERS)[Tier]][]) {
          const face = EXPRESSION_NAMES[(pose.length + fighter.form.length) % EXPRESSION_NAMES.length] ?? 'idle'
          const grid = frame(fighter, { ...STILL, pose, face, aura: 'flare' }, 3, tier, render)
          const size = pixelSize(tier, render)
          expect({ render, tier, height: grid.length }).toEqual({ render, tier, height: size.height })
          expect(grid.every(row => row.length === size.width)).toBe(true)
          // The cells it takes are the same whichever way it is drawn.
          const lines = rows(grid, palette(fighter, STILL), render)
          expect(lines).toHaveLength(cells.rows)
          expect(lines.every(line => [...line.map(segment => segment.text).join('')].length === cells.columns)).toBe(true)
          // Every pixel has a colour.
          const colors = palette(fighter, STILL)
          expect([...grid.join('')].every(pixel => pixel === '.' || colors[pixel] !== undefined)).toBe(true)
          expect(mirror(grid).map(row => [...row].reverse().join(''))).toEqual(grid)
        }
      }
    }
  }
  expect(pixelSize('large', 'sextant')).toEqual({ width: 48, height: 30 })
  expect(pixelSize('large', 'halfblock')).toEqual({ width: 24, height: 20 })
  expect(CELL.sextant).toEqual({ width: 2, height: 3 })
})

test('/config Render picks sextants unless it asks for half blocks', async () => {
  expect(renderChoice('halfblock')).toBe('halfblock')
  expect(renderChoice('sextant')).toBe('sextant')
  expect(renderChoice(undefined)).toBe('sextant')
  expect(renderChoice('quadrant')).toBe('sextant')
})

// The sextant faces: the eyes, brows, mouth, blush and tears of every fighter in
// every mood lie in cells of two colours, so no colour bleeds into the face.
const FACE_CELLS: Record<Tier, { columns: [number, number]; rows: [number, number] }> = {
  large: { columns: [8, 15], rows: [3, 7] },
  medium: { columns: [5, 10], rows: [1, 4] },
  head: { columns: [5, 10], rows: [1, 3] },
}

test('the sextant faces never mix three colours in a cell, whatever the mood', async () => {
  for (const fighter of FIGHTERS) {
    for (const mood of ['idle', 'working', 'happy', 'sad', 'sleep'] as const) {
      for (const tick of [0, 1]) {
        for (const tier of Object.keys(TIERS) as Tier[]) {
          const seen = look(mood, tick)
          const grid = frame(fighter, { ...seen, aura: 'none' }, tick, tier, 'sextant')
          const { columns, rows: down } = FACE_CELLS[tier]
          const onFace = clashes(grid, palette(fighter, seen), 'sextant').filter(
            ([x, y]) => x >= columns[0] && x <= columns[1] && y >= down[0] && y <= down[1],
          )
          expect({ fighter, mood, tier, onFace }).toEqual({ fighter, mood, tier, onFace: [] })
        }
      }
    }
  }
})

test('the sextant aura glows and flickers without adding a third colour to any cell', async () => {
  for (const fighter of FIGHTERS) {
    for (const aura of ['calm', 'flare'] as const) {
      for (const tier of Object.keys(TIERS) as Tier[]) {
        for (let tick = 0; tick < 6; tick += 1) {
          const seen = { ...STILL, pose: aura === 'flare' ? 'power' : 'stand', aura } as const
          const colors = palette(fighter, seen)
          const bare = clashes(frame(fighter, { ...seen, aura: 'none' }, tick, tier, 'sextant'), colors, 'sextant')
          const lit = clashes(frame(fighter, seen, tick, tier, 'sextant'), colors, 'sextant')
          expect({ fighter, aura, tier, tick, added: lit.filter(([x, y]) => !bare.some(([bx, by]) => bx === x && by === y)) }).toEqual(
            { fighter, aura, tier, tick, added: [] },
          )
        }
      }
    }
  }
  const ssj2 = { character: 'goku', form: 'ssj2' } as const
  const flare = { ...STILL, pose: 'power', aura: 'flare' } as const
  const lit = (tick: number) => frame(ssj2, flare, tick, 'large', 'sextant')
  expect(pixels(lit(0), 'i') + pixels(lit(0), 'o')).toBeGreaterThan(0)
  expect(lit(0)).not.toEqual(lit(1))
  expect(Array.from({ length: 23 }, (_, tick) => pixels(lit(tick), 'z')).reduce((a, b) => a + b)).toBeGreaterThan(0)
  expect(pixels(frame({ character: 'goku', form: 'base' }, flare, 0, 'large', 'sextant'), 'o')).toBe(0)
})

// Where each render's large fighter wears its expressions: [left, top, right, bottom].
const EXPRESSION_AREA: Record<Render, [number, number, number, number]> = {
  halfblock: [8, 8, 15, 12],
  sextant: [16, 9, 31, 20],
}

test('Super Saiyan 3 has no brows in any face, either render', async () => {
  const ssj3 = { character: 'goku', form: 'ssj3' } as const
  for (const render of RENDERS) {
    const [left, top, right, bottom] = EXPRESSION_AREA[render]
    for (const face of EXPRESSION_NAMES) {
      const area = frame(ssj3, { ...STILL, face }, 0, 'large', render)
        .slice(top, bottom + 1)
        .map(row => row.slice(left, right + 1))
      expect({ render, face, brows: pixels(area, 'd') }).toEqual({ render, face, brows: 0 })
    }
  }
  // Goku's own brows are there to remove.
  const [left, top, right, bottom] = EXPRESSION_AREA.sextant
  const goku = frame({ character: 'goku', form: 'ssj2' }, { ...STILL, face: 'power' }, 0, 'large', 'sextant')
  expect(pixels(goku.slice(top, bottom + 1).map(row => row.slice(left, right + 1)), 'd')).toBeGreaterThan(0)
})

test('the sextant fighters keep each character and mood', async () => {
  const at = (fighter: Fighter, mood: 'idle' | 'working' | 'happy' | 'sad' | 'sleep', tier: Tier = 'large') =>
    frame(fighter, look(mood, 1), 1, tier, 'sextant')
  const goku = { character: 'goku', form: 'ssj2' } as const
  // Open eyes glint; working bares the teeth; a failure cries; meditating shuts them.
  expect(pixels(at(goku, 'idle'), 'w')).toBe(2)
  expect(pixels(at(goku, 'working'), 't')).toBeGreaterThan(0)
  expect(pixels(at(goku, 'happy'), 'p')).toBeGreaterThan(0)
  expect(pixels(at(goku, 'sad'), 'b')).toBeGreaterThan(0)
  expect(pixels(at(goku, 'sleep'), 'e')).toBe(0)
  // Super Saiyan 3's mane falls to the heels and it has no brows; Majin Vegeta wears the M.
  expect(at({ character: 'goku', form: 'ssj3' }, 'idle')[27]).toMatch(/h/)
  expect(at(goku, 'idle')[27]).not.toMatch(/h/)
  expect(at({ character: 'goku', form: 'ssj3' }, 'idle').slice(9, 12).join('').slice(0)).not.toMatch(/d/)
  expect(pixels(at({ character: 'vegeta', form: 'majin' }, 'idle'), 'M')).toBeGreaterThan(0)
  expect(pixels(at({ character: 'vegeta', form: 'majin' }, 'idle', 'head'), 'M')).toBeGreaterThan(0)
  // Vegeta's brows slant down to the middle even at rest, where Goku's are level.
  const brows = (fighter: Fighter) => at(fighter, 'idle').slice(9, 12).map(row => row.slice(16, 32))
  expect(brows({ character: 'vegeta', form: 'base' })).not.toEqual(brows({ character: 'goku', form: 'base' }))
  // The thumbs up rises beside the face.
  expect(at({ character: 'gohan', form: 'base' }, 'happy')[13]?.[42]).toBe('S')
  // Without colour the eyes are cut out of the silhouette.
  const seen = look('idle', 1)
  const text = rows(at(goku, 'idle'), palette(goku, seen), 'sextant', true).map(line => line.map(segment => segment.text).join(''))
  expect([...(text[5] ?? '')].slice(8, 16).some(glyph => glyph !== '█')).toBe(true)
})

test('base form has black hair and no aura; Super Saiyan turns it gold and glows', async () => {
  const base = { character: 'goku', form: 'base' } as const
  const ssj1 = { character: 'goku', form: 'ssj1' } as const
  expect(palette(base, STILL).h).not.toBe(palette(ssj1, STILL).h)
  expect(pixels(halfBlock(base, { ...STILL, aura: 'flare' }, 0), 'o')).toBe(0)
  expect(pixels(halfBlock(ssj1, { ...STILL, aura: 'calm' }, 0), 'o')).toBeGreaterThan(0)
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
  expect(pixels(halfBlock(ssj1, flare, 0), 'i')).toBeGreaterThan(0)
  expect(pixels(halfBlock(ssj1, flare, 0), 'o')).toBeGreaterThan(0)
  const sparks = (fighter: Fighter) =>
    Array.from({ length: 23 }, (_, tick) => pixels(halfBlock(fighter, flare, tick), 'z')).reduce((a, b) => a + b)
  expect(sparks(ssj1)).toBe(0)
  expect(sparks(ssj2)).toBeGreaterThan(0)
  // The flames rise: the pattern moves between ticks.
  expect(halfBlock(ssj2, flare, 0)).not.toEqual(halfBlock(ssj2, flare, 1))
})

test('Super Saiyan 3 grows long hair and Majin Vegeta wears the M', async () => {
  const ssj3 = halfBlock({ character: 'goku', form: 'ssj3' }, STILL, 0)
  const ssj2 = halfBlock({ character: 'goku', form: 'ssj2' }, STILL, 0)
  expect(ssj3[10]).toMatch(/h/)
  expect(ssj2[10]).not.toMatch(/h/)
  expect(pixels(halfBlock({ character: 'vegeta', form: 'majin' }, STILL, 0), 'M')).toBeGreaterThan(0)
  expect(pixels(halfBlock({ character: 'vegeta', form: 'ssj2' }, STILL, 0), 'M')).toBe(0)
})

test('a failure knocks it out of its form: base hair, no aura, a tear', async () => {
  const fighter = { character: 'goku', form: 'ssj3' } as const
  const knocked = look('sad', 0)
  const grid = halfBlock(fighter, knocked, 0)
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
  expect(halfBlock(goku, look('sleep', 0), 0)[0]).toBe('.'.repeat(WIDTH))
  expect(halfBlock(goku, look('sleep', 0), 0, 'large').slice(0, 2).join('')).not.toMatch(/[^.]/)
  expect(pixels(halfBlock(goku, look('sleep', 0), 0), 'e')).toBe(0)
  expect(pixels(halfBlock(goku, look('sleep', 0), 0), 'c')).toBe(2)
})

test('the large fighter wears each mood on its face', async () => {
  const goku = { character: 'goku', form: 'ssj2' } as const
  const face = (mood: 'idle' | 'working' | 'happy' | 'sad' | 'sleep') => halfBlock(goku, look(mood, 1), 1, 'large')
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
    const gokuBrows = halfBlock({ character: 'goku', form: 'base' }, seen, 1, 'large')[8] ?? ''
    expect(`${gokuBrows.slice(9, 11)} ${gokuBrows.slice(13, 15)}`).toBe('dd dd')
    expect(inner(halfBlock({ character: 'vegeta', form: 'base' }, seen, 1, 'large'))).toBe('dd')
    expect(inner(halfBlock({ character: 'goku', form: 'base' }, seen, 1, 'large'))).not.toContain('d')
  }
  // Super Saiyan 3 has no brows at all.
  expect(halfBlock({ character: 'goku', form: 'ssj3' }, idle, 1, 'large')[8]?.slice(8, 16)).not.toMatch(/d/)
  // Super Saiyan 3's mane falls to the heels; Majin Vegeta wears the M.
  expect(halfBlock({ character: 'goku', form: 'ssj3' }, idle, 1, 'large')[17]).toMatch(/h/)
  expect(halfBlock({ character: 'goku', form: 'ssj2' }, idle, 1, 'large')[17]).not.toMatch(/h/)
  expect(pixels(halfBlock({ character: 'vegeta', form: 'majin' }, idle, 1, 'large'), 'M')).toBe(4)
  // The thumbs up rises beside the face.
  expect(halfBlock({ character: 'gohan', form: 'base' }, look('happy', 0), 0, 'large')[9]?.[20]).toBe('S')
})

test('without colour the fighter is a silhouette, eyes cut out and aura left off', async () => {
  const fighter = { character: 'goku', form: 'ssj2' } as const
  const lit = { ...STILL, aura: 'flare' } as const
  const grid = halfBlock(fighter, lit, 0)
  const lines = rows(grid, palette(fighter, lit), 'halfblock', true)
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
    const eyes = rows(halfBlock(fighter, seen, 1, 'large'), palette(fighter, seen), 'halfblock', true)
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
  expect(caption('working', working, 'goku').text).toMatch(/^running Bash\.+$/)
  expect(caption('working', { ...working, tool: null }, 'goku').text).toMatch(/^powering up\.+$/)

  const happy = run(working, [
    { type: 'toolDone', now: 30, tool: 'Bash', isError: false },
    { type: 'turn', now: 40, isAborted: false, form: 'base', attacks: false },
  ])
  expect(happy).toMatchObject({ mood: 'happy', tool: null, turns: 1 })
  expect(caption('happy', happy, 'goku')).toEqual({ text: 'done!', tone: 'cheer' })

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
  expect(caption('sad', failed, 'goku').text).toBe('Bash failed…')
  expect(stats(failed)).toBe('0 turns · 1 tool · 1 error')

  const aborted = run(INITIAL, [{ type: 'turn', now: 0, isAborted: true, form: 'base', attacks: true }])
  expect(caption(aborted.mood, aborted, 'goku').text).toBe('interrupted…')
})

test('idle it walks within its room and meditates, a prompt wakes it', async () => {
  const walked = run(run(INITIAL, [{ type: 'start', now: 0 }]), ticks(0, 200))
  expect(walked.x).toBeGreaterThanOrEqual(0)
  expect(walked.x).toBeLessThanOrEqual(ROAM)

  const asleep = run(walked, [{ type: 'tick', now: SLEEP_MS + 1 }])
  expect(asleep.mood).toBe('sleep')
  expect(caption('sleep', asleep, 'goku').text).toMatch(/^z/)
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
  const clock = mock.clock(on)
  mock.env(on, env)
  on('turn.complete', () => ({ text: '' }))
  on('prompt.submit', (_, e) => ({ text: e.text }))
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

  return clock
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

// A sprite row's glyphs: half blocks and sextants.
const SPRITE_ROW = /^[ ▀▄█▌▐\u{1FB00}-\u{1FB3B}]+$/u
const HALF_BLOCK_ROW = /^[ ▀▄█]+$/

// The band's text beside the sprite, and the sprite rows it drew.
const band = async ($: Engine, props: Partial<typeof PROPS> = {}, surface: 'terminal' | 'desktop' = 'terminal') => {
  const mounted = await $.ui.mount({ ...BAND, surface, props: { ...BAND.props, ...props } })
  const title = (await mounted.find({ type: 'Text', text: / · (waiting|done|power|running)/ }))?.text
  const form = (await mounted.find({ type: 'Text', text: / · power / }))?.text
  const sprite = (await mounted.findAll({ type: 'Text' })).filter(
    text => SPRITE_ROW.test(text.text) && [16, 24].includes([...text.text].length) && text.children.length > 1,
  )
  const engineText = (await mounted.find({ type: 'Text', text: /engine/ }))?.text
  await mounted.unmount()

  return { title, form, spriteRows: sprite.length, sprite: sprite.map(text => text.text), engineText }
}

// Whether a band's sprite is drawn in sextants or half blocks alone.
const renderOf = (sprite: readonly string[]): Render =>
  sprite.every(row => HALF_BLOCK_ROW.test(row)) ? 'halfblock' : 'sextant'

test('the band draws Goku over what lies beneath, and /pet hides him', async ($, on) => {
  engine(on, { model: 'claude-opus-5-5', effortLevel: 'high' })
  await start($)

  for (const surface of ['terminal', 'desktop'] as const) {
    const drawn = await band($, {}, surface)
    expect(drawn.title).toMatch(/^Goku · waiting for you/)
    expect(drawn.form).toBe('Super Saiyan 2 · power 10,000!')
    expect(drawn.spriteRows).toBe(TIERS.large.rows)
    expect(renderOf(drawn.sprite)).toBe('sextant')
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

test('the render option draws half blocks for a font without sextants', { options: { render: 'halfblock' } }, async (
  $,
  on,
) => {
  engine(on, { model: 'claude-opus-5-5', effortLevel: 'high' })
  await start($)
  for (const maxRows of [14, 6, 4]) {
    const drawn = await band($, { maxRows })
    expect({ maxRows, render: renderOf(drawn.sprite), rows: drawn.spriteRows > 0 }).toEqual({
      maxRows,
      render: 'halfblock',
      rows: true,
    })
  }
})

test('NO_COLOR draws the pet without colour', async ($, on) => {
  engine(on, { model: 'claude-opus-5-5', effortLevel: 'max' }, { NO_COLOR: '1' })
  await start($)
  const mounted = await $.ui.mount({ ...BAND, surface: 'terminal' })
  const blocks = (await mounted.findAll({ type: 'Text' })).filter(text => SPRITE_ROW.test(text.text))
  expect(blocks.length).toBeGreaterThan(0)
  expect(blocks.every(block => block.props.color === undefined && block.props.backgroundColor === undefined)).toBe(true)
  await mounted.unmount()
})

// A finished turn of the main conversation, as the engine reports it.
const TURN_DONE = { answer: 'ok', durationMs: 1, isAborted: false, turnId: 't', reason: 'answer' } as const

const FINISH = { isAborted: false, form: 'base', attacks: true } as const

const at = (elapsed: number, milestone: number | null = null): Attack => ({ elapsed, milestone })

test('a finished turn fires a beam, then gives a thumbs up, then settles', async () => {
  const started = run(INITIAL, [{ type: 'start', now: 0 }])
  const fired = run(started, [{ type: 'turn', now: 1_000, ...FINISH }])
  expect(fired).toMatchObject({ mood: 'attack', turns: 1, attack: at(0) })
  expect(look('attack', 0)).toMatchObject({ pose: 'beam', face: 'power', aura: 'flare' })
  expect(caption('attack', fired, 'goku')).toEqual({ text: 'Ka...', tone: 'beam' })

  // Each frame moves it on; once it has fired, the whole shout shows.
  const firing = run(fired, [{ type: 'frame', now: 2_700 }])
  expect(firing.attack).toEqual(at(1_700))
  expect(phaseOf(at(1_700)).phase).toBe('hold')
  expect(caption('attack', firing, 'goku').text).toBe('Ka... me... ha... me... HA!!')

  // It lasts about two and a half seconds, then the thumbs up; ticks end it too.
  expect(attackMs(at(0))).toBeLessThanOrEqual(3_000)
  const done = run(fired, [{ type: 'frame', now: 1_000 + attackMs(at(0)) }])
  expect(done).toMatchObject({ mood: 'happy', attack: null })
  expect(run(fired, ticks(1_000, Math.ceil(attackMs(at(0)) / 400))).mood).toBe('happy')
  expect(run(done, ticks(done.since, Math.ceil(REACT_MS / 400))).mood).toBe('idle')

  // With Attacks off, or on an interrupted turn, there is no beam.
  expect(run(started, [{ type: 'turn', now: 1_000, ...FINISH, attacks: false }])).toMatchObject({ mood: 'happy', attack: null })
  expect(run(started, [{ type: 'turn', now: 1_000, ...FINISH, isAborted: true }])).toMatchObject({ mood: 'sad', attack: null })
  // A frame or a tick outside a beam changes nothing it should not.
  expect(run(started, [{ type: 'frame', now: 5 }])).toEqual(started)
})

test('a prompt or a tool cancels a beam at once', async () => {
  const fired = run(INITIAL, [{ type: 'turn', now: 0, ...FINISH }])
  for (const event of [{ type: 'prompt', now: 300 }, { type: 'tool', now: 300, tool: 'Bash' }] as const) {
    const cut = run(fired, [event])
    expect({ event: event.type, mood: cut.mood, attack: cut.attack }).toEqual({ event: event.type, mood: 'working', attack: null })
    // A late frame does not bring it back.
    expect(run(cut, [{ type: 'frame', now: 400 }]).mood).toBe('working')
  }
})

test('crossing a power milestone fires a bigger, longer beam that shouts it', async () => {
  expect([0, 8_999, 9_000, 99_999, 100_000, 2_500_000].map(milestoneOf)).toEqual([0, 0, 9_000, 9_000, 100_000, 1_000_000])
  expect(milestoneShout(9_000)).toBe("It's over 9000!!!")
  expect(milestoneShout(1_000_000)).toBe("It's over 1,000,000!!!")

  // Super Saiyan multiplies by 50: 5,000 at the start, 7,500 after a turn,
  // 10,000 after two, which crosses 9,000.
  const ssj1 = { ...FINISH, form: 'ssj1' } as const
  const first = run(INITIAL, [{ type: 'turn', now: 0, ...ssj1 }])
  expect(first.attack).toEqual(at(0))
  const second = run(first, [{ type: 'turn', now: 10_000, ...ssj1 }])
  expect(second.attack).toEqual(at(0, 9_000))
  expect(attackMs(at(0, 9_000))).toBeGreaterThan(attackMs(at(0)))
  // The milestone is reached once: the next turn fires a normal beam.
  expect(run(second, [{ type: 'turn', now: 20_000, ...ssj1 }]).attack).toEqual(at(0))
  // A session that starts past a milestone does not celebrate it on its first turn.
  expect(run(INITIAL, [{ type: 'turn', now: 0, ...FINISH, form: 'ssj2' }]).attack).toEqual(at(0))
  // Raising the effort jumps the power level: Ultra Instinct's 100,000s.
  expect(run(second, [{ type: 'turn', now: 20_000, ...FINISH, form: 'ui' }]).attack).toEqual(at(0, 100_000))
  // With Attacks off the milestone is still marked, so turning them on later
  // does not celebrate an old one.
  const quiet = run(first, [{ type: 'turn', now: 10_000, ...ssj1, attacks: false }])
  expect(quiet.milestone).toBe(9_000)
})

test('each character fires its own technique', async () => {
  expect(TECHNIQUES).toEqual({ goku: 'kamehameha', vegeta: 'finalFlash', gohan: 'masenko' })
  const shouts = (technique: (typeof TECHNIQUES)[keyof typeof TECHNIQUES]) =>
    [...new Set(Array.from({ length: 28 }, (_, i) => chant(technique, at(i * FRAME_MS))))]
  expect(shouts('kamehameha')).toEqual(['Ka...', 'Ka... me...', 'Ka... me... ha...', 'Ka... me... ha... me...', 'Ka... me... ha... me... HA!!'])
  expect(shouts('finalFlash')).toEqual(['Final...', 'Final... FLASH!!'])
  expect(shouts('masenko')).toEqual(['Ma...', 'Ma... sen...', 'Ma... sen... KO!!'])
  // Kamehameha is blue, Final Flash yellow, Masenko gold; each a colour of its own.
  const edge = (technique: (typeof TECHNIQUES)[keyof typeof TECHNIQUES]) => beamPalette(technique).u ?? ''
  const [r, g, b] = (edge('kamehameha').slice(1).match(/../g) ?? []).map(c => parseInt(c, 16))
  expect((b ?? 0) > (r ?? 0) && (b ?? 0) > (g ?? 0)).toBe(true)
  expect(new Set(Object.values(TECHNIQUES).map(edge)).size).toBe(3)
})

test('the beam stays within the columns it is given, two colours a cell, either render', async () => {
  const fighter = { character: 'goku', form: 'ssj2' } as const
  const seen = look('attack', 0)
  const colors = { ...palette(fighter, seen), ...beamPalette('kamehameha') }
  for (const render of RENDERS) {
    for (const tier of ['large', 'medium'] as const) {
      const { width, height } = pixelSize(tier, render)
      const cell = CELL[render]
      const grid = frame(fighter, seen, 0, tier, render)
      for (const milestone of [null, 9_000]) {
        for (const maxColumns of [0, 7, 30]) {
          // Every frame, and the last moment before it gives way.
          const length = attackMs(at(0, milestone))
          const times = [...Array.from({ length: Math.ceil(length / FRAME_MS) }, (_, i) => i * FRAME_MS), length - 1]
          const widths = times.map(time => {
            const drawn = withAttack(grid, { attack: at(time, milestone), spot: palmsOf(tier, render).spot, cell, maxColumns })
            const key = { render, tier, milestone, maxColumns, at: time }
            expect({ ...key, height: drawn.length, isEven: drawn.every(row => row.length === drawn[0]?.length) }).toEqual({
              ...key,
              height,
              isEven: true,
            })
            // The beam out past the fighter and its ball never mixes three colours in a cell.
            const ball = Math.ceil(10 / cell.width)
            const beyond = clashes(drawn, colors, render).filter(([x]) => x >= TIERS[tier].columns + ball)
            expect({ ...key, beyond }).toEqual({ ...key, beyond: [] })

            return (drawn[0]?.length ?? 0) / cell.width
          })
          const key = { render, tier, milestone, maxColumns }
          // It charges in the palms, reaches the limit and no further, and is gone at the end.
          expect({ ...key, first: widths[0], widest: Math.max(...widths), last: widths.at(-1) }).toEqual({
            ...key,
            first: width / cell.width,
            widest: width / cell.width + maxColumns,
            last: width / cell.width,
          })
        }
      }
    }
  }
})

// The band while a beam may be firing: its title, the widest sprite row, and
// the line under the form.
const beamBand = async ($: Engine, props: Partial<typeof PROPS> = {}) => {
  const mounted = await $.ui.mount({ ...BAND, surface: 'terminal', props: { ...BAND.props, ...props } })
  const texts = await mounted.findAll({ type: 'Text' })
  const title = texts.find(text => /^(Goku|Vegeta|Gohan) · /.test(text.text))?.text
  const sprite = texts.filter(text => SPRITE_ROW.test(text.text))
  const width = Math.max(0, ...sprite.map(text => [...text.text].length))
  const shout = texts.find(text => /^It's over/.test(text.text))?.text
  const isColored = sprite.some(text => text.props.color !== undefined || text.props.backgroundColor !== undefined)
  await mounted.unmount()

  return { title, width, shout, isColored }
}

test('a finished turn fires across the band, pushing the text right, until a prompt', async ($, on) => {
  const clock = engine(on, { model: 'claude-opus-5-5', effortLevel: 'high' })
  await start($)
  await $.turn.complete(TURN_DONE)
  const charging = await beamBand($)
  expect(charging.title).toBe('Goku · Ka...')
  expect(charging.width).toBeLessThanOrEqual(TIERS.large.columns + 2)

  // The frames run on their own: the beam is fired and the text pushed right,
  // as far as the band leaves room for the text (100 - 24 - 2 - 36 columns).
  await clock.advance(1_800)
  const fired = await beamBand($)
  expect(fired.title).toBe('Goku · Ka... me... ha... me... HA!!')
  expect(fired.width).toBe(TIERS.large.columns + 38)
  // A wider band fires it no further than the large tier's 40 columns.
  expect((await beamBand($, { bodyColumns: 200 })).width).toBe(TIERS.large.columns + 40)
  // A band with no room beside the text fires no beam; the head alone none either.
  expect((await beamBand($, { bodyColumns: 62 })).width).toBe(TIERS.large.columns)
  const head = await beamBand($, { maxRows: 4 })
  expect({ title: head.title, width: head.width }).toEqual({ title: 'Goku · Ka... me... ha... me... HA!!', width: TIERS.head.columns })

  // A prompt cuts it short, and the text is back at once.
  await $.prompt.submit({ text: 'next', wait: false, origin: { kind: 'composer' } })
  await clock.settle()
  const cut = await beamBand($, { isWorking: true })
  expect(cut.title).toMatch(/^Goku · powering up/)
  expect(cut.width).toBe(TIERS.large.columns)

  // Left alone it ends in a thumbs up.
  await $.turn.complete(TURN_DONE)
  await clock.advance(3_000)
  expect((await beamBand($)).title).toBe('Goku · done!')
})

test('crossing 9000 shouts it beside the bigger beam', async ($, on) => {
  const clock = engine(on, { model: 'claude-opus-5-5', effortLevel: 'medium' })
  await start($)
  // Super Saiyan: 5,000, then 7,500, then 10,000.
  await $.turn.complete(TURN_DONE)
  await clock.advance(4_000)
  expect((await beamBand($)).shout).toBeUndefined()
  await $.turn.complete(TURN_DONE)
  await clock.advance(2_000)
  const big = await beamBand($)
  expect(big.shout).toBe("It's over 9000!!!")
  expect(big.title).toBe('Goku · Ka... me... ha... me... HA!!')
})

test('Vegeta fires Final Flash and Gohan Masenko', { options: { character: 'vegeta' } }, async ($, on) => {
  const clock = engine(on, { model: 'claude-haiku-5-5' })
  await start($)
  await $.turn.complete(TURN_DONE)
  await clock.advance(1_800)
  expect((await beamBand($)).title).toBe('Vegeta · Final... FLASH!!')
})

test('Gohan fires Masenko', async ($, on) => {
  const clock = engine(on, { model: 'claude-haiku-5-5' })
  await start($)
  await $.turn.complete(TURN_DONE)
  await clock.advance(1_800)
  expect((await beamBand($)).title).toBe('Gohan · Ma... sen... KO!!')
})

test('the Attacks option off keeps the plain thumbs up', { options: { attacks: false } }, async ($, on) => {
  const clock = engine(on, { model: 'claude-opus-5-5' })
  await start($)
  await $.turn.complete(TURN_DONE)
  const drawn = await beamBand($)
  expect(drawn.title).toBe('Goku · done!')
  expect(drawn.width).toBe(TIERS.large.columns)
  await clock.advance(1_800)
  expect((await beamBand($)).width).toBe(TIERS.large.columns)
})

test('the beam is drawn in half blocks, and without colour under NO_COLOR', { options: { render: 'halfblock' } }, async (
  $,
  on,
) => {
  const clock = engine(on, { model: 'claude-opus-5-5', effortLevel: 'high' }, { NO_COLOR: '1' })
  await start($)
  await $.turn.complete(TURN_DONE)
  await clock.advance(1_800)
  const fired = await beamBand($)
  expect(fired.width).toBe(TIERS.large.columns + 38)
  expect(fired.isColored).toBe(false)
  const mounted = await $.ui.mount({ ...BAND, surface: 'terminal' })
  const sprite = (await mounted.findAll({ type: 'Text' })).filter(text => SPRITE_ROW.test(text.text))
  expect(sprite.every(text => HALF_BLOCK_ROW.test(text.text))).toBe(true)
  await mounted.unmount()
})
