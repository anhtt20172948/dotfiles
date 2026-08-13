# kitty config

Font: `SFMono Nerd Font` (patched), `font_size 9` — see [kitty.conf](kitty.conf).

## Making Nerd Font icons larger — `symbol_map` to Symbols Nerd Font Mono

### Problem
All glyphs render small relative to the text — both folder icons (mini.icons in
neo-tree) and file icons (nvim-web-devicons: docker, ts, json, …).

Cause: the **patched SFMono Nerd Font** draws icon glyphs — especially the
Material Design Icons in the **U+F0000+** range (e.g. the folder glyph `󰉋` =
U+F024B) — scaled down to match SF Mono's x-height, so they look tiny.

kitty 0.48 has **no per-glyph scale option** (`modify_font` only adjusts
cell_width / cell_height / baseline / underline / strikethrough, not glyph size).

### Solution
Redirect the Nerd Font codepoint ranges to the standalone **Symbols Nerd Font
Mono**. That font draws its glyphs to fill the cell, so the icons come out larger
and more consistent while the **SF Mono text keeps its size**.

**1. Install the standalone font** (Arch `extra` repo):

```bash
sudo pacman -S --needed ttf-nerd-fonts-symbols-mono
fc-list | grep -i "Symbols Nerd Font Mono"   # confirm it is installed
```

**2. `symbol_map` in [kitty.conf](kitty.conf)** (already configured):

```conf
symbol_map U+E0A0-U+E0D4 Symbols Nerd Font Mono
symbol_map U+E200-U+E2A9 Symbols Nerd Font Mono
symbol_map U+E300-U+E3E3 Symbols Nerd Font Mono
symbol_map U+E5FA-U+E6B7 Symbols Nerd Font Mono
symbol_map U+E700-U+E8EF Symbols Nerd Font Mono
symbol_map U+EA60-U+EBEB Symbols Nerd Font Mono
symbol_map U+F000-U+F2FF Symbols Nerd Font Mono
symbol_map U+F300-U+F381 Symbols Nerd Font Mono
symbol_map U+F400-U+F533 Symbols Nerd Font Mono
symbol_map U+F0001-U+F1AF0 Symbols Nerd Font Mono
```

The `U+F0001-U+F1AF0` range is Material Design Icons (used by mini.icons for
neo-tree folder icons). The other ranges cover devicons / seti / codicons /
octicons / font-awesome / powerline (nvim-web-devicons).

**3. Reload:** press `ctrl+shift+f5` in kitty, or open a new window.

### Tuning
- Icons still a little small → add `modify_font cell_height 110%`, or bump
  `font_size` from 9 to 10.
- A glyph shows as a tofu box (the standalone font lacks it) → drop the matching
  range from `symbol_map` so it falls back to SFMono.

### Note
`symbol_map` only **changes the font** for a range; it does not scale glyphs
beyond the cell. The "larger" look comes from the standalone font drawing its
glyphs bigger within the same cell than the patched SFMono build does.
