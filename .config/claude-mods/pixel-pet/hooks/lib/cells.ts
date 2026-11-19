// Pixel grids as text: each text cell holds a block of pixels drawn with one
// glyph, a foreground and a background colour.
//
// Half blocks hold two pixel rows a cell (`▀` over `▄`), so a cell never has
// more than two colours. Sextants (U+1FB00-1FB3B, Unicode 13) hold a 2x3 block,
// three times the pixels in the same cell; a block that mixes more than two
// colours keeps the two that lose the least, weighed by how much each pixel
// matters (an eye over the skin around it).

import type { Palette } from './palette'

export type Render = 'sextant' | 'halfblock'

export const RENDERS: readonly Render[] = ['sextant', 'halfblock']

// The Render row of /config: anything it does not list draws sextants.
export const renderChoice = (value: unknown): Render => (value === 'halfblock' ? 'halfblock' : 'sextant')

export type Segment = { text: string; color?: string; backgroundColor?: string }

// Pixels across and down one text cell.
export const CELL: Record<Render, { width: number; height: number }> = {
  halfblock: { width: 1, height: 2 },
  sextant: { width: 2, height: 3 },
}

// Without colour the fighter is a silhouette: its eyes, mouth and tears are cut
// out of it and the aura is left off.
const MONOCHROME_HOLES = new Set(['e', 'c', 'l', 'w', 'm', 'n', 't', 'b', 'o', 'i', 'z'])

// How much losing a pixel costs: the face's details first, the aura last.
const WEIGHTS: Record<string, number> = {
  e: 6,
  w: 6,
  l: 6,
  m: 5,
  n: 5,
  t: 5,
  b: 5,
  p: 4,
  M: 4,
  c: 4,
  k: 3,
  d: 2,
  o: 0.5,
  i: 0.5,
  z: 1,
}


const weightOf = (pixel: string) => WEIGHTS[pixel] ?? 1

// Dropping a pixel to the terminal's background, or painting one there, costs
// as much as the most distant colour.
const TRANSPARENT_COST = 1

const HEX = /^#[0-9a-f]{6}$/i

const rgb = (color: string): [number, number, number] | null =>
  HEX.test(color) ? [parseInt(color.slice(1, 3), 16), parseInt(color.slice(3, 5), 16), parseInt(color.slice(5, 7), 16)] : null

// A perceptual distance between two colours (the "redmean" weighting), from 0
// (the same) to about 1. A colour that is no hex value is as far as can be.
const distance = (a: string, b: string) => {
  const first = rgb(a)
  const second = rgb(b)
  if (a === b || first === null || second === null) {
    return a === b ? 0 : 1
  }
  const [r1, g1, b1] = first
  const [r2, g2, b2] = second
  const mean = (r1 + r2) / 2
  const squared =
    (2 + mean / 256) * (r1 - r2) ** 2 + 4 * (g1 - g2) ** 2 + (2 + (255 - mean) / 256) * (b1 - b2) ** 2

  return Math.sqrt(squared) / 765
}

// A pixel of a cell: its colour (null where it is transparent) and how much it matters.
type Dot = { color: string | null; weight: number }

const cost = (dot: Dot, to: string | null) => {
  if (dot.color === to) {
    return 0
  }

  return dot.weight * (dot.color === null || to === null ? TRANSPARENT_COST : distance(dot.color, to))
}

// The two colours (either may be transparent) that draw a cell's pixels losing
// the least; a cell of one colour gets it twice.
const pickTwo = (dots: readonly Dot[]): [string | null, string | null] => {
  const colors = [...new Set(dots.map(dot => dot.color))]
  const [only = null, other = only] = colors
  if (colors.length <= 2) {
    return [only, colors.length === 1 ? only : other]
  }
  let best: [string | null, string | null] = [null, null]
  let least = Infinity
  colors.forEach((first, i) => {
    colors.slice(i + 1).forEach(second => {
      const total = dots.reduce((sum, dot) => sum + Math.min(cost(dot, first), cost(dot, second)), 0)
      if (total < least) {
        best = [first, second]
        least = total
      }
    })
  })

  return best
}

// The sextant glyph lighting `mask`'s cells: bit 0 the top left, 1 the top
// right, down to bit 5 the bottom right. The two half columns and the full
// block were encoded before Unicode 13 and are skipped by its run.
export const sextant = (mask: number): string => {
  if (mask === 0) {
    return ' '
  }
  if (mask === 63) {
    return '█'
  }
  if (mask === 21) {
    return '▌'
  }
  if (mask === 42) {
    return '▐'
  }

  return String.fromCodePoint(0x1fb00 + mask - 1 - (mask > 21 ? 1 : 0) - (mask > 42 ? 1 : 0))
}

