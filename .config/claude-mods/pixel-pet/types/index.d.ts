export type Mood = 'idle' | 'working' | 'happy' | 'sad' | 'sleep'

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
}

declare module 'claude-code' {
  interface PluginState {
    'pixel-pet': { pet: Pet; isHidden: boolean }
  }
}
