// The signature beam a fighter fires when a turn ends: it charges a ball of
// energy in its palms, fires a beam to the right that pushes the text beside
// it, then the beam fades and the text slides back. A turn that lifts the
// power level past a milestone fires a bigger, longer one.
//
// The beam is drawn into the fighter's pixel grid, widening it, so it is drawn
// as sextants, half blocks or plain glyphs exactly as the fighter is.

import type { Attack } from '../../types'
import type { Character } from './fighter'
import type { Pixel } from './layers'

export type Technique = 'kamehameha' | 'finalFlash' | 'masenko'

export const TECHNIQUES: Record<Character, Technique> = {
  goku: 'kamehameha',
  vegeta: 'finalFlash',
  gohan: 'masenko',
}

// The shout, a syllable at a time: all but the last while it charges, the last
// as it fires.
const CHANTS: Record<Technique, readonly string[]> = {
  kamehameha: ['Ka...', 'me...', 'ha...', 'me...', 'HA!!'],
  finalFlash: ['Final...', 'FLASH!!'],
  masenko: ['Ma...', 'sen...', 'KO!!'],
}

// The length of each phase, in milliseconds: a normal beam lasts 2.7 s, a
// milestone's 3.4 s.
type Timeline = { charge: number; fire: number; hold: number; fade: number }

const TIMELINES: Record<'normal' | 'big', Timeline> = {
  normal: { charge: 1_000, fire: 600, hold: 500, fade: 600 },
  big: { charge: 1_200, fire: 700, hold: 900, fade: 600 },
}

// How often the beam is redrawn while it runs.
export const FRAME_MS = 100

const timelineOf = (attack: Attack) => TIMELINES[attack.milestone === null ? 'normal' : 'big']

export const attackMs = (attack: Attack) => {
  const { charge, fire, hold, fade } = timelineOf(attack)

  return charge + fire + hold + fade
}

export type Phase = 'charge' | 'fire' | 'hold' | 'fade'

// Where an attack is: its phase and how far through it, from 0 to 1.
export const phaseOf = (attack: Attack): { phase: Phase; progress: number } => {
  const timeline = timelineOf(attack)
  const phases: Phase[] = ['charge', 'fire', 'hold', 'fade']
  let start = 0
  for (const phase of phases) {
    const length = timeline[phase]
    if (attack.elapsed < start + length) {
      return { phase, progress: Math.max(0, (attack.elapsed - start) / length) }
    }
    start += length
  }

  return { phase: 'fade', progress: 1 }
}

// The shout so far: one more charging syllable at a time, the last as it fires.
export const chant = (technique: Technique, attack: Attack) => {
  const syllables = CHANTS[technique]
  const { phase, progress } = phaseOf(attack)
  const charging = syllables.length - 1
  const said = phase === 'charge' ? Math.min(charging, Math.floor(progress * charging) + 1) : syllables.length

  return syllables.slice(0, said).join(' ')
}

// Power milestones: 9,000, then every power of ten from 100,000 up.
const FIRST_MILESTONE = 9_000
const NEXT_MILESTONE = 100_000

export const milestoneOf = (power: number): number => {
  if (power < FIRST_MILESTONE) {
    return 0
  }
  let milestone = FIRST_MILESTONE
  for (let next = NEXT_MILESTONE; next <= power; next *= 10) {
    milestone = next
  }

  return milestone
}

// What a milestone's beam shouts beside the counts.
export const milestoneShout = (milestone: number) =>
  milestone === FIRST_MILESTONE ? "It's over 9000!!!" : `It's over ${milestone.toLocaleString('en-US')}!!!`

// Where a fighter's palms push the beam out: `x`, the first pixel column in
// front of the palms, where the ball glows; `top`, the text row the beam's top
// lies on; `cells`, how many text rows thick it is. A milestone's beam is a
// row thicker above and below.
export type BeamSpot = { x: number; top: number; cells: number }

// Both palms pushed forward, for a fighter's art, and where its beam starts.
export type Palms = { pixels: readonly Pixel[]; spot: BeamSpot }

type Scene = {
  attack: Attack
  spot: BeamSpot
  cell: { width: number; height: number }
  // How many text columns the beam may take beyond the fighter: 0 keeps it in
  // the palms (a ball, no beam).
  maxColumns: number
}

const easeOut = (t: number) => 1 - (1 - t) ** 2

// How far the beam reaches past the fighter's right edge, in pixels.
const reachOf = (phase: Phase, progress: number, room: number) => {
  switch (phase) {
    case 'charge':
      return 0
    case 'fire':
      return Math.round(easeOut(progress) * room)
    case 'hold':
      return room
    case 'fade':
      return Math.round((1 - easeOut(progress)) * room)
  }
}

// The ball's radius in pixels: it grows as the fighter charges, pulses as it
// fires, and shrinks as the beam fades.
const radiusOf = (phase: Phase, progress: number, full: number, elapsed: number) => {
  switch (phase) {
    case 'charge':
      return 1 + progress * (full - 1)
    case 'fire':
    case 'hold':
      return full + (Math.floor(elapsed / FRAME_MS) % 2)
    case 'fade':
      return full * (1 - progress)
  }
}