const maskOf = (lit: readonly boolean[]) => lit.reduce((mask, isLit, bit) => (isLit ? mask | (1 << bit) : mask), 0)

// A half-block cell, as it has always been drawn: the upper pixel's colour over
// the lower one's.
const halfBlockCell = ([top, bottom]: readonly Dot[]): Segment => {
  const upper = top?.color ?? null
  const lower = bottom?.color ?? null
  if (upper === null) {
    return lower === null ? { text: ' ' } : { text: '▄', color: lower }
  }
  if (lower === null) {
    return { text: '▀', color: upper }
  }

  return upper === lower ? { text: '█', color: upper } : { text: '▀', color: upper, backgroundColor: lower }
}

// A sextant cell in its two colours. Over transparency the colour is drawn
// alone over the terminal; otherwise the colour fewer pixels take is drawn
// over the other, and on a tie the top left pixel's colour is the background.
const sextantCell = (dots: readonly Dot[]): Segment => {
  const [first, second] = pickTwo(dots)
  const takesFirst = dots.map(dot => cost(dot, first) <= cost(dot, second))
  if (first === null || second === null) {
    const color = first ?? second
    const lit = takesFirst.map(isFirst => (first === null ? !isFirst : isFirst))

    return color === null ? { text: ' ' } : { text: sextant(maskOf(lit)), color }
  }
  const firstCount = takesFirst.filter(Boolean).length
  if (first === second || firstCount === dots.length || firstCount === 0) {
    return { text: '█', color: firstCount === 0 ? second : first }
  }
  const isFirstInFront =
    firstCount * 2 < dots.length || (firstCount * 2 === dots.length && takesFirst[0] === false)
  const [front, back] = isFirstInFront ? [first, second] : [second, first]

  return {
    text: sextant(maskOf(takesFirst.map(isFirst => isFirst === isFirstInFront))),
    color: front,
    backgroundColor: back,
  }
}

const cell = (render: Render, dots: readonly Dot[], isMonochrome: boolean): Segment => {
  const isSolid = dots.map(dot => dot.color !== null)
  if (!isSolid.includes(true)) {
    return { text: ' ' }
  }
  if (isMonochrome) {
    return { text: render === 'halfblock' ? halfBlockCell(dots).text : sextant(maskOf(isSolid)) }
  }

  return render === 'halfblock' ? halfBlockCell(dots) : sextantCell(dots)
}

// The pixels of the cell at column `x`, row `y`, top left first. A key the
// palette lacks, or a hole of the silhouette, is transparent.
const dotsAt = (grid: readonly string[], x: number, y: number, render: Render, colors: Palette, isMonochrome: boolean) => {
  const { width: across, height: down } = CELL[render]

  return Array.from({ length: across * down }, (_, at): Dot => {
    const key = grid[y * down + Math.floor(at / across)]?.[x * across + (at % across)] ?? '.'
    const color = key === '.' || (isMonochrome && MONOCHROME_HOLES.has(key)) ? undefined : colors[key]

    return color === undefined ? { color: null, weight: 1 } : { color: isMonochrome ? 'solid' : color, weight: weightOf(key) }
  })
}

const isSameStyle = (a: Segment, b: Segment) => a.color === b.color && a.backgroundColor === b.backgroundColor

// Each text row as runs of one style, so a row costs a few elements, not one per cell.
export const rows = (grid: readonly string[], colors: Palette, render: Render, isMonochrome = false): Segment[][] => {
  const { width: across, height: down } = CELL[render]
  const columns = Math.ceil((grid[0]?.length ?? 0) / across)

  return Array.from({ length: Math.ceil(grid.length / down) }, (_, y) =>
    Array.from({ length: columns }, (_, x) => cell(render, dotsAt(grid, x, y, render, colors, isMonochrome), isMonochrome)).reduce<
      Segment[]
    >((line, next) => {
      const last = line.at(-1)

      return last !== undefined && isSameStyle(last, next)
        ? [...line.slice(0, -1), { ...last, text: last.text + next.text }]
        : [...line, next]
    }, []),
  )
}

// Cells whose pixels mix more than two colours (transparency counts as one),
// where a sextant has to drop one: [column, row] of each, for checks.
export const clashes = (grid: readonly string[], colors: Palette, render: Render): [number, number][] => {
  const { width: across, height: down } = CELL[render]
  const cells = Array.from({ length: Math.ceil(grid.length / down) }, (_, y) =>
    Array.from({ length: Math.ceil((grid[0]?.length ?? 0) / across) }, (_, x): [number, number] => [x, y]),
  ).flat()

  return cells.filter(
    ([x, y]) => new Set(dotsAt(grid, x, y, render, colors, false).map(dot => dot.color)).size > 2,
  )
}
