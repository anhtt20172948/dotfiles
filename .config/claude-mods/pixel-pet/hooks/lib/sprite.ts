// Pixel art drawn with half blocks: one text row holds two pixel rows, the
// upper pixel as the glyph's colour and the lower as its background.

import { BODIES, HEADS, HEAD_ROWS, MOUTH, SIZE, TEAR, THUMB } from './art'
import type { Head, Pose } from './art'
import {
  EXPRESSIONS,
  EXPRESSION_ORIGIN,
  FACE,
  HAIR_FRONT_ROW,
  LARGE,
  LARGE_BODIES,
  LARGE_HAIR,
  LARGE_HEAD_ROWS,
  LARGE_THUMB,
  SCOWL,
} from './art-large'
import type { Expression } from './art-large'
import type { Character, Fighter, Form } from './fighter'
import { hasAura, hasSparks, paletteOf } from './palette'
import type { Palette } from './palette'

export type { Palette } from './palette'
export { ALL_COLORS, NAME_COLORS, formColor } from './palette'

export type Segment = { text: string; color?: string; backgroundColor?: string }

export type Aura = 'none' | 'calm' | 'flare'

export type Look = {
  pose: Pose
  step: 0 | 1
  // The large tier's face for the mood; the smaller tiers read the flags below.
  face: Expression
  isEyesClosed: boolean
  hasMouth: boolean
  hasTear: boolean
  // Knocked out of the form: base hair, no aura.
  isPoweredDown: boolean
  aura: Aura
}

// How much of the fighter a band has room for: the large, detailed fighter, the
// small one, or the small one's head alone.
export type Tier = 'large' | 'medium' | 'head'

// Each tier's size in pixels and the band rows it takes (two pixel rows a row).
export const TIERS: Record<Tier, { width: number; height: number; rows: number }> = {
  large: { ...LARGE, rows: LARGE.height / 2 },
  medium: { ...SIZE, rows: SIZE.height / 2 },
  head: { width: SIZE.width, height: HEAD_ROWS, rows: HEAD_ROWS / 2 },
}

// The largest tier a band of `rows` fits, or none. The large fighter also needs
// `columns` wide enough to keep `textColumns` beside it; a narrow band draws the
// small one, whose text has always had to squeeze.
export const tierFor = (rows: number, columns = Infinity, textColumns = 0): Tier | null => {
  if (rows >= TIERS.large.rows && columns >= TIERS.large.width + textColumns) {
    return 'large'
  }

  return rows >= TIERS.medium.rows ? 'medium' : rows >= TIERS.head.rows ? 'head' : null
}

const shownForm = (fighter: Fighter, look: Look): Form => (look.isPoweredDown ? 'base' : fighter.form)

export const palette = (fighter: Fighter, look: Look): Palette => paletteOf(fighter, shownForm(fighter, look))

const HEAD_OF: Record<Character, (form: Form) => Head> = {
  goku: form => (form === 'ssj1' || form === 'ssj2' ? 'gokuSuper' : form === 'ssj3' ? 'gokuSsj3' : 'goku'),
  vegeta: form => (form === 'majin' ? 'vegetaMajin' : 'vegeta'),
  gohan: form => (form === 'ssj1' || form === 'ssj2' || form === 'beast' ? 'gohanSuper' : 'gohan'),
}

type Pixel = readonly [number, number, string]

const blank = (width: number, height: number) => Array.from({ length: height }, () => '.'.repeat(width))

// The upper drawing wins wherever it is not transparent.
const over = (under: readonly string[], upper: readonly string[]) =>
  under.map((row, y) =>
    [...row].map((value, x) => (upper[y]?.[x] === undefined || upper[y]?.[x] === '.' ? value : upper[y]?.[x])).join(''),
  )

const put = (grid: readonly string[], pixels: readonly Pixel[]) =>
  grid.map((row, y) =>
    [...row].map((value, x) => pixels.find(([px, py]) => px === x && py === y)?.[2] ?? value).join(''),
  )

// Rows moved down by `by`, the top filled with nothing.
const lowered = (grid: readonly string[], by: number) =>
  by === 0 ? [...grid] : [...blank(grid[0]?.length ?? 0, by), ...grid.slice(0, grid.length - by)]

// A drawing placed at row `top` of a blank grid of `height` rows.
const placed = (rows: readonly string[], top: number, width: number, height: number) =>
  blank(width, height).map((row, y) => rows[y - top] ?? row)

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