// The beam's key for pixel row `y`, by where the row lies in the beam: a thin
// edge (u) around a white-hot core (V); a thick beam glows (v) inside its edge
// rows of cells and is white-hot only in the middle. A beam one half-block row
// thick is all core. Every cell holds two colours at most. As it fades the
// core cools and then the edges go.
const beamKey = (y: number, top: number, cells: number, down: number, fade: number): string => {
  const row = Math.floor(y / down) - top
  const sub = y % down
  const hasEdges = cells > 1 || down >= 3
  const isEdgeRow = hasEdges && ((row === 0 && sub === 0) || (row === cells - 1 && sub === down - 1))
  if (isEdgeRow) {
    return fade > 0.6 ? '.' : 'u'
  }
  const isEdgeCell = row === 0 || row === cells - 1
  const core = fade > 0.3 ? 'v' : 'V'

  return cells >= 3 && isEdgeCell ? 'v' : core
}

// Where everything of one frame of an attack lies, in pixels of the widened grid.
type Layout = {
  spot: BeamSpot
  cell: Scene['cell']
  // The fighter's width, and the widest the grid may grow.
  width: number
  limit: number
  // Where the beam ends (`width` while it has not left the palms).
  end: number
  firstRow: number
  lastRow: number
  middle: number
  radius: number
  // The ball may glow past the fighter only where the beam has room.
  ballLimit: number
  // The rounded head, or null where the band has no row above and below for it.
  head: { x: number; radius: number } | null
  fade: number
  frame: number
}

const layoutOf = (grid: readonly string[], { attack, spot: palms, cell, maxColumns }: Scene): Layout => {
  const isBig = attack.milestone !== null
  // A milestone's beam is a row of cells thicker above and below.
  const spot = isBig ? { ...palms, top: palms.top - 1, cells: palms.cells + 2 } : palms
  const room = Math.max(0, maxColumns)
  const width = grid[0]?.length ?? 0
  const limit = width + room * cell.width
  const { phase, progress } = phaseOf(attack)
  // Whole cells at a time, so the beam's tip never shares a cell with nothing.
  const reachColumns = room === 0 ? 0 : Math.round(reachOf(phase, progress, limit - width) / cell.width)
  const end = width + reachColumns * cell.width
  const firstRow = spot.top * cell.height
  const lastRow = (spot.top + spot.cells) * cell.height - 1
  const half = (spot.cells * cell.height) / 2
  const fade = phase === 'fade' ? progress : 0
  // The head glows a cell deeper than the beam above and below, out where the
  // beam has left the fighter, until the beam cools.
  const headRadius = half + cell.height
  const hasHead =
    end > width && fade < 0.6 && firstRow - cell.height >= 0 && lastRow + cell.height < grid.length

  return {
    spot,
    cell,
    width,
    limit,
    end,
    firstRow,
    lastRow,
    middle: (firstRow + lastRow + 1) / 2,
    radius: radiusOf(phase, progress, half + 1 + (isBig ? 1 : 0), attack.elapsed),
    ballLimit: room > 0 ? limit : width,
    head: hasHead ? { x: end - headRadius, radius: headRadius } : null,
    fade,
    frame: Math.floor(attack.elapsed / FRAME_MS),
  }
}

// The pixel at `x`, `y` with the attack over `value`, what the fighter has there.
const pixelAt = (layout: Layout, x: number, y: number, value: string): string => {
  const { spot, cell, width, end, firstRow, lastRow, middle, radius, ballLimit, head, fade, frame } = layout
  const distance = Math.hypot(x + 0.5 - spot.x, y + 0.5 - middle)
  if (radius > 0.5 && distance <= radius && x < ballLimit) {
    // A white-hot middle and a glowing rim that flickers.
    return distance <= radius - 1.5 ? 'V' : (x + y + frame) % 4 === 0 ? 'v' : 'u'
  }
  // The beam runs only once it has left the palms.
  const isInBeam = end > width && y >= firstRow && y <= lastRow && x >= spot.x && x < end
  if (!isInBeam) {
    const isInHead = head !== null && x >= width && x < end && Math.hypot(x + 0.5 - head.x, y + 0.5 - middle) <= head.radius

    return isInHead ? 'u' : value
  }
  const key = beamKey(y, spot.top, spot.cells, cell.height, fade)
  // The edges ripple as the beam runs, a whole cell at a time so no cell takes
  // a third colour; the top and bottom rows of cells out of step.
  const column = Math.floor(x / cell.width)
  const isLowerCell = Math.floor(y / cell.height) > spot.top

  return key === 'u' && (column + frame * 3 + (isLowerCell ? 3 : 0)) % 7 === 0 ? '.' : key
}

// The rows cut to what they draw, in whole cells, never narrower than the fighter.
const trimmed = (rows: readonly string[], width: number, cellWidth: number) => {
  const lastDrawn = Math.max(...rows.map(row => Math.max(-1, ...[...row].map((value, x) => (value === '.' ? -1 : x)))))
  const columns = Math.max(width, Math.ceil((lastDrawn + 1) / cellWidth) * cellWidth)

  return rows.map(row => row.slice(0, columns))
}

// The fighter's grid widened with the attack: a ball in its palms and the beam
// running right. The grid comes back as wide as what it draws, at most
// `maxColumns` text columns wider.
export const withAttack = (grid: readonly string[], scene: Scene): string[] => {
  const layout = layoutOf(grid, scene)
  const drawn = grid.map((row, y) =>
    [...row.padEnd(layout.limit, '.')].map((value, x) => pixelAt(layout, x, y, value)).join(''),
  )

  return trimmed(drawn, layout.width, scene.cell.width)
}
