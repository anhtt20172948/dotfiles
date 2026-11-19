// Pixel art drawn with half blocks: one text row holds two pixel rows, the
// upper pixel as the glyph's colour and the lower as its background.

import { BODIES, HEADS, HEAD_ROWS, MOUTH, SIZE, TEAR, THUMB } from './art'
import type { Head, Pose } from './art'
import type { Character, Fighter, Form } from './fighter'

export type Segment = { text: string; color?: string; backgroundColor?: string }

export type Aura = 'none' | 'calm' | 'flare'

export type Look = {
  pose: Pose
  step: 0 | 1
  isEyesClosed: boolean
  hasMouth: boolean
  hasTear: boolean
  // Knocked out of the form: base hair, no aura.
  isPoweredDown: boolean
  aura: Aura
}

export const WIDTH = SIZE.width

// Text rows the whole fighter takes, and the head alone.
export const FULL_ROWS = SIZE.height / 2
export const HEAD_ONLY_ROWS = HEAD_ROWS / 2

export type Palette = Record<string, string>

// Every channel is 00, 4c, 7f, af, d7 or ff (or the colour is a grey): each sits
// nearest the 256-colour cube level it quantizes to, so Claude Code inside tmux,
// which drops to 256 colours, draws nearly the same fighter as a truecolor terminal.
const SKIN = '#ffd7af'
const BLUE = '#004caf'
const WHITE = '#ffffff'

const COMMON: Palette = {
  k: '#3a3a3a', // outline
  c: '#af7f4c', // closed eyes, lighter than open ones
  s: SKIN,
  m: '#7f0000', // mouth
  b: '#4cafff', // tear
  M: '#d70000', // Majin mark
}

const BLACK_HAIR = { d: '#00004c', h: '#4c4c7f', H: '#7f7faf' }
const GOLD_HAIR = { d: '#d77f00', h: '#ffd700', H: '#ffffaf' }
const DARK_EYES = '#1c1c1c'
const TEAL_EYES = '#007f7f'
const SPARK = '#7fd7ff'

type FormLook = { hair: { d: string; h: string; H: string }; eyes: string; aura?: { o: string; i: string; z?: string } }

const FORM_LOOKS: Record<Form, FormLook> = {
  base: { hair: BLACK_HAIR, eyes: DARK_EYES },
  ssj1: { hair: GOLD_HAIR, eyes: TEAL_EYES, aura: { o: '#ffffaf', i: '#ffd74c' } },
  ssj2: { hair: GOLD_HAIR, eyes: TEAL_EYES, aura: { o: '#ffffaf', i: '#ffd74c', z: SPARK } },
  ssj3: { hair: GOLD_HAIR, eyes: TEAL_EYES, aura: { o: '#ffd74c', i: '#ffaf00', z: SPARK } },
  majin: { hair: GOLD_HAIR, eyes: TEAL_EYES, aura: { o: '#ffd74c', i: '#ffaf00', z: SPARK } },
  ui: { hair: { d: '#7f7faf', h: '#d0d0d0', H: WHITE }, eyes: '#4c4c7f', aura: { o: '#afd7ff', i: '#7fafff' } },
  ego: { hair: { d: '#4c007f', h: '#7f4cd7', H: '#d7afff' }, eyes: '#7f00af', aura: { o: '#d7afff', i: '#af4cd7' } },
  ultimate: { hair: BLACK_HAIR, eyes: DARK_EYES, aura: { o: '#d0d0d0', i: WHITE } },
  beast: { hair: { d: '#808080', h: '#dadada', H: WHITE }, eyes: '#d70000', aura: { o: '#ff7faf', i: '#d7004c' } },
}

