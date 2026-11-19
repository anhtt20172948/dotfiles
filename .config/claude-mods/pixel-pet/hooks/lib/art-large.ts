// The large half-block fighter: hand-drawn 24x20 grids for a band of ten rows or more.
//
// Hair: d h H (shade, fill, highlight). Rows up to HAIR_FRONT_ROW lie over
// the face (bangs, a widow's peak); rows below it lie behind the face and body
// (Super Saiyan 3's mane). Face: k outline, s skin, q skin shade. Expressions
// add brows (d), eyes (l lash, e iris, w glint), a nose (q), a mouth (n closed,
// m open, t teeth), blush (p) and tears (b). Bodies: T torso, U torso shade, A accent (collar, belt, sash),
// L arm, C wristband or glove cuff, S hand, P trousers, F boots.

import type { Head, Pose } from './art'
import type { Expression, LayeredArt, Pixel } from './layers'

const LARGE = { width: 24, height: 20 } as const

// The head fills rows 0-13; the body the rows below.
const LARGE_HEAD_ROWS = 14
const HAIR_FRONT_ROW = 8

const EMPTY = '.'.repeat(LARGE.width)

const pad = (rows: readonly string[]) => [...rows, ...Array.from({ length: LARGE.height - rows.length }, () => EMPTY)]

// Every character shares one face, so the expressions fit all of them.
const FACE: readonly string[] = pad([
  ...Array.from({ length: 7 }, () => EMPTY),
  '......kssssssssssk......',
  '......kssssssssssk......',
  '.....kssssssssssssk.....',
  '.....kssssssssssssk.....',
  '......kqssssssssqk......',
  '.......kqssssssqk.......',
  '........kkqsqskk........',
])

const LARGE_HAIR: Record<Head, readonly string[]> = {
  goku: pad([
    '........d.......d.......',
    '.......dHd.....dHd...d..',
    '..d...dhHhd...dhHhd.dHd.',
    '..dd.dhhhhhd.dhhhhhdhhd.',
    '.dhhddhhhHhhdhhhhHhhhhd.',
    'dhhhhhhhhHhhhhhhhHhhhhhd',
    'dhhhhhhhhhhhhhhhhhhhhhhd',
    'dhhhhhh.hhh..hhh.hhhhhhd',
    '.dhhhd............dhhhd.',
    '..dhhd............dhhd..',
    '...dd..............dd...',
  ]),
  // Super Saiyan 1 and 2: every spike stands up, two bangs fall.
  gokuSuper: pad([
    '..d....d....dd....d...d.',
    '..dd..dHd..dHHd..dHd.dd.',
    '..dHd.dHd.dhHHhd.dHd.Hd.',
    '...dHddhHddhhHhhddHhdHd.',
    '...dhhhhHhhhhHhhhhHhhhd.',
    '..dhhhhhhhhhhHhhhhhhhhd.',
    '..dhhhhhhhhhhhhhhhhhhhd.',
    '...dhhh.......hhhh.hhd..',
    '...dhd..........h..dhd..',
    '....d..............dd...',
  ]),
  // Super Saiyan 3: no brows, a bare forehead and a mane down to the heels.
  gokuSsj3: pad([
    '...d..d....dd....d..d...',
    '..dHd.dHd.dHHd..dHd.dHd.',
    '.dhHhdhHhdhhHhhdhHhdhHd.',
    'dhhhhhhhhhhhHhhhhhhhhhhd',
    'dhhhhhhhhhhhHhhhhhhhhhhd',
    'dhhhhhhhhhhhhhhhhhhhhhhd',
    'dhhhhhhhhhhhhhhhhhhhhhhd',
    'dhhhhhd..........dhhhhhd',
    'dhhhhd............dhhhhd',
    'dhhhhd............dhhhhd',
    'dhhhhd............dhhhhd',
    'dhhhhd............dhhhhd',
    'dhhhd..............dhhhd',
    'dhhhd..............dhhhd',
    'dhhhd..............dhhhd',
    '.dhhd..............dhhd.',
    '.dhhd..............dhhd.',
    '.dhhd..............dhhd.',
    '..dhd..............dhd..',
    '...d................d...',
  ]),
  // A flame of hair rising from a widow's peak.
  vegeta: pad([
    '...........dd...........',
    '.........d.dHd.d........',
    '........dHddhHddHd......',
    '......d.dhhhhHhhhd.d....',
    '.....dHdhhhhhHhhhhdHd...',
    '.....dhhhhhhhhhhhhhhd...',
    '......dhhhhhhhhhhhhd....',
    '........dhhhhhhd........',
    '..........dhhd..........',
  ]),
  // The Majin mark hangs from a shorter peak (MAJIN_MARK).
  vegetaMajin: pad([
    '...........dd...........',
    '.........d.dHd.d........',
    '........dHddhHddHd......',
    '......d.dhhhhHhhhd.d....',
    '.....dHdhhhhhHhhhhdHd...',
    '.....dhhhhhhhhhhhhhhd...',
    '......dhhhhhhhhhhhhd....',
    '........dh.hh.hd........',
  ]),
  // A kid: smaller hair with one bang over the brow.
  gohan: pad([
    EMPTY,
    EMPTY,
    '.........d...d..........',
    '.......d.dHd.dHd.d......',
    '.....dHddhHhdhhhdHd.....',
    '....dhhhhhhHhhhhhhhd....',
    '....dhhhhhhhhhhhhhhd....',
    '.....dhhhhh.hhh.hhd.....',
    '.....dhd....hh....d.....',
  ]),
  gohanSuper: pad([
    '.......d....d...d.......',
    '......dHd..dHd.dHd......',
    '.....dhHd.dhHhddHhd.....',
    '...d.dhHhdhhHhhdhhd.d...',
    '...dHdhhhhhhHhhhhhhdHd..',
    '....dhhhhhhhhhhhhhhhd...',
    '....dhhhhhhhhhhhhhhhd...',
    '.....dhhhh.......hhd....',
    '.....dhd.....h....d.....',
  ]),
}