// The aura hugs the fighter. Calm, it glows a pixel deep around the body, from
// row `calmFrom` down; flaring, it wraps the whole fighter two deep and its gaps
// rise with every tick, like flames. Sparks crackle where the form has them.
const withAura = (grid: readonly string[], aura: Aura, tick: number, sparks: boolean, calmFrom: number): string[] => {
  if (aura === 'none') {
    return [...grid]
  }
  const reach = aura === 'flare' ? 2 : 1

  return grid.map((row, y) =>
    [...row]
      .map((value, x) => {
        if (value !== '.' || (aura === 'calm' && y < calmFrom)) {
          return value
        }
        const d = nearness(grid, x, y, reach)
        if (d === 0) {
          return value
        }
        if (sparks && (x * 7 + y * 13 + tick * 11) % 23 === 0) {
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

// The small fighter: 16x12, or its head alone (16x8).
const smallFrame = (fighter: Fighter, form: Form, look: Look, isHeadOnly: boolean): string[] => {
  const head = HEADS[HEAD_OF[fighter.character](form)]
  const shift = look.pose === 'meditate' && !isHeadOnly ? 1 : 0
  const body = BODIES[look.pose][look.step % BODIES[look.pose].length] ?? []
  const dressed = over(lowered(head, shift), placed(body, SIZE.height - body.length, SIZE.width, SIZE.height))
  const eyed = look.isEyesClosed ? dressed.map(row => row.replaceAll('e', 'c')) : dressed
  const at = ([x, y]: readonly [number, number], pixel: string): Pixel => [x, y + shift, pixel]
  const details: Pixel[] = [
    ...(look.hasMouth ? MOUTH.map(point => at(point, 'm')) : []),
    ...(look.hasTear ? [at(TEAR, 'b')] : []),
    ...(look.pose === 'thumbs' ? THUMB.map(([x, y]): Pixel => [x, y, 'S']) : []),
  ]
  const drawn = put(eyed, details)

  return isHeadOnly ? drawn.slice(0, HEAD_ROWS) : drawn
}

// The Majin mark: a red M hanging from the widow's peak, above the brows.
const MAJIN_MARK: readonly Pixel[] = [
  [10, 7, 'M'],
  [13, 7, 'M'],
  [11, 8, 'M'],
  [12, 8, 'M'],
]

// The mood's face for a character: Super Saiyan 3 has no brows, and Vegeta's
// brows scowl unless the mood draws its own.
const expressionOf = (head: Head, face: Expression): string[] => {
  const drawn = EXPRESSIONS[face]
  const scowling = head.startsWith('vegeta') && (face === 'idle' || face === 'blink' || face === 'calm')
  // The scowl replaces the brow row and slants into the row below it.
  const scowl = (row: string, y: number) => (y === 0 ? (SCOWL[0] ?? row) : (over([row], [SCOWL[y] ?? ''])[0] ?? row))
  const browed = scowling ? drawn.map(scowl) : [...drawn]

  return head === 'gokuSsj3' ? browed.map(row => row.replaceAll('d', '.')) : browed
}

// The large fighter, 24x20: hair behind, face, body, bangs and the mood's face
// over them.
const largeFrame = (fighter: Fighter, form: Form, look: Look): string[] => {
  const { width, height } = LARGE
  const head = HEAD_OF[fighter.character](form)
  const hair = LARGE_HAIR[head]
  const back = hair.map((row, y) => (y > HAIR_FRONT_ROW ? row : '.'.repeat(width)))
  const front = hair.map((row, y) => (y <= HAIR_FRONT_ROW ? row : '.'.repeat(width)))
  const expression = expressionOf(head, look.face).map(row => '.'.repeat(EXPRESSION_ORIGIN.x) + row)
  const faced = over(over(FACE, front), placed(expression, EXPRESSION_ORIGIN.y, width, height))
  const marked = head === 'vegetaMajin' ? put(faced, MAJIN_MARK) : faced
  const shift = look.pose === 'meditate' ? 2 : 0
  const body = LARGE_BODIES[look.pose][look.step % LARGE_BODIES[look.pose].length] ?? []
  const bodyTop = look.pose === 'meditate' ? height - body.length : LARGE_HEAD_ROWS
  const drawn = over(over(lowered(back, shift), placed(body, bodyTop, width, height)), lowered(marked, shift))

  return look.pose === 'thumbs' ? put(drawn, LARGE_THUMB) : drawn
}

// The fighter in one pose at one tier, as palette keys, with its aura.
export const frame = (fighter: Fighter, look: Look, tick: number, tier: Tier = 'medium'): string[] => {
  const form = shownForm(fighter, look)
  const grid = tier === 'large' ? largeFrame(fighter, form, look) : smallFrame(fighter, form, look, tier === 'head')
  const calmFrom = tier === 'large' ? LARGE_HEAD_ROWS - 4 : HEAD_ROWS - 2

  return withAura(grid, hasAura(form) ? look.aura : 'none', tick, hasSparks(form), calmFrom)
}

export const mirror = (grid: readonly string[]) => grid.map(row => [...row].reverse().join(''))

// Without colour the fighter is a silhouette: its eyes, mouth and tears are cut
// out of it and the aura is left off.
const MONOCHROME_HOLES = new Set(['e', 'c', 'l', 'w', 'm', 'n', 't', 'b', 'o', 'i', 'z'])

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
