/**
 * Colour themes for the dashboard. Pure data and pure functions: no engine calls.
 *
 * The dashboard names colours by semantic role (the engine's own theme keys).
 * The `default` theme leaves those keys alone, so the pane follows the person's
 * Claude Code theme. Every other theme maps each role to one hex colour of a
 * well-known palette, defined once below. A theme only changes colours: no
 * layout, width, truncation or text.
 *
 * Gauges (▰▱) are glyphs inside a line of text, so a gauge takes its line's
 * role colour; there is no separate gauge colour to define.
 */

/** The semantic roles the dashboard paints with; the first nine are engine theme keys. */
export const ROLES = ['text', 'subtle', 'success', 'warning', 'error', 'merged', 'permission', 'suggestion', 'claude', 'border'] as const
export type Role = (typeof ROLES)[number]

export type Palette = {
  /** Terminal background the palette is designed for: a light palette is for light terminals. */
  mode: 'dark' | 'light'
  /** The palette's own background; only used to check contrast, never drawn. */
  background: string
  colors: Record<Role, string>
}

export const DEFAULT_THEME = 'default'

export const PALETTES = {
  'tokyo-night': {
    mode: 'dark', background: '#1a1b26',
    colors: { text: '#c0caf5', subtle: '#8089b3', success: '#9ece6a', warning: '#e0af68', error: '#f7768e', merged: '#bb9af7', permission: '#7aa2f7', suggestion: '#7dcfff', claude: '#ff9e64', border: '#565f89' },
  },
  'catppuccin-mocha': {
    mode: 'dark', background: '#1e1e2e',
    colors: { text: '#cdd6f4', subtle: '#9399b2', success: '#a6e3a1', warning: '#f9e2af', error: '#f38ba8', merged: '#cba6f7', permission: '#89b4fa', suggestion: '#89dceb', claude: '#fab387', border: '#6c7086' },
  },
  'catppuccin-latte': {
    mode: 'light', background: '#eff1f5',
    colors: { text: '#4c4f69', subtle: '#666a80', success: '#2f7a1f', warning: '#a15c07', error: '#d20f39', merged: '#8839ef', permission: '#1e66f5', suggestion: '#127a80', claude: '#c44a00', border: '#8c8fa1' },
  },
  'gruvbox-dark': {
    mode: 'dark', background: '#282828',
    colors: { text: '#ebdbb2', subtle: '#a89984', success: '#b8bb26', warning: '#fabd2f', error: '#fb4934', merged: '#d3869b', permission: '#83a598', suggestion: '#8ec07c', claude: '#fe8019', border: '#7c6f64' },
  },
  'gruvbox-light': {
    mode: 'light', background: '#fbf1c7',
    colors: { text: '#3c3836', subtle: '#665c54', success: '#79740e', warning: '#b57614', error: '#9d0006', merged: '#8f3f71', permission: '#076678', suggestion: '#427b58', claude: '#af3a03', border: '#928374' },
  },
  nord: {
    mode: 'dark', background: '#2e3440',
    colors: { text: '#d8dee9', subtle: '#9aa5bd', success: '#a3be8c', warning: '#ebcb8b', error: '#d57780', merged: '#b48ead', permission: '#81a1c1', suggestion: '#88c0d0', claude: '#d08770', border: '#5c677d' },
  },
  dracula: {
    mode: 'dark', background: '#282a36',
    colors: { text: '#f8f8f2', subtle: '#9aa5d6', success: '#50fa7b', warning: '#f1fa8c', error: '#ff5555', merged: '#bd93f9', permission: '#ff79c6', suggestion: '#8be9fd', claude: '#ffb86c', border: '#6272a4' },
  },
  'solarized-dark': {
    mode: 'dark', background: '#002b36',
    colors: { text: '#93a1a1', subtle: '#839496', success: '#859900', warning: '#b58900', error: '#e8504d', merged: '#8087d6', permission: '#268bd2', suggestion: '#2aa198', claude: '#e05a1e', border: '#586e75' },
  },
  'solarized-light': {
    mode: 'light', background: '#fdf6e3',
    colors: { text: '#465d65', subtle: '#586e76', success: '#657a00', warning: '#8f6c00', error: '#c9211e', merged: '#5a60b3', permission: '#1f78b8', suggestion: '#1e7d76', claude: '#b5400f', border: '#93a1a1' },
  },
  'one-dark': {
    mode: 'dark', background: '#282c34',
    colors: { text: '#abb2bf', subtle: '#8d94a3', success: '#98c379', warning: '#e5c07b', error: '#e06c75', merged: '#c678dd', permission: '#61afef', suggestion: '#56b6c2', claude: '#d19a66', border: '#5c6370' },
  },
} satisfies Record<string, Palette>

