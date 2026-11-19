// The colours behind every palette key the art uses.
//
// Every channel is 00, 4c, 7f, af, d7 or ff (or the colour is a grey): each sits
// nearest the 256-colour cube level it quantizes to, so Claude Code inside tmux,
// which drops to 256 colours, draws nearly the same fighter as a truecolor terminal.

import type { Technique } from './beam'
import type { Character, Fighter, Form } from './fighter'

export type Palette = Record<string, string>

const SKIN = '#ffd7af'
const BLUE = '#004caf'
const WHITE = '#ffffff'
const PURPLE = '#7f4caf'
const RED = '#af0000'

const COMMON: Palette = {
  k: '#3a3a3a', // outline
  l: '#3a3a3a', // lashes and shut eyes in the large tier, cut out without colour
  c: '#af7f4c', // closed eyes in the small tiers, lighter than open ones
  s: SKIN,
  q: '#d7af7f', // skin in shade
  w: WHITE, // the glint in an eye
  m: '#7f0000', // open mouth
  n: '#af4c4c', // closed mouth
  t: WHITE, // teeth
  p: '#ff7f7f', // blush
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

// T torso, U its shade, A accent, L arm, R sleeve or wristband (the small tiers),
// C wristband or glove cuff (the large tier), S hand, P trousers, F boots.
const OUTFITS: Record<Character, Palette> = {
  // An orange gi over a blue undershirt, belt, wristbands and boots.
  goku: { T: '#ff7f00', U: '#d74c00', A: BLUE, L: SKIN, R: BLUE, C: BLUE, S: SKIN, P: '#ff7f00', F: BLUE },
  // White armour over a blue suit, white gloves and boots.
  vegeta: { T: WHITE, U: '#b2b2b2', A: BLUE, L: BLUE, R: BLUE, C: WHITE, S: WHITE, P: BLUE, F: WHITE },
  // A purple gi with a red sash and wristbands.
  gohan: { T: PURPLE, U: '#4c4c7f', A: RED, L: SKIN, R: RED, C: RED, S: SKIN, P: PURPLE, F: BLUE },
}

// The name beside the pet, in each character's colour.
export const NAME_COLORS: Record<Character, string> = { goku: '#ff7f00', vegeta: '#4c7fff', gohan: '#af7fd7' }

// Each signature beam: its rippling edge (u), the glow inside a thick beam
// (v) and its white-hot core (V). A cooling beam's core turns to its glow.
// Kamehameha is blue, Final Flash yellow, Masenko a deeper gold.
const BEAMS: Record<Technique, Palette> = {
  kamehameha: { u: '#4cafff', v: '#afd7ff', V: WHITE },
  finalFlash: { u: '#ffd700', v: '#ffffaf', V: WHITE },
  masenko: { u: '#ffaf00', v: '#ffd74c', V: '#ffffaf' },
}

// The shout beside a beam, in its colour.
export const BEAM_TEXT_COLORS: Record<Technique, string> = {
  kamehameha: '#4cafff',
  finalFlash: '#ffd700',
  masenko: '#ffaf00',
}

export const beamPalette = (technique: Technique): Palette => BEAMS[technique]

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
  ...Object.values(BEAMS).flatMap(beam => Object.values(beam)),
  ...Object.values(BEAM_TEXT_COLORS),
]

// The form's name in its aura's colour; the base form has none.
export const formColor = (form: Form): string | undefined => FORM_LOOKS[form].aura?.i

export const hasAura = (form: Form) => FORM_LOOKS[form].aura !== undefined

export const hasSparks = (form: Form) => FORM_LOOKS[form].aura?.z !== undefined

export const paletteOf = (fighter: Fighter, form: Form): Palette => {
  const look = FORM_LOOKS[form]

  return { ...COMMON, ...OUTFITS[fighter.character], ...look.hair, e: look.eyes, ...look.aura }
}
