export type Mood = 'idle' | 'working' | 'attack' | 'happy' | 'sad' | 'sleep'

// A signature beam fired when a turn ends: how long it has run, and the power
// milestone it celebrates (a bigger beam), or null.
export type Attack = {
  elapsed: number
  milestone: number | null
}

export type Pet = {
  mood: Mood
  // The tool running or the one that just failed; null between tools.
  tool: string | null
  // When the mood last changed, in clock milliseconds.
  since: number
  tick: number
  // Columns walked from the left edge, and the way the pet faces.
  x: number
  dir: 1 | -1
  turns: number
  tools: number
  errors: number
  // The beam being fired while the mood is 'attack'; null otherwise.
  attack: Attack | null
  // The highest power milestone a finished turn has reached; null before the first.
  milestone: number | null
}

// What the main conversation runs on: the model picks the character and the
// effort level its form. Null until known; a model without effort has none.
export type Power = {
  model: string | null
  effort: 'low' | 'medium' | 'high' | 'xhigh' | 'max' | null
}

declare module 'claude-code' {
  interface PluginState {
    'pixel-pet': { pet: Pet; isHidden: boolean; power: Power }
  }
}
