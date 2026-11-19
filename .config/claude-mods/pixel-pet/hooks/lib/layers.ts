// A fighter drawn in layers: the hair behind, a face every character shares,
// the hair in front, the mood's expression over the face, and a body below.
// The large half-block fighter and both sextant fighters are drawn this way.

import type { Head, Pose } from './art'

export type Expression = 'idle' | 'blink' | 'power' | 'happy' | 'hurt' | 'calm'

export const EXPRESSION_NAMES: readonly Expression[] = ['idle', 'blink', 'power', 'happy', 'hurt', 'calm']

// [x, y, palette key]
export type Pixel = readonly [number, number, string]

export type LayeredArt = {
  width: number
  height: number
  // The head fills the rows above `headRows`; the body starts there.
  headRows: number
  // Hair rows up to this one lie over the face (bangs, a widow's peak); rows
  // below it lie behind the face and body (Super Saiyan 3's mane).
  hairFrontRow: number
  // The calm aura glows from this row down, around the body.
  calmFrom: number
  // How far the head sinks when the fighter sits to meditate.
  meditateDrop: number
  face: readonly string[]
  hair: Record<Head, readonly string[]>
  // Where an expression's top left corner lies on the face.
  expressionOrigin: { x: number; y: number }
  // What each mood does to the face; '.' keeps the face. The first
  // `browRows` rows hold the brows.
  expressions: Record<Expression, readonly string[]>
  browRows: number
  // Vegeta's brows slant down to the middle even at rest: these rows replace
  // the brows and overlay the rows below them.
  scowl: readonly string[]
  // Bodies below the head, with two steps of a walk where it moves.
  bodies: Record<Pose, readonly (readonly string[])[]>
  // The thumbs-up arm beside the chin.
  thumb: readonly Pixel[]
  // The Majin mark hanging from the widow's peak, above the brows.
  majinMark: readonly Pixel[]
}

const blank = (width: number, height: number) => Array.from({ length: height }, () => '.'.repeat(width))

// The upper drawing wins wherever it is not transparent.
export const over = (under: readonly string[], upper: readonly string[]) =>
  under.map((row, y) =>
    [...row].map((value, x) => (upper[y]?.[x] === undefined || upper[y]?.[x] === '.' ? value : upper[y]?.[x])).join(''),
  )

export const put = (grid: readonly string[], pixels: readonly Pixel[]) => {
  const at = new Map(pixels.map(([x, y, value]) => [`${x},${y}`, value]))

  return grid.map((row, y) => [...row].map((value, x) => at.get(`${x},${y}`) ?? value).join(''))
}

// Rows moved down by `by`, the top filled with nothing.
export const lowered = (grid: readonly string[], by: number) =>
  by === 0 ? [...grid] : [...blank(grid[0]?.length ?? 0, by), ...grid.slice(0, grid.length - by)]

// A drawing placed at row `top` of a blank grid of `height` rows.
export const placed = (rows: readonly string[], top: number, width: number, height: number) =>
  blank(width, height).map((row, y) => rows[y - top] ?? row)

// The mood's face for a head: Super Saiyan 3 has no brows, and Vegeta's brows
// scowl unless the mood draws its own.
const expressionOf = (art: LayeredArt, head: Head, face: Expression): string[] => {
  const drawn = art.expressions[face]
  const isScowling = head.startsWith('vegeta') && (face === 'idle' || face === 'blink' || face === 'calm')
  const scowled = (row: string, y: number) =>
    y < art.browRows ? (art.scowl[y] ?? row) : (over([row], [art.scowl[y] ?? ''])[0] ?? row)
  const browed = isScowling ? drawn.map(scowled) : [...drawn]

  return head === 'gokuSsj3' ? browed.map(row => row.replaceAll('d', '.')) : browed
}

export type Layered = {
  head: Head
  pose: Pose
  step: 0 | 1
  face: Expression
  // Only the head, as in a band too short for the body: it does not sink to meditate.
  isHeadOnly?: boolean
}

// The fighter's pixels: hair behind, body, face, bangs and the mood's face over them.
export const layered = (art: LayeredArt, { head, pose, step, face, isHeadOnly = false }: Layered): string[] => {
  const { width, height } = art
  const hair = art.hair[head]
  const back = hair.map((row, y) => (y > art.hairFrontRow ? row : '.'.repeat(width)))
  const front = hair.map((row, y) => (y <= art.hairFrontRow ? row : '.'.repeat(width)))
  const expression = expressionOf(art, head, face).map(row => '.'.repeat(art.expressionOrigin.x) + row)
  const faced = over(over(placed(art.face, 0, width, height), front), placed(expression, art.expressionOrigin.y, width, height))
  const marked = head === 'vegetaMajin' ? put(faced, art.majinMark) : faced
  const isSitting = pose === 'meditate' && !isHeadOnly
  const shift = isSitting ? art.meditateDrop : 0
  const bodies = art.bodies[pose]
  const body = bodies[step % bodies.length] ?? []
  const bodyTop = isSitting ? height - body.length : art.headRows
  const drawn = over(over(lowered(placed(back, 0, width, height), shift), placed(body, bodyTop, width, height)), lowered(marked, shift))

  return pose === 'thumbs' ? put(drawn, art.thumb) : drawn
}
