import { expect, test } from 'claude-code/testing'

import { DEFAULT_THEME, PALETTES, ROLES, THEME_NAMES, contrast, isNoColorSet, isThemeName, isTruecolorTerm, themePainter, toAnsi256 } from '../hooks/theme'

const TRUECOLOR = { isNoColor: false, isTruecolor: true }
const HEX = /^#[0-9a-f]{6}$/
const NAMES = Object.keys(PALETTES)
// The themes the Theme option promises, in the order the README lists them.
const PROMISED = ['tokyo-night', 'catppuccin-mocha', 'catppuccin-latte', 'gruvbox-dark', 'gruvbox-light', 'nord', 'dracula', 'solarized-dark', 'solarized-light', 'one-dark']

test('the theme list is the default plus every promised palette', () => {
  expect(THEME_NAMES).toEqual([DEFAULT_THEME, ...PROMISED])
  expect(NAMES).toEqual(PROMISED)
})

test('every theme defines a valid colour for every role, and nothing else', () => {
  for (const name of NAMES) {
    const palette = PALETTES[name as keyof typeof PALETTES]
    expect(Object.keys(palette.colors).sort()).toEqual([...ROLES].sort())
    for (const role of ROLES) expect(palette.colors[role]).toMatch(HEX)
    expect(palette.background).toMatch(HEX)
    expect(['dark', 'light']).toContain(palette.mode)
  }
})

test('every role stays legible on its own palette background', () => {
  for (const name of NAMES) {
    const { colors, background } = PALETTES[name as keyof typeof PALETTES]
    for (const role of ROLES) {
      const minimum = role === 'text' || role === 'subtle' ? 4.5 : role === 'border' ? 2 : 3
      expect(`${name}.${role} ${contrast(colors[role], background) >= minimum}`).toBe(`${name}.${role} true`)
    }
  }
})

test('light palettes sit on light backgrounds and dark palettes on dark ones', () => {
  const light = NAMES.filter(name => PALETTES[name as keyof typeof PALETTES].mode === 'light')
  expect(light).toEqual(['catppuccin-latte', 'gruvbox-light', 'solarized-light'])
  for (const name of NAMES) {
    const { mode, background, colors } = PALETTES[name as keyof typeof PALETTES]
    expect(contrast(background, '#ffffff') < contrast(background, '#000000')).toBe(mode === 'light')
    // Text reads against the background, so text is the far end of the scale from it.
    expect(contrast(colors.text, background) > contrast(colors.subtle, background)).toBe(true)
  }
})

test('selecting a theme paints each role from its palette', () => {
  for (const name of NAMES) {
    const paint = themePainter(name, TRUECOLOR)
    for (const role of ROLES) expect(paint(role)).toBe(PALETTES[name as keyof typeof PALETTES].colors[role])
  }
  expect(isThemeName('nord')).toBe(true)
  expect(isThemeName('nope')).toBe(false)
  expect(isThemeName('constructor')).toBe(false)
})

test('the default theme leaves the engine keys alone', () => {
  const paint = themePainter(DEFAULT_THEME, TRUECOLOR)
  for (const key of ['text', 'subtle', 'success', 'warning', 'error', 'merged', 'permission', 'suggestion', 'claude']) expect(paint(key)).toBe(key)
  // The engine has no border key: the log box keeps the colour it had.
  expect(paint('border')).toBe('subtle')
  expect(paint(undefined)).toBeUndefined()
  // An unknown theme name falls back to the default rather than painting nothing.
  expect(themePainter('nope', TRUECOLOR)('claude')).toBe('claude')
  // NO_COLOR is the engine's to honour for its own keys.
  expect(themePainter(DEFAULT_THEME, { isNoColor: true, isTruecolor: true })('claude')).toBe('claude')
})

test('NO_COLOR draws no colour at all in a palette theme', () => {
  for (const name of NAMES) {
    const paint = themePainter(name, { isNoColor: true, isTruecolor: true })
    for (const role of [...ROLES, 'claude', 'unknown']) expect(paint(role)).toBeUndefined()
  }
  expect(isNoColorSet(undefined)).toBe(false)
  expect(isNoColorSet('')).toBe(false)
  expect(isNoColorSet('1')).toBe(true)
})

test('a terminal without truecolor gets the nearest 256-colour index', () => {
  expect(isTruecolorTerm('truecolor')).toBe(true)
  expect(isTruecolorTerm('24bit')).toBe(true)
  expect(isTruecolorTerm(undefined)).toBe(false)
  expect(isTruecolorTerm('')).toBe(false)
  expect(toAnsi256('#000000')).toBe(16)
  expect(toAnsi256('#ffffff')).toBe(231)
  expect(toAnsi256('#ff0000')).toBe(196)
  expect(toAnsi256('#808080')).toBe(244)
  for (const name of NAMES) {
    const paint = themePainter(name, { isNoColor: false, isTruecolor: false })
    for (const role of ROLES) {
      const painted = paint(role) ?? ''
      expect(painted).toMatch(/^ansi256\((\d+)\)$/)
      const index = Number(/\((\d+)\)/.exec(painted)?.[1])
      expect(index >= 16 && index <= 255).toBe(true)
    }
  }
})