// Vegeta scowls even at rest: his brows always slant down to the middle.
const SCOWL: readonly string[] = ['.d....d.', '..d..d..']

// What each mood does to the face, over cols 8-15 of rows 8-12; '.' keeps the face.
const EXPRESSION_ORIGIN = { x: 8, y: 8 } as const

const EXPRESSIONS: Record<Expression, readonly string[]> = {
  idle: ['.dd..dd.', '.wl..wl.', '.ee..ee.', '...q....', '...nn...'],
  blink: ['.dd..dd.', '........', '.ll..ll.', '...q....', '...nn...'],
  // Brows down in a V, eyes narrowed, shouting.
  power: ['.d....d.', '..d..d..', '.ee..ee.', '...tt...', '...mm...'],
  // Eyes shut in arcs, a grin and blushing cheeks.
  happy: ['.dd..dd.', '.ll..ll.', 'l..ll..l', 'p.mttm.p', '...mm...'],
  // Eyes squeezed shut, brows up, a frown and a tear.
  hurt: ['..d..d..', '.l....l.', '..l..l..', 'b..mm...', '..m..m..'],
  calm: ['.dd..dd.', '........', '.ll..ll.', '...q....', '...nn...'],
}

// Bodies over the rows below the head, with two steps of a walk where it moves.
const LARGE_BODIES: Record<Pose, readonly (readonly string[])[]> = {
  stand: [
    [
      '......kTTTAssATTTk......',
      '.....LUTTTTAATTTTUL.....',
      '.....LUTTTTTTTTTTUL.....',
      '.....CAAAAAAAAAAAAC.....',
      '.....S.PPPPPPPPPP.S.....',
      '.......FFF....FFF.......',
    ],
    [
      '......kTTTAssATTTk......',
      '.....LUTTTTAATTTTUL.....',
      '.....LUTTTTTTTTTTUL.....',
      '.....CAAAAAAAAAAAAC.....',
      '.....S.PPPPPPPPPP.S.....',
      '......FFF......FFF......',
    ],
  ],
  // Fists clenched at the hips, feet planted wide.
  power: [
    [
      '......kTTTAssATTTk......',
      '....LLUTTTTAATTTTULL....',
      '...SCLUTTTTTTTTTTULCS...',
      '......AAAAAAAAAAAA......',
      '.....PPPPP....PPPPP.....',
      '....FFFF........FFFF....',
    ],
  ],
  // The raised arm and fist are drawn beside the face (LARGE_THUMB).
  thumbs: [
    [
      '......kTTTAssATTTkL.....',
      '.....LUTTTTAATTTTU......',
      '.....LUTTTTTTTTTTU......',
      '.....CAAAAAAAAAAAA......',
      '.....S.PPPPPPPPPP.......',
      '.......FFF....FFF.......',
    ],
  ],
  // Flung back, arms thrown up, legs splayed.
  knocked: [
    [
      '...S..kTTTAssATTTk..S...',
      '....LLUTTTTAATTTTULL....',
      '......UTTTTTTTTTTU......',
      '......AAAAAAAAAAAA......',
      '......PPPP....PPPP......',
      '.....FFF........FFF.....',
    ],
  ],
  // Sitting cross-legged, hands in the lap: the head sits two rows lower.
  meditate: [
    [
      '......kTTTAssATTTk......',
      '.....LUTTTTAATTTTUL.....',
      '...PPPPPPPSSSSPPPPPPP...',
      '..FFPPPPPPPPPPPPPPPPFF..',
    ],
  ],
}

// The thumbs-up arm beside the chin.
const LARGE_THUMB: readonly Pixel[] = [
  [18, 13, 'L'],
  [19, 12, 'C'],
  [19, 11, 'S'],
  [20, 11, 'S'],
  [19, 10, 'S'],
  [20, 10, 'S'],
  [20, 9, 'S'],
]

// The Majin mark: a red M hanging from the widow's peak, above the brows.
const MAJIN_MARK: readonly Pixel[] = [
  [10, 7, 'M'],
  [13, 7, 'M'],
  [11, 8, 'M'],
  [12, 8, 'M'],
]

export const HALFBLOCK_LARGE: LayeredArt = {
  ...LARGE,
  headRows: LARGE_HEAD_ROWS,
  hairFrontRow: HAIR_FRONT_ROW,
  calmFrom: LARGE_HEAD_ROWS - 4,
  meditateDrop: 2,
  face: FACE,
  hair: LARGE_HAIR,
  expressionOrigin: EXPRESSION_ORIGIN,
  expressions: EXPRESSIONS,
  browRows: 1,
  scowl: SCOWL,
  bodies: LARGE_BODIES,
  thumb: LARGE_THUMB,
  majinMark: MAJIN_MARK,
}
