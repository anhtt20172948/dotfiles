# Demo renders

[VHS](https://github.com/charmbracelet/vhs) tapes that record the real
configuration (tmux, Neovim, yazi, lazygit and the Starship prompt) once per
palette, so screenshots can be regenerated whenever the look changes and every
pull request that touches the configuration gets a visual diff to look at.

| Palette | Source | What it stands for |
| --- | --- | --- |
| `mocha` | `.config/kitty/current-theme.conf` | The Catppuccin Mocha fallback (macOS, or Arch before DMS has run). |
| `dms-dark` | `tests/fixtures/palettes/dms-dark.conf` | A dank16 palette DMS derived from a dark wallpaper. |
| `dms-light` | `tests/fixtures/palettes/dms-light.conf` | dank16's light variant of the same wallpaper. |

## What a render does

`render.sh` follows the README's quick start in a scratch `HOME`: a checkout of
`HEAD` on a `main` branch at `~/dotfiles`, linked by `./install.sh`. Neovim's
plugins are restored from `lazy-lock.json`, then Neovim is started once in a
detached tmux pane so Mason and Tree-sitter finish their first-start installs
before anything is recorded (`warmup.lua`). For each palette it then writes
`~/.config/kitty/dank-theme.conf` the way DMS does (nothing for Mocha, which is
the fallback), hands the same colours to VHS as the terminal theme, and plays
every tape in `tapes/`.

`workspace.tape` records one session: tmux window 1 with Neovim beside a
Starship shell, the which-key popup, window 2 with yazi and window 3 with
lazygit. Each palette gets a GIF and four stills:

```
OUT/workspace/<palette>/workspace.gif
OUT/workspace/<palette>/{workspace,which-key,yazi,lazygit}.png
OUT/hero.gif   the workspace still of each palette in turn, labelled
OUT/hero.png   the labelled DMS dark still
OUT/social.png the DMS dark still at GitHub's social preview size (1280x640)
```

The terminal is VHS's (xterm.js in headless Chrome) set up like kitty here: no
window chrome, 10 px padding, the palette's 16 colours. Differences from the
workstation to keep in mind when comparing:

- The font is JetBrainsMono Nerd Font, a FOSS Nerd Font installed only for the
  render. The workstation's patched SFMono Nerd Font Complete may not be
  redistributed, so it cannot be installed in CI.
- No wallpaper or `background_opacity`: surfaces that are transparent on the
  workstation show the palette background.
- xterm.js draws a Nerd Font icon two cells wide even when the next cell is not
  blank, where kitty squeezes it into one, so an icon followed directly by text
  (the `:` after tmux's window icons) overlaps it a little.
- TPM is replaced by a no-op, so tmux plugins (key bindings only) are not
  loaded and the render needs no plugin downloads.
- The tape dismisses the update notice lazy.nvim shows for plugins the lockfile
  keeps behind upstream, and never enters Insert mode in Neovim: that would load
  Supermaven, which registers the machine with its service.

## Running it

```bash
docs/demo/render.sh                 # every palette, into docs/demo/out (gitignored)
docs/demo/render.sh -o /tmp/demo dms-light
```

Needs on `PATH`: `vhs` and `ttyd` (VHS records through them, and finds or
downloads a Chrome), `ffmpeg`, `git`, `tmux`, `python3`, Neovim, `starship`,
`yazi`, `lazygit` and `delta`, and the network for the plugin restore. The
versions CI uses are pinned in [demo.yml](../../.github/workflows/demo.yml).

| Variable | Effect |
| --- | --- |
| `DEMO_FONT_DIR` | A directory of fonts for this render only, through a private fontconfig file. Point it at an unpacked JetBrainsMono Nerd Font to match CI without installing the font. |
| `DEMO_NVIM_DATA` | A persistent Neovim data directory (plugins, Mason packages, parsers) shared between renders. |
| `DEMO_WARMUP_TIMEOUT` | Seconds to wait for the first Neovim start (default 600). |
| `DEMO_KEEP=1` | Keep the scratch directory and print its path. |

## In CI

The [demo workflow](../../.github/workflows/demo.yml) renders every palette on
pull requests and pushes to `main` that touch the configuration, `install.sh`,
this directory or the palette fixtures, and uploads `OUT` as the
`demo-<commit>` artifact. It is a separate, non-blocking workflow: it needs the
network and its job is allowed to fail.

## Updating the README media

`media/hero.gif`, `media/hero.png` and `media/social.png` in this directory come
from a CI render; the README shows the GIF, and `social.png` is the repository's
social preview. When the look changes, download the artifact of the commit that
changed it and copy the three files here:

```bash
gh run download <run-id> --name demo-<commit> --dir /tmp/demo
cp /tmp/demo/hero.gif /tmp/demo/hero.png /tmp/demo/social.png docs/demo/media/
```

GitHub has no API for the social preview: upload `media/social.png` by hand in
the repository's Settings, General, Social preview.