const OUTFITS: Record<Character, Palette> = {
  // Orange gi over a blue undershirt, belt, wristbands and boots.
  goku: { T: '#ff7f00', A: BLUE, R: BLUE, S: SKIN, P: '#ff7f00', F: BLUE },
  // White armour over a blue suit, white gloves and boots.
  vegeta: { T: WHITE, A: BLUE, R: BLUE, S: WHITE, P: BLUE, F: WHITE },
  // A purple gi with a red sash.
  gohan: { T: '#7f4caf', A: '#af0000', R: '#af0000', S: SKIN, P: '#7f4caf', F: BLUE },
}

// The name beside the pet, in each character's colour.
export const NAME_COLORS: Record<Character, string> = { goku: '#ff7f00', vegeta: '#4c7fff', gohan: '#af7fd7' }

// Every colour the pet draws with, for checks.
export const ALL_COLORS: readonly string[] = [
  ...Object.values(COMMON),
  ...Object.values(FORM_LOOKS).flatMap(look => [
    ...Object.values(look.hair),
    look.eyes,
    ...Object.values(look.aura ?? {}),
  ]),
  ...Object.values(OUTFITS).flatMap(outfit => Object.values(outfit)),
  ...Object.values(NAME_COLORS),
]

// The form's name in its aura's colour; the base form has none.
export const formColor = (form: Form): string | undefined => FORM_LOOKS[form].aura?.i

const shownForm = (fighter: Fighter, look: Look): Form => (look.isPoweredDown ? 'base' : fighter.form)

export const palette = (fighter: Fighter, look: Look): Palette => {
  const form = FORM_LOOKS[shownForm(fighter, look)]

  return { ...COMMON, ...OUTFITS[fighter.character], ...form.hair, e: form.eyes, ...form.aura }
}

const HEAD_OF: Record<Character, (form: Form) => Head> = {
  goku: form => (form === 'ssj1' || form === 'ssj2' ? 'gokuSuper' : form === 'ssj3' ? 'gokuSsj3' : 'goku'),
  vegeta: form => (form === 'majin' ? 'vegetaMajin' : 'vegeta'),
  gohan: form => (form === 'ssj1' || form === 'ssj2' || form === 'beast' ? 'gohanSuper' : 'gohan'),
}

const EMPTY = '.'.repeat(WIDTH)

const put = (grid: readonly string[], pixels: readonly (readonly [number, number])[], pixel: string) =>
  grid.map((row, y) =>
    [...row].map((value, x) => (pixels.some(([px, py]) => px === x && py === y) ? pixel : value)).join(''),
  )

// The upper drawing wins wherever it is not transparent.
const over = (under: string, upper: string) =>
  [...under].map((value, x) => (upper[x] === undefined || upper[x] === '.' ? value : upper[x])).join('')

const isSolid = (grid: readonly string[], x: number, y: number) => {
  const value = grid[y]?.[x]

  return value !== undefined && value !== '.'
}

// How near the closest solid pixel is, up to `reach`; 0 when none is.
const nearness = (grid: readonly string[], x: number, y: number, reach: number) => {
  for (let d = 1; d <= reach; d += 1) {
    for (let dy = -d; dy <= d; dy += 1) {
      for (let dx = -d; dx <= d; dx += 1) {
        if (isSolid(grid, x + dx, y + dy)) {
          return d
        }
      }
    }
  }

  return 0
}

// A calm aura glows around the body alone, from this pixel row down.
const CALM_FROM_ROW = 6

// The aura hugs the fighter. Calm, it glows a pixel deep around the body;
// flaring, it wraps the whole fighter two deep and its gaps rise with every
// tick, like flames. Sparks crackle where the form has them.
const withAura = (grid: readonly string[], aura: Aura, tick: number, hasSparks: boolean): string[] => {
  if (aura === 'none') {
    return [...grid]
  }
  const reach = aura === 'flare' ? 2 : 1

  return grid.map((row, y) =>
    [...row]
      .map((value, x) => {
        if (value !== '.' || (aura === 'calm' && y < CALM_FROM_ROW)) {
          return value
        }
        const d = nearness(grid, x, y, reach)
        if (d === 0) {
          return value
        }
        if (hasSparks && (x * 7 + y * 13 + tick * 11) % 23 === 0) {
          return 'z'
        }
        const isGap =
          aura === 'flare' ? (y + tick + ((x * 7) % 3)) % 3 === 0 : (x + y + Math.floor(tick / 2)) % 4 === 0
        if (isGap) {
          return value
        }

        return aura === 'flare' && d === 1 ? 'i' : 'o'
      })
      .join(''),
  )
}

