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

export const look = (mood: Mood, tick: number): Look => {
  const step = (tick % 2) as 0 | 1
  switch (mood) {
    case 'idle':
      return { isBlinking: tick % 12 === 0, hasBlush: false, hasTear: false, step: tick % 16 < 10 ? step : 0 }
    case 'working':
      return { isBlinking: false, hasBlush: false, hasTear: false, step }
    case 'happy':
      return { isBlinking: true, hasBlush: true, hasTear: false, step }
    case 'sad':
      return { isBlinking: false, hasBlush: false, hasTear: true, step: 0 }
    case 'sleep':
      return { isBlinking: true, hasBlush: false, hasTear: false, step: 0 }
  }
}

export type Tone = 'dim' | 'love' | 'warn'

export const caption = (mood: Mood, pet: Pet): { text: string; tone: Tone } => {
  const dots = '.'.repeat((pet.tick % 3) + 1)
  switch (mood) {
    case 'idle':
      return { text: 'đang chờ bạn', tone: 'dim' }
    case 'working':
      return { text: pet.tool === null ? `đang nghĩ${dots}` : `đang chạy ${pet.tool}${dots}`, tone: 'dim' }
    case 'happy':
      return { text: `xong rồi! ${pet.tick % 2 === 0 ? '♥' : '♥ ♥'}`, tone: 'love' }
    case 'sad':
      return { text: pet.tool === null ? 'bị ngắt rồi…' : `${pet.tool} lỗi rồi…`, tone: 'warn' }
    case 'sleep':
      return { text: 'zZz'.slice(0, (pet.tick % 3) + 1), tone: 'dim' }
  }
}

export const stats = (pet: Pet) =>
  [`${pet.turns} lượt`, `${pet.tools} tool`, ...(pet.errors > 0 ? [`${pet.errors} lỗi`] : [])].join(' · ')
