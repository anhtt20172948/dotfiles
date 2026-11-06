# kitty config

Font: `SFMono Nerd Font` (patched, Complete variant for icons), `font_size 9` - see [kitty.conf](kitty.conf).

## Italics

`italic_font` and `bold_italic_font` are `auto`, so italic text uses the SFMono
Nerd Font italic faces. Setting them to `style=Bold` made italics render bold.

## Theme

- `current-theme.conf` (Catppuccin Mocha) is the fallback colour set.
- `globinclude dank-theme.conf` layers the wallpaper colours that DMS generates
  from its matugen template (`dank-theme.conf`) over it. If DMS has not
  generated the file yet, the glob matches nothing and kitty keeps the fallback.
- `dank-tabs.conf` is not included. DMS writes it with tab layout settings
  (edge, style, alignment, title templates) that would override
  [custom-tabs.conf](custom-tabs.conf). The `dank-*.conf` files are per host and
  gitignored.

## Icons

Icons come from the patched SFMono Nerd Font Complete itself. There is no
`symbol_map` override. Earlier versions redirected the Nerd Font v2 code point
ranges to `Symbols Nerd Font Mono`; that was redundant with the Complete font.
