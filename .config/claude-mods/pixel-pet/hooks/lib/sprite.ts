// Pixel art drawn with half blocks: one text row holds two pixel rows, the
// upper pixel as the glyph's colour and the lower as its background.

export type Segment = { text: string; color?: string; backgroundColor?: string }

export type Look = { isBlinking: boolean; hasBlush: boolean; hasTear: boolean; step: 0 | 1 }

export const WIDTH = 12

// '.' is transparent; every other letter is a palette key.
export const PALETTE: Record<string, string> = {
  k: '#5c3d2e', // outline
  o: '#f4a259', // fur
  w: '#fff1dc', // paws
  p: '#f28482', // nose and blush
  e: '#1b1b1b', // eyes
  b: '#5fa8d3', // tear
}

const BODY = [
  '.kk......kk.',
  '.kok....kok.',
  '.kookkkkook.',
  'kooooooooook',
  'koeooooooeok',
  'kooooppooook',
  'kwoooooooowk',
  '.kkkkkkkkkk.',
]

const PAWS = ['kwoooooooowk', 'kowoooooowok'] as const

const put = (row: string, at: number, pixel: string) =>
  row.slice(0, at) + pixel + row.slice(at + 1)

export const frame = (look: Look): string[] =>
  BODY.map((row, y) => {
    if (y === 4 && look.isBlinking) {
      return row.replaceAll('e', 'k')
    }
    if (y === 5) {
      const blushed = look.hasBlush ? put(put(row, 1, 'p'), 10, 'p') : row

      return look.hasTear ? put(blushed, 2, 'b') : blushed
    }

    return y === 6 ? PAWS[look.step] : row
  })

export const mirror = (grid: string[]) => grid.map(row => [...row].reverse().join(''))

// Without colour the sprite is a silhouette and these pixels are cut out of it.
const MONOCHROME_HOLES = new Set(['e', 'b'])

const cell = (top: string, bottom: string, isMonochrome: boolean): Segment => {
  const paint = (pixel: string) => (isMonochrome ? {} : { color: PALETTE[pixel] })
  if (top === '.' && bottom === '.') {
    return { text: ' ' }
  }
  if (bottom === '.') {
    return { text: '▀', ...paint(top) }
  }
  if (top === '.') {
    return { text: '▄', ...paint(bottom) }
  }
  if (isMonochrome || PALETTE[top] === PALETTE[bottom]) {
    return { text: '█', ...paint(top) }
  }

  return { text: '▀', color: PALETTE[top], backgroundColor: PALETTE[bottom] }
}

const isSameStyle = (a: Segment, b: Segment) =>
  a.color === b.color && a.backgroundColor === b.backgroundColor

// Each text row as runs of one style, so a row costs a few elements, not one per pixel.
export const rows = (grid: string[], isMonochrome = false): Segment[][] => {
  const pixel = (value: string | undefined) =>
    value === undefined || (isMonochrome && MONOCHROME_HOLES.has(value)) ? '.' : value
  const lines: Segment[][] = []
  for (let y = 0; y < grid.length; y += 2) {
    const line: Segment[] = []
    for (let x = 0; x < WIDTH; x += 1) {
      const next = cell(pixel(grid[y]?.[x]), pixel(grid[y + 1]?.[x]), isMonochrome)
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
