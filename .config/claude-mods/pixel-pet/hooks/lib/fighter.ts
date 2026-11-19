// Who the pet is: the session's model picks the character and its effort
// level picks the transformation.

import type { Power } from '../../types'

export type Character = 'goku' | 'vegeta' | 'gohan'

export type Level = NonNullable<Power['effort']>

export type Form = 'base' | 'ssj1' | 'ssj2' | 'ssj3' | 'majin' | 'ui' | 'ego' | 'ultimate' | 'beast'

export type Fighter = { character: Character; form: Form }

export const LEVELS: readonly Level[] = ['low', 'medium', 'high', 'xhigh', 'max']

export const CHARACTERS: readonly Character[] = ['goku', 'vegeta', 'gohan']

export const NAMES: Record<Character, string> = { goku: 'Goku', vegeta: 'Vegeta', gohan: 'Gohan' }

export const FORMS: Record<Character, Record<Level, Form>> = {
  goku: { low: 'base', medium: 'ssj1', high: 'ssj2', xhigh: 'ssj3', max: 'ui' },
  vegeta: { low: 'base', medium: 'ssj1', high: 'ssj2', xhigh: 'majin', max: 'ego' },
  gohan: { low: 'base', medium: 'ssj1', high: 'ssj2', xhigh: 'ultimate', max: 'beast' },
}

export const FORM_NAMES: Record<Form, string> = {
  base: 'Base form',
  ssj1: 'Super Saiyan',
  ssj2: 'Super Saiyan 2',
  ssj3: 'Super Saiyan 3',
  majin: 'Majin',
  ui: 'Ultra Instinct',
  ego: 'Ultra Ego',
  ultimate: 'Ultimate',
  beast: 'Beast',
}

// Opus is Goku, Sonnet Vegeta, and Haiku or any other model kid Gohan. The
// model may be an id (`claude-opus-5-5[1m]`), an alias (`opus`) or a label
// (`Opus 5.5`).
export const characterFor = (model: string | null): Character => {
  if (model === null) {
    return 'gohan'
  }
  if (/opus/i.test(model)) {
    return 'goku'
  }

  return /sonnet/i.test(model) ? 'vegeta' : 'gohan'
}

// A level as the engine or settings spell it; anything else (a number, `auto`,
// `unset`, nothing) is no level.
export const levelOf = (value: unknown): Level | null =>
  typeof value === 'string' && (LEVELS as readonly string[]).includes(value.trim().toLowerCase())
    ? (value.trim().toLowerCase() as Level)
    : null

// A model that takes no effort stays in its base form.
export const fighterFor = (model: string | null, effort: Level | null, choice: Character | null = null): Fighter => {
  const character = choice ?? characterFor(model)

  return { character, form: effort === null ? 'base' : FORMS[character][effort] }
}

// The Character row of /config: `auto` (or anything it does not list) follows the model.
export const characterChoice = (value: unknown): Character | null =>
  typeof value === 'string' && (CHARACTERS as readonly string[]).includes(value) ? (value as Character) : null

const MULTIPLIERS: Record<Form, number> = {
  base: 1,
  ssj1: 50,
  ssj2: 100,
  ssj3: 400,
  majin: 150,
  ui: 1_000,
  ego: 1_000,
  ultimate: 300,
  beast: 1_200,
}

// Training raises it: every finished turn and tool call counts, every error costs.
export const powerLevel = (form: Form, counts: { turns: number; tools: number; errors: number }) =>
  Math.max(1, 100 + counts.turns * 50 + counts.tools * 10 - counts.errors * 25) * MULTIPLIERS[form]

export const formatPower = (power: number) => `power ${power.toLocaleString('en-US')}${power > 9_000 ? '!' : ''}`
