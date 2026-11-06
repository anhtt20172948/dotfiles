# kitty config

Font: `SFMono Nerd Font` (patched, Complete variant for icons), `font_size 9` - see [kitty.conf](kitty.conf).

## Italics

`italic_font` and `bold_italic_font` are `auto`, so italic text uses the SFMono
Nerd Font italic faces. Setting them to `style=Bold` made italics render bold.

## Theme

Include order in [kitty.conf](kitty.conf), later files win:

1. `current-theme.conf` - fallback terminal colours (Catppuccin Mocha).
2. [custom-tabs-colors.conf](custom-tabs-colors.conf) - fallback tab bar colours.
3. `globinclude dank-theme.conf` - wallpaper terminal colours from DMS.
4. `globinclude dank-tabs.conf` - wallpaper tab bar colours from DMS.
5. [custom-tabs.conf](custom-tabs.conf) - tab bar layout only (edge, style,
   alignment, margins, title templates). It is last so the layout DMS writes
   into `dank-tabs.conf` never overrides it.

If DMS has not generated a `dank-*.conf` file yet, its glob matches nothing and
kitty keeps the fallback colours. The `dank-*.conf` files are per host and
gitignored.

## Icons

Icons come from the patched SFMono Nerd Font Complete itself. There is no
`symbol_map` override. Earlier versions redirected the Nerd Font v2 code point
ranges to `Symbols Nerd Font Mono`; that was redundant with the Complete font.
