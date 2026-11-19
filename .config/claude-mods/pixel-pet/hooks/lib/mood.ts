import type { Mood, Pet } from '../../types'
import type { Look } from './sprite'

export const TICK_MS = 400
export const REACT_MS = 4_000
export const SLEEP_MS = 3 * 60_000
// How far the pet walks while idle, in columns.
export const ROAM = 10

export type PetEvent =
  | { type: 'start'; now: number }
  | { type: 'tick'; now: number }
  | { type: 'prompt'; now: number }
  | { type: 'tool'; now: number; tool: string }
  | { type: 'toolDone'; now: number; tool: string; isError: boolean }
  | { type: 'turn'; now: number; isAborted: boolean }

export const INITIAL: Pet = {
  mood: 'idle',
  tool: null,
  since: 0,
  tick: 0,
  x: 0,
  dir: 1,
  turns: 0,
  tools: 0,
  errors: 0,
}

const become = (pet: Pet, mood: Mood, now: number, tool: string | null = null): Pet => ({
  ...pet,
  mood,
  tool,
  since: now,
})

// Idle time is spent walking ten ticks out of every sixteen, then sitting.
const walk = (pet: Pet): Pet => {
  if (pet.tick % 16 >= 10 || pet.tick % 2 === 1) {
    return pet
  }
  const x = pet.x + pet.dir
  const dir = x <= 0 ? 1 : x >= ROAM ? -1 : pet.dir

  return { ...pet, x: Math.max(0, Math.min(ROAM, x)), dir }
}

const tick = (pet: Pet, now: number): Pet => {
  const next = { ...pet, tick: pet.tick + 1 }
  const age = now - pet.since
  if ((pet.mood === 'happy' || pet.mood === 'sad') && age >= REACT_MS) {
    return become(next, 'idle', now)
  }
  if (pet.mood === 'idle' && age >= SLEEP_MS) {
    return become(next, 'sleep', now)
  }

  return pet.mood === 'idle' ? walk(next) : next
}

export const step = (pet: Pet, event: PetEvent): Pet => {
  switch (event.type) {
    case 'start':
      return become(pet, 'idle', event.now)
    case 'tick':
      return tick(pet, event.now)
    case 'prompt':
      return become(pet, 'working', event.now)
    case 'tool':
      return { ...become(pet, 'working', event.now, event.tool), tools: pet.tools + 1 }
    case 'toolDone':
      return event.isError
        ? { ...become(pet, 'sad', event.now, event.tool), errors: pet.errors + 1 }
        : { ...pet, tool: null }
    case 'turn':
      return { ...become(pet, event.isAborted ? 'sad' : 'happy', event.now), turns: pet.turns + 1 }
  }
}

// What shows: a turn still running wins over a calm mood, and a stale working
// mood (a turn that ended without telling) gives way to idle.
export const shownMood = (pet: Pet, isWorking: boolean): Mood => {
  if (isWorking && (pet.mood === 'idle' || pet.mood === 'sleep')) {
    return 'working'
  }
  if (!isWorking && pet.mood === 'working') {
    return 'idle'
  }

  return pet.mood
}

// Idle it walks and blinks with a calm aura; working it powers up, the aura
// flaring; a finished turn gets a thumbs up; a failure knocks it back out of
// its form; a long idle sends it to meditate.
export const look = (mood: Mood, tick: number): Look => {
  const step = (tick % 2) as 0 | 1
  const calm = { hasMouth: false, hasTear: false, isPoweredDown: false }
  switch (mood) {
    case 'idle': {
      const isBlinking = tick % 12 === 0
      const walking = tick % 16 < 10 ? step : 0
      const face = isBlinking ? 'blink' : 'idle'

      return { ...calm, pose: 'stand', step: walking, face, isEyesClosed: isBlinking, aura: 'calm' }
    }
    case 'working':
      return { ...calm, pose: 'power', step, face: 'power', isEyesClosed: false, hasMouth: true, aura: 'flare' }
    case 'happy':
      return { ...calm, pose: 'thumbs', step: 0, face: 'happy', isEyesClosed: true, hasMouth: true, aura: 'calm' }
    case 'sad':
      return {
        ...calm,
        pose: 'knocked',
        step: 0,
        face: 'hurt',
        isEyesClosed: true,
        hasTear: true,
        isPoweredDown: true,
        aura: 'none',
      }
    case 'sleep':
      return { ...calm, pose: 'meditate', step: 0, face: 'calm', isEyesClosed: true, aura: 'none' }
  }
}

export type Tone = 'dim' | 'cheer' | 'warn'

export const caption = (mood: Mood, pet: Pet): { text: string; tone: Tone } => {
  const dots = '.'.repeat((pet.tick % 3) + 1)
  switch (mood) {
    case 'idle':
      return { text: 'waiting for you', tone: 'dim' }
    case 'working':
      return { text: pet.tool === null ? `powering up${dots}` : `running ${pet.tool}${dots}`, tone: 'dim' }
    case 'happy':
      return { text: 'done!', tone: 'cheer' }
    case 'sad':
      return { text: pet.tool === null ? 'interrupted…' : `${pet.tool} failed…`, tone: 'warn' }
    case 'sleep':
      return { text: 'zZz'.slice(0, (pet.tick % 3) + 1), tone: 'dim' }
  }
}

const count = (n: number, noun: string) => `${n} ${noun}${n === 1 ? '' : 's'}`

export const stats = (pet: Pet) =>
  [
    count(pet.turns, 'turn'),
    count(pet.tools, 'tool'),
    ...(pet.errors > 0 ? [count(pet.errors, 'error')] : []),
  ].join(' · ')
