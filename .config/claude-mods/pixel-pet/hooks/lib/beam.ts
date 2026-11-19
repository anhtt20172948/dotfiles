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
      return full + (Math.floor(elapsed / 100) % 2)
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

// The fighter's grid widened with the attack: a ball in its palms and the beam
// running right. The grid comes back as wide as what it draws, at most
// `maxColumns` text columns wider.
export const withAttack = (grid: readonly string[], scene: Scene): string[] => {
  const { attack, cell, maxColumns } = scene
  const isBig = attack.milestone !== null
  const spot = isBig ? { ...scene.spot, top: scene.spot.top - 1, cells: scene.spot.cells + 2 } : scene.spot
  const width = grid[0]?.length ?? 0
  const limit = width + Math.max(0, maxColumns) * cell.width
  const { phase, progress } = phaseOf(attack)
  // Whole cells at a time, so the beam's tip never shares a cell with nothing.
  const cells = Math.max(0, maxColumns) === 0 ? 0 : reachOf(phase, progress, limit - width) / cell.width
  const reach = Math.round(cells) * cell.width
  const end = width + reach
  const firstRow = spot.top * cell.height
  const lastRow = (spot.top + spot.cells) * cell.height - 1
  const middle = (firstRow + lastRow + 1) / 2
  const half = (spot.cells * cell.height) / 2
  const radius = radiusOf(phase, progress, half + 1 + (isBig ? 1 : 0), attack.elapsed)
  // The beam's head: a glow a cell deeper than the beam above and below,
  // rounded to its tip, out where the beam has left the fighter.
  const headRadius = half + cell.height
  const headX = end - headRadius
  // Only where the band has a row above and below the beam for it.
  const hasHeadRoom = firstRow - cell.height >= 0 && lastRow + cell.height < grid.length
  const fade = phase === 'fade' ? progress : 0
  const frame = Math.floor(attack.elapsed / 100)
  const canvas = grid.map(row => row.padEnd(limit, '.'))

  const drawn = canvas.map((row, y) =>
    [...row]
      .map((value, x) => {
        const isInBeam = y >= firstRow && y <= lastRow && x >= spot.x && x < end && reach > 0
        const distance = Math.hypot(x + 0.5 - spot.x, y + 0.5 - middle)
        const isInBall = radius > 0.5 && distance <= radius && x < (maxColumns > 0 ? limit : width)
        if (isInBall) {
          // A white-hot middle and a glowing rim that flickers.
          return distance <= radius - 1.5 ? 'V' : (x + y + frame) % 4 === 0 ? 'v' : 'u'
        }
        const isInHead =
          hasHeadRoom &&
          reach > 0 &&
          fade < 0.6 && x >= width && x < end && Math.hypot(x + 0.5 - headX, y + 0.5 - middle) <= headRadius
        if (!isInBeam) {
          return isInHead ? 'u' : value
        }
        const key = beamKey(y, spot.top, spot.cells, cell.height, fade)
        // The edges ripple as the beam runs, a whole cell at a time so no cell
        // takes a third colour; the top and bottom rows of cells out of step.
        const column = Math.floor(x / cell.width)
        const isLowerCell = Math.floor(y / cell.height) > spot.top

        return key === 'u' && (column + frame * 3 + (isLowerCell ? 3 : 0)) % 7 === 0 ? '.' : key
      })
      .join(''),
  )
  const used = Math.max(
    width,
    ...drawn.map(row => {
      const last = Math.max(...[...row].map((value, x) => (value === '.' ? -1 : x)))

      return last + 1
    }),
  )
  const columns = Math.ceil(used / cell.width) * cell.width

  return drawn.map(row => row.slice(0, Math.max(width, columns)))
}