// The fighter in one pose: head, body, face details and aura, as palette keys.
// Compact keeps the head alone, for a band too short for the whole fighter.
export const frame = (fighter: Fighter, look: Look, tick: number, isCompact = false): string[] => {
  const form = shownForm(fighter, look)
  const head = HEADS[HEAD_OF[fighter.character](form)]
  const shift = look.pose === 'meditate' && !isCompact ? 1 : 0
  const lowered = shift === 0 ? [...head] : [EMPTY, ...head.slice(0, SIZE.height - 1)]
  const body = BODIES[look.pose][look.step % BODIES[look.pose].length] ?? []
  const top = SIZE.height - body.length
  const dressed = lowered.map((row, y) => (y >= top ? over(row, body[y - top] ?? EMPTY) : row))
  const eyed = look.isEyesClosed ? dressed.map(row => row.replaceAll('e', 'c')) : dressed
  const at = (pixels: readonly (readonly [number, number])[]) => pixels.map(([x, y]) => [x, y + shift] as const)
  const mouthed = look.hasMouth ? put(eyed, at(MOUTH), 'm') : eyed
  const teared = look.hasTear ? put(mouthed, at([TEAR]), 'b') : mouthed
  const thumbed = look.pose === 'thumbs' ? put(teared, THUMB, 'S') : teared
  const cropped = isCompact ? thumbed.slice(0, HEAD_ROWS) : thumbed
  const aura = FORM_LOOKS[form].aura

  return withAura(cropped, aura === undefined ? 'none' : look.aura, tick, aura?.z !== undefined)
}

export const mirror = (grid: readonly string[]) => grid.map(row => [...row].reverse().join(''))

// Without colour the fighter is a silhouette: its eyes, mouth and tear are cut
// out of it and the aura is left off.
const MONOCHROME_HOLES = new Set(['e', 'm', 'b', 'o', 'i', 'z'])

const cell = (top: string, bottom: string, colors: Palette, isMonochrome: boolean): Segment => {
  const paint = (pixel: string) => (isMonochrome ? {} : { color: colors[pixel] })
  if (top === '.' && bottom === '.') {
    return { text: ' ' }
  }
  if (bottom === '.') {
    return { text: '▀', ...paint(top) }
  }
  if (top === '.') {
    return { text: '▄', ...paint(bottom) }
  }
  if (isMonochrome || colors[top] === colors[bottom]) {
    return { text: '█', ...paint(top) }
  }

  return { text: '▀', color: colors[top], backgroundColor: colors[bottom] }
}

const isSameStyle = (a: Segment, b: Segment) => a.color === b.color && a.backgroundColor === b.backgroundColor

// Each text row as runs of one style, so a row costs a few elements, not one per pixel.
export const rows = (grid: readonly string[], colors: Palette, isMonochrome = false): Segment[][] => {
  const pixel = (value: string | undefined) =>
    value === undefined || (isMonochrome && MONOCHROME_HOLES.has(value)) ? '.' : value
  const width = grid[0]?.length ?? 0
  const lines: Segment[][] = []
  for (let y = 0; y < grid.length; y += 2) {
    const line: Segment[] = []
    for (let x = 0; x < width; x += 1) {
      const next = cell(pixel(grid[y]?.[x]), pixel(grid[y + 1]?.[x]), colors, isMonochrome)
      const last = line.at(-1)
      if (last !== undefined && isSameStyle(last, next)) {
        line[line.length - 1] = { ...last, text: last.text + next.text }
      } else {
        line.push(next)
      }
    }
    lines.push(line)
  }

  return lines
}