export type ThemeName = typeof DEFAULT_THEME | keyof typeof PALETTES

export const THEME_NAMES: readonly string[] = [DEFAULT_THEME, ...Object.keys(PALETTES)]

export const isThemeName = (name: string): name is ThemeName => THEME_NAMES.includes(name)

/** What the terminal can draw; read from NO_COLOR and COLORTERM by the caller. */
export type ColorSupport = { isNoColor: boolean; isTruecolor: boolean }

/** The `COLORTERM` values that promise 24-bit colour. */
export const isTruecolorTerm = (colorterm: string | undefined): boolean => /^(truecolor|24bit)$/i.test((colorterm ?? '').trim())

/** NO_COLOR counts when set to any non-empty value (no-color.org). */
export const isNoColorSet = (value: string | undefined): boolean => (value ?? '') !== ''

type Rgb = readonly [number, number, number]

const channels = (hex: string): Rgb => {
  const n = Number.parseInt(hex.slice(1), 16)
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255]
}

const CUBE_STEPS = [0, 95, 135, 175, 215, 255] as const

const squaredDistance = (a: Rgb, b: Rgb): number => (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2

/** Nearest xterm-256 colour: the 6x6x6 cube or the 24-step grey ramp, whichever is closer. */
export const toAnsi256 = (hex: string): number => {
  const rgb = channels(hex)
  const level = (v: number): number => (v < 48 ? 0 : v < 115 ? 1 : Math.floor((v - 35) / 40))
  const [ri, gi, bi] = [level(rgb[0]), level(rgb[1]), level(rgb[2])]
  const cube: Rgb = [CUBE_STEPS[ri] ?? 0, CUBE_STEPS[gi] ?? 0, CUBE_STEPS[bi] ?? 0]
  const grey = Math.min(23, Math.max(0, Math.round((rgb[0] + rgb[1] + rgb[2]) / 30 - 0.8)))
  const greyValue = 8 + grey * 10
  return squaredDistance(rgb, [greyValue, greyValue, greyValue]) < squaredDistance(rgb, cube) ? 232 + grey : 16 + 36 * ri + 6 * gi + bi
}

/**
 * Resolves a role the dashboard asks for into the colour prop to draw with:
 * the key itself (default theme), a hex colour, an `ansi256(n)` colour where
 * the terminal lacks truecolor, or undefined under NO_COLOR.
 */
export type Paint = (role: string | undefined) => string | undefined

export const themePainter = (name: string, support: ColorSupport): Paint => {
  // The engine has no border key: the default theme keeps the log box's old colour.
  if (!isThemeName(name) || name === DEFAULT_THEME) return role => (role === 'border' ? 'subtle' : role)
  const { colors } = PALETTES[name]
  return role => {
    if (support.isNoColor) return undefined
    const hex = role !== undefined && Object.hasOwn(colors, role) ? colors[role as Role] : undefined
    if (hex === undefined) return role
    return support.isTruecolor ? hex : `ansi256(${toAnsi256(hex)})`
  }
}

const linear = (v: number): number => {
  const s = v / 255
  return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4
}

const luminance = (hex: string): number => {
  const [r, g, b] = channels(hex)
  return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
}

/** WCAG contrast ratio of two hex colours, 1 to 21. */
export const contrast = (a: string, b: string): number => {
  const [x, y] = [luminance(a), luminance(b)]
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05)
}
