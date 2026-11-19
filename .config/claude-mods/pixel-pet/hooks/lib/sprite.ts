// The fighter as a grid of palette keys, one per pixel, for cells.ts to draw.
// Sextants draw a finer fighter (2x3 pixels a cell) than half blocks (1x2) in
// the same cells.

import { BODIES, HEADS, HEAD_ROWS, MOUTH, PALMS, SIZE, TEAR, THUMB } from './art'
import type { Head, Pose } from './art'
import { HALFBLOCK_LARGE } from './art-large'
import { SEXTANT_LARGE } from './art-sextant-large'
import { SEXTANT_SMALL } from './art-sextant'
import type { Palms } from './beam'
import { CELL } from './cells'
import type { Render } from './cells'
import type { Character, Fighter, Form } from './fighter'
import { layered, lowered, over, placed, put } from './layers'
import type { Expression, LayeredArt, Pixel } from './layers'
import { hasAura, hasSparks, paletteOf } from './palette'
import type { Palette } from './palette'

export type { Palette } from './palette'
export { ALL_COLORS, NAME_COLORS, formColor } from './palette'
export { RENDERS, renderChoice, rows } from './cells'
export type { Render, Segment } from './cells'

export type Aura = 'none' | 'calm' | 'flare'

export type Look = {
  pose: Pose
  step: 0 | 1
  // The layered fighters' face for the mood; the small half-block one reads the flags below.
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

// The text cells each tier takes, whichever way it is drawn.
export const TIERS: Record<Tier, { columns: number; rows: number }> = {
  large: { columns: 24, rows: 10 },
  medium: { columns: 16, rows: 6 },
  head: { columns: 16, rows: 4 },
}

// Each tier's size in pixels.
export const pixelSize = (tier: Tier, render: Render) => ({
  width: TIERS[tier].columns * CELL[render].width,
  height: TIERS[tier].rows * CELL[render].height,
})

// The largest tier a band of `rows` fits, or none. The large fighter also needs
// `columns` wide enough to keep `textColumns` beside it; a narrow band draws the
// small one, whose text has always had to squeeze.
export const tierFor = (rows: number, columns = Infinity, textColumns = 0): Tier | null => {
  if (rows >= TIERS.large.rows && columns >= TIERS.large.columns + textColumns) {
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
const halfBlockAura = (grid: readonly string[], aura: Aura, tick: number, sparks: boolean, calmFrom: number) => {
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

// How many steps of `across` columns and `down` rows each pixel lies from the
// fighter, up to `reach`; 0 beyond it, or on the fighter.
const depths = (grid: readonly string[], reach: number, across: number, down: number): number[][] => {
  const grow = (inside: readonly (readonly boolean[])[]) =>
    inside.map((row, y) =>
      row.map((_, x) =>
        Array.from({ length: 2 * down + 1 }, (__, dy) => dy - down).some(dy =>
          Array.from({ length: 2 * across + 1 }, (___, dx) => dx - across).some(dx => inside[y + dy]?.[x + dx] === true),
        ),
      ),
    )
  const solid = grid.map((row, y) => [...row].map((_, x) => isSolid(grid, x, y)))
  const rings = Array.from({ length: reach }).reduce<boolean[][][]>(
    reached => [...reached, grow(reached.at(-1) ?? solid)],
    [],
  )

  return solid.map((row, y) =>
    row.map((isOn, x) => (isOn ? 0 : rings.findIndex(ring => ring[y]?.[x] === true) + 1)),
  )
}

// Where the aura leaves a gap. Flaring, each column of cells flickers in its
// own phase and the gaps climb two pixel rows a tick, like flames; calm, whole
// cells blink slowly.
const isAuraGap = (aura: Aura, tick: number, x: number, y: number) => {
  const { width: across, height: down } = CELL.sextant

  return aura === 'flare'
    ? (y + 2 * tick + ((Math.floor(x / across) * 5) % 6)) % 6 >= 4
    : (Math.floor(x / across) + Math.floor(y / down) + Math.floor(tick / 2)) % 4 === 0
}

type AuraScene = { grid: readonly string[]; depth: number[][]; colors: Palette; aura: Aura; tick: number; sparks: boolean; calmFrom: number }

// The aura's pixels in the sextant cell at column `cellX`, row `cellY`. A cell
// beside the fighter glows in one colour or not at all (not at all where the
// fighter shows two colours there), a cell of aura alone flickers in one
// colour, and a spark is a zigzag of its own: two colours a cell either way.
const cellAura = (scene: AuraScene, cellX: number, cellY: number): Pixel[] => {
  const { grid, depth, colors, aura, tick, sparks, calmFrom } = scene
  const { width: across, height: down } = CELL.sextant
  const at = Array.from({ length: across * down }, (_, i): [number, number] => [
    cellX * across + (i % across),
    cellY * down + Math.floor(i / across),
  ])
  const body = new Set(at.map(([x, y]) => grid[y]?.[x] ?? '.').filter(key => key !== '.').map(key => colors[key] ?? key))
  const open = at.filter(([x, y]) => grid[y]?.[x] === '.' && (aura === 'flare' || y >= calmFrom))
  const near = open.map(([x, y]) => depth[y]?.[x] ?? 0).filter(d => d > 0)
  if (near.length === 0 || body.size > 1) {
    return []
  }
  if (sparks && body.size === 0 && (cellX * 7 + cellY * 13 + tick * 11) % 23 === 0) {
    return open.map(([x, y]): Pixel => [x, y, (x + y) % 2 === 0 ? 'z' : '.'])
  }
  const color = aura === 'flare' && Math.min(...near) === 1 ? 'i' : 'o'
  if (body.size === 1) {
    const [left, top] = at[0] ?? [0, 0]

    return isAuraGap(aura, tick, left, top) ? [] : open.map(([x, y]): Pixel => [x, y, color])
  }

  return open
    .filter(([x, y]) => (depth[y]?.[x] ?? 0) > 0 && !isAuraGap(aura, tick, x, y))
    .map(([x, y]): Pixel => [x, y, color])
}

const sextantAura = (scene: AuraScene) => {
  const { width: across, height: down } = CELL.sextant
  const cells = Array.from({ length: Math.ceil(scene.grid.length / down) }, (_, cellY) =>
    Array.from({ length: Math.ceil((scene.grid[0]?.length ?? 0) / across) }, (__, cellX) => cellAura(scene, cellX, cellY)),
  )

  return put(scene.grid, cells.flat(2))
}

const withAura = (render: Render, scene: Omit<AuraScene, 'depth'>) => {
  const { grid, aura, tick, sparks, calmFrom } = scene
  if (aura === 'none') {
    return [...grid]
  }
  const { width: across, height: down } = CELL.sextant

  return render === 'sextant'
    ? sextantAura({ ...scene, depth: depths(grid, aura === 'flare' ? 2 : 1, across, down) })
    : halfBlockAura(grid, aura, tick, sparks, calmFrom)
}

// The small half-block fighter: 16x12, or its head alone (16x8).
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
    ...(look.pose === 'beam' ? PALMS.pixels : []),
  ]
  const drawn = put(eyed, details)

  return isHeadOnly ? drawn.slice(0, HEAD_ROWS) : drawn
}

// The layered art each render draws a tier with; the small half-block fighter
// is drawn whole instead.
const LAYERED: Record<Render, Partial<Record<Tier, LayeredArt>>> = {
  halfblock: { large: HALFBLOCK_LARGE },
  sextant: { large: SEXTANT_LARGE, medium: SEXTANT_SMALL, head: SEXTANT_SMALL },
}

// Where a tier's fighter pushes its palms out for a beam.
export const palmsOf = (tier: Tier, render: Render): Palms => LAYERED[render][tier]?.palms ?? PALMS

// The fighter in one pose at one tier, as palette keys, with its aura.
export const frame = (fighter: Fighter, look: Look, tick: number, tier: Tier, render: Render): string[] => {
  const form = shownForm(fighter, look)
  const art = LAYERED[render][tier]
  const isHeadOnly = tier === 'head'
  const { height } = pixelSize(tier, render)
  const grid =
    art === undefined
      ? smallFrame(fighter, form, look, isHeadOnly)
      : layered(art, { head: HEAD_OF[fighter.character](form), pose: look.pose, step: look.step, face: look.face, isHeadOnly }).slice(
          0,
          height,
        )
  const calmFrom = art?.calmFrom ?? HEAD_ROWS - 2

  const aura = hasAura(form) ? look.aura : 'none'

  return withAura(render, { grid, colors: paletteOf(fighter, form), aura, tick, sparks: hasSparks(form), calmFrom })
}

export const mirror = (grid: readonly string[]) => grid.map(row => [...row].reverse().join(''))
