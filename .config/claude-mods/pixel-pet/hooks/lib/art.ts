// Hand-drawn 16x12 pixel grids. '.' is transparent; every other letter is a
// palette key (palette.ts), so one drawing serves every form and character.
//
// Heads: d h H hair (shade, fill, highlight), k outline, s skin, e eyes,
// M the Majin mark. Bodies: T torso, A accent (collar, belt), R wristband or
// sleeve, S hand, P trousers, F feet.

import type { Palms } from './beam'

export const SIZE = { width: 16, height: 12 } as const

// The head fills rows 0-7; a body (or Super Saiyan 3's hair) the rows below.
export const HEAD_ROWS = 8

const EMPTY = '.'.repeat(SIZE.width)

const below = (rows: number) => Array.from({ length: rows }, () => EMPTY)

export type Head = 'goku' | 'gokuSuper' | 'gokuSsj3' | 'vegeta' | 'vegetaMajin' | 'gohan' | 'gohanSuper'

export const HEADS: Record<Head, readonly string[]> = {
  goku: [
    '..d...d....d....',
    '.dh..dHd..dhd.d.',
    '.dhddhHhddhhhdh.',
    'dhhhhhhHhhhhhhhd',
    'dhhhhhshhshhhhhd',
    '..hdksesseskdh..',
    '....kssssssk....',
    '.....kssssk.....',
    ...below(4),
  ],
  gokuSuper: [
    '.d..d..dd..d..d.',
    '.dh.dhdhhdhd.hd.',
    '..hdhhhHhhhhdh..',
    '.dhhhhhHhhhhhhd.',
    '..dhhshhsshhhd..',
    '...dksesseskd...',
    '....kssssssk....',
    '.....kssssk.....',
    ...below(4),
  ],
  // Super Saiyan 3: no brows, no bangs, and hair down to the heels.
  gokuSsj3: [
    '..d.d..dd..d.d..',
    '.dhdhddhhddhdhd.',
    'dhhhhhhHhhhhhhhd',
    'dhhhhhhHhhhhhhhd',
    'dhhhsssssssshhhd',
    'dhhhksesseskhhhd',
    'dhh.kssssssk.hhd',
    'dhh..kssssk..hhd',
    'dhh..........hhd',
    '.dh..........hd.',
    '.dh..........hd.',
    '..d..........d..',
  ],
  // A flame of hair over a widow's peak.
  vegeta: [
    '......d..d......',
    '....d.dhhd.d....',
    '...dhdhHHhdhd...',
    '...dhhhhhhhhd...',
    '....ksshhssk....',
    '....ksessesk....',
    '....kssssssk....',
    '.....kssssk.....',
    ...below(4),
  ],
  vegetaMajin: [
    '......d..d......',
    '....d.dhhd.d....',
    '...dhdhHHhdhd...',
    '...dhhhhhhhhd...',
    '....kssMMssk....',
    '....ksessesk....',
    '....kssssssk....',
    '.....kssssk.....',
    ...below(4),
  ],
  // A kid: lower, smaller hair with one bang.
  gohan: [
    EMPTY,
    '....d.dd..d.....',
    '...dhdhHddhd....',
    '..dhhhhHhhhhd...',
    '...dhssshssd....',
    '...dksesseskd...',
    '....kssssssk....',
    '.....kssssk.....',
    ...below(4),
  ],
  gohanSuper: [
    '....d..d..d.....',
    '..d.dhdhddhd.d..',
    '..dhdhhHhhhdhd..',
    '..dhhhhHhhhhhd..',
    '...dhsssshssd...',
    '...dksesseskd...',
    '....kssssssk....',
    '.....kssssk.....',
    ...below(4),
  ],
}

export type Pose = 'stand' | 'power' | 'thumbs' | 'knocked' | 'meditate' | 'beam'

// Bodies over rows 8-11; two steps of a walk where it moves.
export const BODIES: Record<Pose, readonly (readonly string[])[]> = {
  stand: [
    ['...kTTTAATTTk...', '...RTTTTTTTTR...', '...S.AAAAAA.S...', '.....FF..FF.....'],
    ['...kTTTAATTTk...', '...RTTTTTTTTR...', '...S.AAAAAA.S...', '....FF....FF....'],
  ],
  // Fists clenched at the hips, feet planted wide.
  power: [['...kTTTAATTTk...', '..SRTTTTTTTTRS..', '....PAAAAAAP....', '...FF......FF...']],
  // The raised fist and thumb are drawn beside the face (THUMB).
  thumbs: [['...kTTTAATTTkR..', '...RTTTTTTTTk...', '...S.AAAAAA.....', '.....FF..FF.....']],
  // Flung back, arms out.
  knocked: [['.SRkTTTAATTTkRS.', '...kTTTTTTTTk...', '....PAAAAAAP....', '...FF......FF...']],
  // Sitting cross-legged, hands in the lap: the head sits a row lower.
  meditate: [['..RkTTTAATTTkR..', '..PPPPPSSPPPPP..', '..FFPPPPPPPPFF..']],
  // Both arms pushed forward for a beam: the palms are drawn in front (PALMS).
  beam: [['...kTTTAATTTk...', '...kTTTTTTTTk...', '.....AAAAAA.....', '....FF....FF....']],
}

// Both palms pushed forward at the chest, and where the beam leaves them: the
// text row of the hands, one row thick.
export const PALMS: Palms = {
  pixels: [
    [13, 8, 'R'],
    [13, 9, 'R'],
    [14, 8, 'S'],
    [14, 9, 'S'],
    [15, 8, 'S'],
    [15, 9, 'S'],
  ],
  spot: { x: 15, top: 4, cells: 1 },
}

// The thumbs-up fist, beside the chin: [x, y] pixels.
export const THUMB: readonly (readonly [number, number])[] = [
  [13, 6],
  [12, 7],
  [13, 7],
]

// Where a face's mouth and tear go, in head rows.
export const MOUTH: readonly (readonly [number, number])[] = [
  [7, 6],
  [8, 6],
]
export const TEAR: readonly [number, number] = [6, 6]
