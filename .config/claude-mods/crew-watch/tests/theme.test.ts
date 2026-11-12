import { expect, test } from 'claude-code/testing'

import {
  AGENT_BORDERS, DEFAULT_THEME, ENGINE_THEME, HARNESS_STYLES, PALETTES, ROLES, TERMINAL_SLOTS, THEME_NAMES, ansiColor, contrast, isNoColorSet, isThemeName, isTruecolorTerm,
  paneStyles, themePainter, toAnsi256,
} from '../hooks/theme'

const TRUECOLOR = { isNoColor: false, isTruecolor: true }
const HEX = /^#[0-9a-f]{6}$/
const NAMES = Object.keys(PALETTES)
// The themes the Theme option promises, in the order the README lists them.
const PROMISED = ['tokyo-night', 'catppuccin-mocha', 'catppuccin-latte', 'gruvbox-dark', 'gruvbox-light', 'nord', 'dracula', 'solarized-dark', 'solarized-light', 'one-dark']

test('the theme list is the terminal default, the engine theme and every promised palette', () => {
  expect([DEFAULT_THEME, ENGINE_THEME]).toEqual(['default', 'claude-code'])
  expect(THEME_NAMES).toEqual([DEFAULT_THEME, ENGINE_THEME, ...PROMISED])
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

test('the default theme paints each role as a slot of the terminal palette, the same with or without truecolor', () => {
  expect(Object.keys(TERMINAL_SLOTS).sort()).toEqual([...ROLES].sort())
  for (const support of [TRUECOLOR, { isNoColor: false, isTruecolor: false }]) {
    const paint = themePainter(DEFAULT_THEME, support)
    for (const role of ROLES) {
      const slot: number | null = TERMINAL_SLOTS[role]
      expect([role, paint(role)]).toEqual([role, slot === null ? undefined : `ansi256(${slot})`])
    }
    // Text sets no colour: the terminal draws its own foreground.
    expect(paint('text')).toBeUndefined()
    // A role the theme does not name stays the engine key, as in the palettes.
    expect(paint('remember')).toBe('remember')
    expect(paint(undefined)).toBeUndefined()
  }
  expect(ansiColor(0)).toBe('ansi256(0)')
  expect(ansiColor(15)).toBe('ansi256(15)')
  // An unknown theme name falls back to the default rather than painting nothing.
  expect(themePainter('nope', TRUECOLOR)('claude')).toBe(themePainter(DEFAULT_THEME, TRUECOLOR)('claude'))
  for (const role of [...ROLES, 'unknown']) expect(themePainter(DEFAULT_THEME, { isNoColor: true, isTruecolor: true })(role)).toBeUndefined()
})

test('the default theme keeps the ANSI slot contract and the slots neo-tree and yazi use', () => {
  for (const role of ROLES) {
    const slot: number | null = TERMINAL_SLOTS[role]
    if (slot === null) continue
    expect([role, Number.isInteger(slot) && slot >= 0 && slot <= 15]).toEqual([role, true])
    // ANSI 0 is the background, 5 a dark container tone and 8 the border tone in DMS's palette: never text.
    if (role !== 'border') expect([role, [0, 5, 8].includes(slot)]).toEqual([role, false])
  }
  // Borders, rules and tracks are the border tone, as tmux's and fzf's borders.
  expect(TERMINAL_SLOTS.border).toBe(8)
  // Metadata is gray (7), fzf's info and yazi's gray; text the terminal's foreground, fzf's fg:-1.
  expect([TERMINAL_SLOTS.text, TERMINAL_SLOTS.subtle]).toEqual([null, 7])
  // neo-tree and yazi (tree_colors.lua, theme.toml): orange icons are yellow (3), folders blue (4),
  // purple icons bright magenta (13). Claude amber, Codex blue and merged purple take the same slots.
  expect([TERMINAL_SLOTS.claude, TERMINAL_SLOTS.codex, TERMINAL_SLOTS.merged]).toEqual([3, 4, 13])
  expect([TERMINAL_SLOTS.success, TERMINAL_SLOTS.error]).toEqual([2, 1])
  // Every text role except purple keeps to slots 1-7, which read on a light DMS palette too.
  for (const role of ROLES) {
    const slot: number | null = TERMINAL_SLOTS[role]
    if (slot !== null && role !== 'border' && role !== 'merged') expect([role, slot <= 7]).toEqual([role, true])
  }
})

test('the claude-code theme leaves the engine keys alone', () => {
  const paint = themePainter(ENGINE_THEME, TRUECOLOR)
  for (const key of ['text', 'subtle', 'success', 'warning', 'error', 'merged', 'permission', 'suggestion', 'claude']) expect(paint(key)).toBe(key)
  // The engine has no border key: the log box keeps the colour it had.
  expect(paint('border')).toBe('subtle')
  expect(paint(undefined)).toBeUndefined()
  // NO_COLOR is the engine's to honour for its own keys.
  expect(themePainter(ENGINE_THEME, { isNoColor: true, isTruecolor: true })('claude')).toBe('claude')
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

test('shared pane styles resolve through every theme and terminal colour mode', () => {
  for (const name of THEME_NAMES) {
    for (const support of [TRUECOLOR, { isNoColor: false, isTruecolor: false }, { isNoColor: true, isTruecolor: true }]) {
      const paint = themePainter(name, support)
      expect(paneStyles(paint)).toEqual({
        frame: { borderStyle: 'round', borderColor: paint('border'), borderDimColor: false },
        title: { color: paint('text'), weight: 'bold' },
        meta: { color: paint('subtle'), weight: 'regular' },
        rule: { color: paint('border'), weight: 'regular' },
      })
    }
  }
  expect(themePainter(ENGINE_THEME, TRUECOLOR)('codex')).toBe('permission')
  expect(themePainter(DEFAULT_THEME, TRUECOLOR)('codex')).toBe('ansi256(4)')
})

test('agent borders carry no colour of their own: the harness gives it, the state only how loud', () => {
  expect(AGENT_BORDERS).toEqual({
    running: { dim: false, isRunning: true },
    blocked: { dim: false, isRunning: false },
    calm: { dim: true, isRunning: false },
  })
  // Claude and Codex borders, tags and names read apart in every palette, and neither is the error red.
  for (const name of NAMES) {
    const { colors } = PALETTES[name as keyof typeof PALETTES]
    const [claude, codex] = [colors[HARNESS_STYLES.claude.role], colors[HARNESS_STYLES.codex.role]]
    expect(`${name} ${claude !== codex && claude !== colors.error && codex !== colors.error}`).toBe(`${name} true`)
  }
  const harnesses = (theme: string) => {
    const paint = themePainter(theme, TRUECOLOR)
    return [paint(HARNESS_STYLES.claude.role), paint(HARNESS_STYLES.codex.role), paint(HARNESS_STYLES.other.role), paint('error')]
  }
  expect(harnesses(ENGINE_THEME)).toEqual(['claude', 'permission', 'text', 'error'])
  // Claude yellow, Codex blue, other harnesses the terminal foreground, blocked red: four apart.
  expect(harnesses(DEFAULT_THEME)).toEqual(['ansi256(3)', 'ansi256(4)', undefined, 'ansi256(1)'])
})
