# dotfiles

[![ci](https://github.com/anhtt20172948/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/anhtt20172948/dotfiles/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

![One tmux session with Neovim beside a Starship shell, shown under the Catppuccin Mocha fallback palette, then a DMS palette from a dark wallpaper, then one from a light wallpaper](docs/demo/media/hero.gif)

<sub>The same session under the Mocha fallback and two DMS palettes, rendered in
CI from the palette fixtures ([docs/demo](docs/demo/README.md)).</sub>

An Arch Linux + Hyprland workstation whose colours come from the wallpaper and
follow you everywhere. DMS derives a palette from the wallpaper, kitty applies
it, and tmux, Neovim, yazi, lazygit and the rest follow it, including Neovim on
remote servers over SSH. Neovim keeps every text colour at WCAG 4.5:1 contrast
against the real background. The same configuration runs on macOS (with a
Catppuccin Mocha fallback palette) and on Linux servers provisioned by the
[workflow](https://github.com/anhtt20172948/workflow) repository, and CI tests
it on Ubuntu, Arch Linux and stock macOS.

## Design principles

- **One palette source.** kitty's active palette is the only place colours are
  defined: DMS writes it from the wallpaper on Arch, and macOS uses the
  Catppuccin Mocha fallback. Every other tool uses ANSI colour names, so a new
  wallpaper re-themes everything without editing a config. A slot contract
  keeps those names readable on any wallpaper (see
  [The ANSI slot contract](#the-ansi-slot-contract)), and the palette tests
  reject hex colours, truecolor escapes and forbidden slots in active
  configuration.
- **Transparent surfaces.** Neovim (including sidebars, status lines and
  popups), tmux's status bar and btop draw no background of their own, so
  kitty's `background_opacity 0.8` and the wallpaper show through; borders
  carry the structure.
- **One accent, one shape.** Cyan (ANSI 6, which DMS fills with its primary
  colour) is the only marker of what is active: the kitty tab, the tmux session
  pill, current window and pane border, the fzf pointer, yazi's hovered row,
  Neovim's borders and the prompt's directory. Pills and tabs share lualine's
  slanted caps, and kitty's tab bar appears only with two or more tabs.
- **One prompt on every host.** [.config/starship.toml](.config/starship.toml)
  is the Starship prompt for bash and zsh, in ANSI names with the same accent
  and caps; `starship-plain.toml` is its ASCII twin for terminals without a
  Nerd Font (`STARSHIP_CONFIG=~/.config/starship-plain.toml`).
- **Readable by construction.** Neovim computes every text colour, file icons
  included, to at least 4.5:1 contrast against the actual background
  (`tests/nvim_visual.lua`, `tests/nvim_icons.lua`, `tests/nvim_lualine.lua`).
  Every ANSI slot another tool uses as text is checked at 4.5:1 against
  Catppuccin Mocha and recorded DMS dark and light palettes
  (`tests/palette_contract.py`), and Hyprland picks its group bar title colours
  for contrast against the tab colours DMS sets.
- **The palette travels.** The local shell exports the palette and SSH forwards
  it; a watcher pushes it to servers on every theme change. Remote Neovim reads
  it without a reconnect, and ANSI-only tools follow automatically because the
  local kitty renders them.
- **Links, not copies; no root.** `install.sh` symlinks only git-tracked files,
  moves conflicts to a backup instead of deleting them, and is safe to re-run.
  Tool installs and shell rc files belong to workflow, not to this repository.

## How the palette flows

```mermaid
flowchart LR
  wallpaper[Wallpaper] --> dms["DMS + matugen"]
  dms --> hypr["Hyprland colours"]
  dms --> palette["kitty palette<br/>dank-theme.conf<br/>(Mocha fallback on macOS)"]
  palette -- "16 ANSI colours" --> tuis["tmux, Starship, fzf, bat, delta,<br/>yazi, lazygit, btop"]
  palette -- "LC_KITTY_PALETTE" --> nvim["Neovim"]
  palette -- "SSH SendEnv +<br/>palette push" --> remote["Neovim on servers"]
```

kitty includes the Mocha fallback first and the DMS files after it, so DMS wins
whenever it has generated them ([kitty README](.config/kitty/README.md)).
Neovim needs the palette itself because it draws in truecolor: locally it reads
`LC_KITTY_PALETTE` (exported by the workflow shell rc) or the kitty palette
files; over SSH it reads the forwarded variable or the file workflow pushed.
The details are in [Palette over SSH](#palette-over-ssh).

## Quick start

On a workstation that already has the applications and workflow's tools (see
[Bootstrap per platform](#bootstrap-per-platform)):

```bash
git clone https://github.com/anhtt20172948/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh -n     # dry run: print what would be linked or backed up
./install.sh
```

`dotfiles-diagnose` (or `dotfiles-diagnose --json`) then reports the host, the
managed tools' versions, the dotfiles commit, the palette Neovim resolves with
each ANSI slot's contrast, and which tools follow it; missing tools are
reported, not fatal.

### Bootstrap per platform

`install.sh` only links configuration. Applications come from the platform's
package manager, and CLI tools, shell rc files and palette transport come from
workflow.

**Arch Linux workstation** (primary)

1. Packages: `pacman -S git zsh tmux kitty hyprland matugen python dux-shell`
   (`dux-shell` provides `dms-shell`, the `dms` desktop shell). The font is the
   patched SFMono Nerd Font "Complete" family, installed by hand into
   `~/.local/share/fonts`; no package provides that family (see the
   [kitty README](.config/kitty/README.md)).
2. Workflow, `make converge-local`: pinned CLI tools in `~/.local/bin` (Neovim,
   yazi, lazygit, fzf, bat, delta, atuin, btop, ...), the bash/zsh rc files,
   the `LC_KITTY_PALETTE` export, SSH `SendEnv`, and a systemd user unit that
   pushes the palette to servers on every DMS theme change. Two pieces for
   configs tracked here are workflow's job too and not in workflow yet:
   installing Starship and running `starship init` (until then hosts keep
   workflow's powerlevel10k prompt), and exporting
   `FZF_DEFAULT_OPTS_FILE=~/.config/fzf/fzfrc` so shell fzf takes the palette
   colours (the tmux pickers already do).
3. Dotfiles: `./install.sh`.

**macOS workstation**

1. Homebrew, kitty, and the same hand-installed SFMono Nerd Font "Complete"
   family.
2. Workflow, `make converge-local`, as above; the palette watcher is a launchd
   agent on `current-theme.conf`.
3. Dotfiles: `./install.sh`, which also installs Homebrew `coreutils` for
   tmux-which-key.

**Linux servers** (x86_64 and aarch64)

1. `git`, `zsh` and `tmux` must already be there: workflow cannot install them
   without root. The SSH server must accept `LC_*` (for example
   `AcceptEnv LC_*`) to receive the palette.
2. Workflow, `make converge LIMIT=<host>`: tools, shell rc and TPM plugins, then
   it clones this repository to `~/dotfiles` and links it with its own linker.
   No `install.sh` step is needed there.

Workflow's inventory, prerequisites and commands are in its
[README](https://github.com/anhtt20172948/workflow#readme).

### DMS look inputs

The palette also depends on DMS settings that live only in
`~/.config/dms/settings.json`, which DMS rewrites and which is not tracked
here. These values produce the look this repository is tuned for; set them in
DMS's settings before judging contrast or comparing screenshots:

| Setting (`settings.json` key) | Value | Effect |
| --- | --- | --- |
| `currentThemeName` | `dynamic` | Colours come from the wallpaper. |
| `matugenScheme` | `scheme-tonal-spot` | Material You scheme that turns the wallpaper into the palette. |
| `matugenSpec` | `2025` | Material colour specification version used by matugen. |
| `radiusStrength` | `38` | Corner rounding of the shell (0-100, Material's baseline is 50), so a little squarer than stock. |
| `fontFamily`, `monoFontFamily` | `SF Pro Display` | Shell UI fonts (terminal and editor use SFMono Nerd Font from kitty). |
| `fontWeight` | `700` | Shell UI font weight. |
| `interfaceStyle`, `density` | `expressive`, `comfortable` | Shell layout style. |
| `popupTransparency`, `foregroundLayerTransparency` | `1`, `1` | Surface alpha of shell popups and layers: fully opaque. |
| `blurEnabled`, `blurBorderEnabled`, `blurBorderOpacity` | `true`, `true`, `0.35` | Background blur and its border. |

Compare a host with these values:

```bash
jq '{currentThemeName, matugenScheme, matugenSpec, radiusStrength, fontFamily,
  monoFontFamily, fontWeight, interfaceStyle, density, popupTransparency,
  foregroundLayerTransparency, blurEnabled, blurBorderEnabled,
  blurBorderOpacity}' ~/.config/dms/settings.json
```

### What `install.sh` does

The linker needs Bash, coreutils (including `readlink -f`) and Python 3.11+
for the agent settings merge. Keep `~/.local/bin` on `PATH` to use the helpers.

- Missing destinations are symlinked to this checkout. Existing real directories
  are traversed so machine-only files stay in place.
- Conflicting files or links are moved to `~/.dotfiles-backup/<timestamp>/`.
  Links already pointing here are left alone.
- Shared directories such as `~/.config`, `~/.local/bin` and agent state
  directories stay real; existing directory symlinks outside this checkout are
  preserved, so runtime data stays outside the checkout.
- Root documentation, tests and project-only settings are excluded from linking.
- An empty `~/.gitconfig` is created when none exists, so `git config --global`
  writes land there instead of in the linked `~/.config/git/config` (git reads
  both; identity and credentials stay in `~/.gitconfig`).
- bat's theme cache is rebuilt when it is missing or older than a tracked theme
  in `.config/bat/themes`, since bat loads custom themes only from its cache.
- A file deleted from the repository leaves its old link behind. From the
  checkout, `find ~ -maxdepth 4 -xtype l -lname "$PWD/*"` lists links into it
  that no longer resolve; remove them by hand.

Shell rc files (`.bashrc`, `.zshrc`, `.bash_profile`) are rendered by workflow,
and this repository carries no shell exports with one deliberate exception:
[.zshenv](.zshenv) exports the active `ai-acct` Claude token
(`CLAUDE_CODE_OAUTH_TOKEN`) and its fingerprint (`AI_ACCT_FINGERPRINT`) for
every zsh, including the non-interactive shells agent workers run in. It reads
the token from `~/.config/claude-accounts` and keeps the read out of xtrace; see
[Claude account switching](#claude-account-switching).

#### Agent settings

Global agent rules live in `.config/agents/AGENTS.md`; OpenCode links to them,
and `.config/agents/CLAUDE.md` is linked to `~/.claude/CLAUDE.md` to import them.
The installer preserves Claude credentials and leaves `~/.codex/AGENTS.md` alone.

The settings merge preserves unrelated fields in `~/.claude/settings.json` and
`~/.codex/config.toml`. Its values and footer items are defined in
[install-agent-statusline](.local/bin/install-agent-statusline). Claude's status
line uses [agent-statusline-claude](.local/bin/agent-statusline-claude) and needs
`jq`; Codex uses its native footer. Preview just the merge with:

```bash
~/.local/bin/install-agent-statusline --home "$HOME" --check
```

Firstmate's `config/crew-dispatch.json` is linked individually under
`~/.local/share/firstmate`, keeping its runtime directories real. Edits to that
linked file change this checkout.

#### Firstmate settings are per host

`captain.md` holds each host's own captain preferences, so it lives at
`~/.local/share/firstmate/data/captain.md` on every host and is intentionally
untracked (it is gitignored and `install.sh` never links or replaces it). Create
it from [docs/firstmate/captain.md.example](docs/firstmate/captain.md.example):

```bash
mkdir -p ~/.local/share/firstmate/data
cp docs/firstmate/captain.md.example ~/.local/share/firstmate/data/captain.md
```

A host where it is still a symlink into an old dotfiles checkout can turn it into
a real file (a no-op on a regular file or a missing path; a non-zero exit status
only means the path was not a symlink):

```bash
for f in data/captain.md; do p=~/.local/share/firstmate/$f; [ -L "$p" ] && cp --remove-destination "$(readlink -f "$p")" "$p"; done
```

## What's inside

| Path | Configuration | Docs |
| --- | --- | --- |
| `.config/nvim` | Neovim: Lua, lazy.nvim with `lazy-lock.json`, palette-derived transparent UI. | [Neovim](#neovim) |
| `.tmux.conf`, `.config/tmux` | Modular tmux: status bar, popups, persistent AI sessions, which-key menu. | [tmux README](.config/tmux/README.md) |
| `.config/extrakto` | Extra extrakto filters (git hashes) for picking text out of a pane. | [tmux README](.config/tmux/README.md) |
| `.config/kitty` | Terminal: font, palette include order, slanted tab bar, `kitten ssh` settings. | [kitty README](.config/kitty/README.md) |
| `.config/starship.toml`, `.config/starship-plain.toml` | Shell prompt for bash and zsh (Nerd Font and ASCII variants). | [Design principles](#design-principles) |
| `.config/hypr` | Hyprland 0.57 Lua config; loads the DMS-generated colours, layout and rules last, then computes readable group bar titles (`groupbar.lua`). | [How the palette flows](#how-the-palette-flows) |
| `.config/yazi` | File manager: ANSI-only theme with Material folder icons, keymaps, and the duckdb, center-media and toggle-pane plugins. | |
| `.duckdbrc` | DuckDB CLI highlight colours (ANSI names), also used by yazi's duckdb previews. | |
| `.config/btop` | Resource monitor: built-in `TTY` theme, transparent background. | |
| `.config/lazygit`, `.config/lazydocker` | Git and Docker TUIs: ANSI-only themes and a reverse-video selected row; lazygit adds Nerd Font icons and delta diffs. | |
| `.config/git`, `.config/bat`, `.config/fzf` | Shared git settings (delta as pager with ANSI-only styles; identity stays in `~/.gitconfig`), bat's `ansi` theme, and fzf's palette colours for the shell. | [The ANSI slot contract](#the-ansi-slot-contract) |
| `.config/atuin` | Shell history settings. | |
| `.config/clangd` | C/C++ language server: a trimmed clang-tidy check set. | |
| `.config/agents`, `.config/opencode` | Global agent rules for Claude Code, Codex and OpenCode. | [Agent settings](#agent-settings) |
| `.config/claude-mods` | Claude Code mods: crew-watch (Crew Monitor) and pixel-pet. | [Claude Code mods](#claude-code-mods) |
| `.config/treehouse`, `.no-mistakes`, `.gnhf`, `.local/share/firstmate/config` | Agent workflow tools: worktree pool, pre-push gate, unattended loops, Firstmate crew dispatch. | [Agent workflow](docs/agent-workflow.md) |
| `.local/bin` | Helpers: `ai-acct`, `show`/`download`, `dotfiles-diagnose`, the agent status line, standalone installers. | [Claude account switching](#claude-account-switching), [Remote helpers](#remote-helper-scripts) |
| `.zshenv` | The active Claude account token for every zsh. | [What `install.sh` does](#what-installsh-does) |

## Guides

### Neovim

[init.lua](.config/nvim/init.lua) loads `core`, `configs.lazy` and
`current-theme`. Plugin declarations live in `.config/nvim/lua/plugins`, with
setup and helpers in `lua/core`, `lua/configs`, `lua/customize` and `lua/lib`.
The leader key is Space.

Floats use rounded borders and transparent surfaces. The fold/sign gutter uses
native Tree-sitter folds when a parser and fold query are available, otherwise
manual folds; files start unfolded and big files skip automatic folding.
Lualine stays under each split, with extra details at wider widths. Snacks owns
pickers, input and notifications; Noice owns command messages, Blink completion,
and native LSP owns hover/signature help. Session selection retains Telescope
on demand to preserve auto-session's delete/copy/alternate actions.
Pickers put the preview beside the list from 110 columns, below it from 25
lines, and start list-only in smaller terminals (`<a-p>` toggles it). The
dashboard follows its window: the artwork gives way to a one-line name when it
does not fit, and recent AI sessions show their age.

Set `NVIM_ASCII=1` before launching Neovim for ASCII diagnostic/git symbols,
file icons and dashboard actions, and mini.icons' ASCII folder style. This is a
manual client-font choice and is independent of SSH. File icons use the resolved
palette's text color; named folder icons keep their mini.icons identities.

| Binding | Action |
|---------|--------|
| `<leader>gw` | Pick a Git or treehouse worktree. |
| `<leader>ap` / `<leader>aP` | Push through no-mistakes / view pipelines. |
| `<leader>ag` / `<leader>aW` | Start a gnhf loop / an AI session in a worktree. |
| `<leader>aF` / `<leader>aR` | Open Firstmate / review a worker's changes. |
| `<leader>au` | Open the Claude account menu. |

#### Neovim colours

Neovim uses Kitty/DMS foreground and background for its neutral layers, keeping
Catppuccin's own syntax accents. Light backgrounds select Latte; dark backgrounds
select Mocha. All text colours (including comments and UI overlays) are adjusted
toward the foreground to meet WCAG 4.5:1 contrast against the editor background;
if the foreground is too dim, the adjustment uses black or white instead.
The DMS cursor colour (or URL colour when available) supplies borders, cursor and
active line accents. Neovim, sidebars, status lines and all popup surfaces use
transparent backgrounds, sharing Kitty's terminal opacity. Popup borders remain
visible, while cursor lines, visual selections and selected menu entries keep a
subtle surface fill. Contrast is measured against the unmodified Kitty/DMS
background behind the transparent window.

Comments alone are italic. Keywords, conditionals and loops are bold; functions,
types, variables, operators and rainbow delimiters are plain. Document heading
and emphasis styles retain their markup meaning. Constants and readonly LSP
variables use peach, parameters maroon, properties/members teal, builtin variables
red and builtin functions sapphire; ordinary variables use the foreground.
Uppercase names depend on the Python parser/LSP classifying them as constants or
readonly variables.

File icons retain nvim-web-devicons' per-filetype colours, adjusted to at least
4.5:1 contrast against the resolved terminal background, including the generic
file icon. Neo-tree, Snacks file pickers and Lualine use these colours;
mini.icons folder icons keep their existing appearance. `NVIM_ASCII=1` retains
the ASCII fallback. Theme reloads recompute from the original icon colours.
`tests/nvim_icons.lua` covers palette changes without plugins; with the installed
plugins, run `nvim --headless -u NONE -i NONE -l tests/helpers/check_devicon_colors.lua "$PWD"`
(and repeat with `NVIM_ASCII=1`) to check the providers and picker formatter.

### The ANSI slot contract

Every tool except Neovim uses ANSI colours: btop's built-in `TTY` theme, yazi's
built-in theme (no flavour), tmux, lazygit, lazydocker, duckdb, Starship, bat
(`.config/bat`), delta (the `[delta]` section of `.config/git/config`, also
used by lazygit) and fzf (`.config/fzf/fzfrc` for the shell, read through
`FZF_DEFAULT_OPTS_FILE`; the tmux pickers use the same spec from
`.config/tmux/scripts/fzf-colors.sh`). They follow one slot contract, because
DMS's dank16 palette gives two slots dark tones whatever the wallpaper:

- text uses ANSI 1-4, 6, 7, 9-15 or the default foreground;
- ANSI 5 (magenta) is never text: dank16 makes it a dark container tone, about
  2.5:1 on the background (use bright magenta, 13);
- ANSI 8 (bright black) is a surface and border tone, never text;
- ANSI 0 (black) equals the background, so it is no selection surface;
- the accent is ANSI 6 (cyan), the DMS primary.

Do not add hex colour literals to active tool configuration. Neovim highlights
must use the active Catppuccin palette, preserving the existing highlight roles
without retaining an independent fixed palette.
`tests/palette_consistency_test.sh` enforces this for tracked files. Its
commented exceptions cover kitty palettes, crew-watch named palettes, pixel-pet
sprite artwork, test fixtures/assertions, documentation, and generated
dependency locks. `tests/palette_contract.py` (run by the same test) also
rejects truecolor and 256-colour escapes, enforces the slot contract in tmux,
fzf, shell, Starship, yazi, lazygit, lazydocker and duckdb configuration, and
checks every text slot they use at 4.5:1 against Catppuccin Mocha and recorded
DMS dark and light palettes (`tests/fixtures/palettes/`). kitty's
`kitten themes` downloads other terminal themes on demand, so none are
vendored here.

### Palette over SSH

Kitty's active palette is the colour source on both platforms. DMS writes
`~/.config/kitty/dank-theme.conf` on Arch Linux with Hyprland; macOS uses
`current-theme.conf` (Catppuccin Mocha) without DMS. In SSH sessions, Neovim first
resolves `LC_KITTY_PALETTE_SRC` from the tmux session environment before the
process environment, then reads the matching pushed file
`~/.config/kitty/remote-palette-<src>.conf`. The source
must contain only lowercase letters, digits and hyphens, with 1 to 32 characters.
The file must contain exactly one palette line in the format below. Missing or
malformed matching files and invalid or absent sources fall back to the most
recently modified valid `remote-palette-*.conf` file, using the last machine
that pushed. If no pushed file is valid, Neovim tries `LC_KITTY_PALETTE` from
the tmux session environment, then the process environment, then the existing
file fallbacks. Removed tmux variables (`-NAME`) and malformed values are ignored.
The tmux environment is read once with a 100 ms timeout during SSH startup only;
failures fall back without interrupting startup. Local sessions ignore pushed files
and the tmux environment.

`LC_KITTY_PALETTE` contains 18 or 19 colon-separated colours, ordered background,
foreground, then color0 through color15, with an optional cursor colour as entry 19.
The cursor supplies the primary UI accent on servers; 18-entry palettes retain
the Catppuccin lavender fallback. Each entry must be six lowercase hex digits
without `#`, whitespace, or newlines. Any other entry count or malformed value
is ignored. Pushed files use the same format with an optional final newline.

The workflow repo manages the local shell export and SSH `SendEnv` configuration;
servers must accept `LC_KITTY_PALETTE` and `LC_KITTY_PALETTE_SRC` (for example
through `AcceptEnv LC_*`).
The local export runs only outside SSH sessions, preserving a palette received
from the client. This carries the palette over plain `ssh`, lazyssh's direct
`/usr/bin/ssh`, and `kitten ssh`. These dotfiles do not alias `ssh` or copy palettes.
The server needs this Neovim configuration too.

If neither a pushed file nor an environment palette is valid, Neovim reads the
first available legacy file:
`remote-palette.conf` during SSH sessions only, then `dank-theme.conf`, then
`current-theme.conf`. It resolves symlinks. Existing remote snapshots remain a
compatibility fallback for hosts that already have them; they are no longer
updated and may be stale, but a valid forwarded variable takes priority over
these legacy files.
Missing or incomplete file palettes fall back to plain Mocha.

The workflow
repo manages a local watcher that pushes source-specific palettes to reachable
servers. After a local theme change, quit and reopen remote Neovim in the same pane
to read the latest pushed palette. Offline servers miss that push; the next SSH
connection still forwards the current palette, and the next theme change pushes
again. tmux refreshes both palette variables on attach. Neovim reads that session
environment even in existing panes. Panes without a source id use the newest valid
pushed file, so reopening Neovim picks up theme changes without a new pane,
re-attach, or reconnect.

Kitty shell integration, remote kitty installation, and connection sharing remain
disabled in `ssh.conf`, preserving the server's account login shell and existing
connection policy when explicitly using `kitten ssh`.

### tmux

[.tmux.conf](.tmux.conf) sources the modules in `.config/tmux`. The prefix is
`Ctrl-b`. `prefix a` opens the AI tool/session picker; `prefix A` attaches the
most recent live agent for the project. `prefix F` opens the agent workflow
menu, `prefix C` the crew view, `prefix E` the Claude account menu, and
`prefix Q` the quota TUI.

See the [tmux README](.config/tmux/README.md) for bindings and dependencies,
including `fzf`, `fd`, `rg`, `bat`, `jq`, `sqlite3` and `sesh`. Install tmux and
TPM through `workflow` on servers; the local tmux entrypoint also has a TPM
bootstrap for other installations.

On macOS, `install.sh` installs Homebrew coreutils for tmux-which-key's GNU
`realpath --relative-to`; tmux includes Homebrew's GNU tools in the plugin
environment. The workflow-only `install_agent_workflow` setup installs the same prerequisite.

### Agent workflow

The configuration integrates treehouse, no-mistakes, gnhf and Firstmate with
the AI CLIs. Firstmate's launcher offers agent, Claude account, model and
effort choices; an existing Firstmate window is focused directly. See
[docs/agent-workflow.md](docs/agent-workflow.md) for daily use.
Use `workflow` for supported server provisioning; `install.sh` links the
configuration and does not install these tools.

### Claude account switching

`ai-acct` selects named Claude OAuth tokens while keeping one shared
`~/.claude` directory and `~/.claude.json`, so history survives account switches.
Codex retains its single account. Requirements: `claude`, `jq`, Python 3 and
`quota-axi`; tmux is optional.

```bash
ai-acct add personal      # enter the token at the hidden prompt
ai-acct use personal
ai-acct list
ai-acct status            # quota for Claude accounts and Codex
```

Names start with a lowercase letter or digit and contain only lowercase
letters, digits, `-` and `_` (up to 32 characters). Tokens are read from stdin,
never arguments, and stored in `~/.config/claude-accounts/NAME.token` with mode
`600`; new account directories use mode `700`. Never commit tokens or put them
in shell commands or logs.

`ai-acct edit NAME` replaces a token, `ai-acct rename OLD NEW` renames an account,
and `ai-acct remove NAME` deletes it. `ai-acct use NAME` writes the `active`
selector, marks Claude onboarding complete and updates tmux's environment for
future panes. It validates the local token without an authentication request.
Running processes retain their token, and the parent shell is unchanged.
Launch with `ai-acct exec claude`, a new zsh shell, or exit the main Claude
process and run `ai-acct resume`. It asks the tmux launcher for the Firstmate
home (`FIRSTMATE_DIR`, else `FM_HOME`, else `~/.local/share/firstmate`), applies
its live-primary guard and resumes the newest session of that home by id with
the active account. `ai-acct exec --account NAME CMD...` binds a named account
to the child instead of following the selector, which is how the tmux launcher
starts Firstmate; once that pane exists the launcher also selects the account so
crews follow it.

`ai-acct list --quota` adds compact quota bars. Quota readings are cached;
older readings show their age and missing readings show an explicit unknown or
unavailable state. The account menu remains usable while quota refreshes.
In Neovim, `:AiAccount` shows quota and `:AiAccount use NAME` selects an account;
the status line shows `AI:NAME`.

### Claude Code mods

`.config/claude-mods` holds Claude Code mods (function-hooks plugins) and is a
local plugin marketplace, `dotfiles-mods`, listed in
`.config/claude-mods/.claude-plugin/marketplace.json`:

| Mod | What it draws | Docs |
| --- | --- | --- |
| crew-watch | The Crew Monitor: a Firstmate crew's agents, context, quota, activity and events, as a docked pane (`/crew`) and a status-line summary. | [crew-watch README](.config/claude-mods/crew-watch/README.md) |
| pixel-pet | A pixel-art cat above the prompt that reacts to turns, tools and errors (`/pet`). | [pixel-pet README](.config/claude-mods/pixel-pet/README.md) |

`install.sh` leaves the
folder in the checkout and calls `install-agent-statusline`, which declares its
real checkout path in `~/.claude/settings.json` (`extraKnownMarketplaces`)
and enables every mod the marketplace lists
(`enabledPlugins`), so every Claude Code session loads them however it was
started (a shell, Neovim, tmux, the desktop app). A mod turned off in `/plugin`
stays off when `install.sh` runs again. A mod that draws above the prompt stacks
its rows on what lies beneath (`next(e)`) instead of replacing it, so the mods'
bands show together.

Claude Code reads the mods from the folder itself, not from a copy: after
editing one, run `/reload-plugins` in a session. For live reload on every save
while working on a mod, start a session with `claude --plugin-dir
<checkout>/.config/claude-mods/<mod>` (replace `<checkout>` with the actual checkout
path). A new mod is a folder with a
`.claude-plugin/plugin.json` and its own `README.md`, listed in
`marketplace.json`, then `./install.sh`.

Check a change to a mod with `claude plugin validate`, `tsc -p` and
`claude plugin test` on its folder (`tests/claude_mod_test.sh` checks the
marketplace and the settings `install.sh` writes, runs each mod's
`tests/*_test.py` with `python3`, and runs the first and last for every mod
when `claude` is installed). `tsc -p` needs the types the engine
lays in `.claude-plugin/types` the first time it loads the mod.

### Remote helper scripts

`show` and `download` search SSH hosts in parallel for a path. `show` mounts
the remote root with `sshfs` and opens the item using a local application;
`download` copies it with `rsync`.

```bash
show /home/user/project/report.pdf
download /home/user/project/data.csv
download /home/user/project/dir ./local-dir
REMOTE_HOSTS="rack jupyter" download /path/to/file
SSH_CONFIG=~/.ssh/config.work show /path/to/file
```

Hosts come from non-wildcard aliases on `Host` lines in `~/.ssh/config`.
`Include` directives are not followed. Both helpers prompt when multiple hosts
match. `download` defaults to the remote basename in the current directory.
`SSH_CONFIG` selects the configuration for discovery and all connections,
including SSHFS and rsync. Quote its value when the config path contains spaces.
`download` requires Python 3 to resolve destinations that do not exist yet.

Both helpers support macOS's stock Bash 3.2. `show` uses macOS `open` for files
and directories; on Linux it keeps the file-type-specific application choices.

`show` schedules an unmount after ten minutes. The mount path is
`/tmp/mnt_show_<host>` with `@` and `.` replaced by `_`; to unmount early, use
`fusermount3 -u` on Linux or `umount` on macOS with that path. Failures are logged to
`${TMPDIR:-/tmp}/show-unmount.log`.

### Standalone installers

The supported way to provision servers is
[workflow](https://github.com/anhtt20172948/workflow), which owns tool installs
and shell setup. These standalone helpers remain in `.local/bin`:

- `install_zsh`: builds ncurses and zsh into `~/.local` and updates
  `~/.bash_profile` to launch zsh in interactive shells.
- `install_neovim`: builds a selected Neovim version into `~/.local` and adds
  environment settings to `~/.zshrc` when needed.
- `install_agent_workflow`: installs its pinned agent tools and AXI skills;
  `--update` reinstalls those pins.

These helpers are separate from `install.sh` and are not the supported server
provisioning path.

## Testing and CI

```bash
tests/run.sh lint   # ShellCheck (LINT_FILES), actionlint, taplo (TOML), yamllint
tests/run.sh test   # tests/*.lua in headless Neovim, tests/*_test.sh, test_material_folder_icons.py
tests/run.sh        # both
tests/smoke/nvim_plugins.sh   # real plugins from lazy-lock.json; needs network
```

Tests use stubs instead of downloaded plugins and need no network or display;
a case that needs a missing tool (Python 3.11+, `luac`) is skipped with a clear
message. Each case gets 300 s (`TEST_CASE_TIMEOUT` overrides it) and a timeout
is reported as one. `TEST_LOG_DIR` keeps each case's log. The same entry point is the
no-mistakes gate (`.no-mistakes.yaml`). Lint SKIPs a linter that is not
installed; `LINT_STRICT=1` (set in CI) fails instead. TOML formatting follows
`.taplo.toml` (`taplo fmt`), YAML rules `.yamllint.yaml`.

`tests/smoke/nvim_plugins.sh` installs the plugins pinned in `lazy-lock.json`
into a scratch `HOME`, boots the full config headless and fails on any error
message, then reports the median lazy.nvim startup time over five boots against
`SMOKE_BUDGET_MS`. A last boot opens `tests/smoke/fixtures/` (one file per
treesitter language the config installs, plus a markdown code fence, a bash
heredoc and an LSP-hover-style float), forces a full treesitter parse and fails
on any parse error, missing highlighter or missing injection; headless Neovim
never redraws, so the plain boots never run those queries.
`tests/smoke/nvim_plugins.sh update` does the same after
`Lazy! update` and writes the new `lazy-lock.json` back.

[CI](.github/workflows/ci.yml) runs on pull requests and pushes to `main`, with
pinned action SHAs and checksummed tool downloads. Tool versions and checksums
live in [`.github/ci-tools.txt`](.github/ci-tools.txt) (installed by
`.github/install-ci-tools.sh`) and the hash-pinned `.github/requirements/`.

- **lint**: `tests/run.sh lint` with every linter required.
- **stylua**: StyLua over the Neovim and Hyprland Lua.
- **test**: the full suite on Ubuntu 24.04 with the pinned Neovim and Starship,
  in a scratch `HOME`.
- **arch**: lint and tests in an `archlinux` container with Arch's current
  tmux, Neovim and Starship, as an unprivileged user.
- **nvim-plugins**: the real-plugin smoke test and startup budget; it does not
  block merging yet (`continue-on-error`).
- **macos**: lint and tests on macOS 15 with stock `/bin/bash` 3.2 and BSD
  tools (plus Neovim and Starship), with GNU `timeout` kept off `PATH`.
- **secrets**: gitleaks over the full history.

[Renovate](.github/renovate.json5) proposes updates to the action SHAs, the
container digest, `ci-tools.txt` (version and checksum together) and the Python
linters, weekly and after a release is a week old. Neovim stays on its minor
release until the config moves on deliberately. The
[lazy-lock update](.github/workflows/lazy-lock.yml) workflow runs `Lazy! update`
weekly and opens a pull request when the updated plugins boot cleanly.

A separate, non-blocking [demo workflow](.github/workflows/demo.yml) renders
tmux, Neovim, yazi and lazygit under the Mocha fallback and the recorded DMS
dark and light palettes with VHS on every pull request that touches the
configuration, and uploads the GIFs and stills to compare
([docs/demo](docs/demo/README.md)).

## License

[MIT](LICENSE). Vendored components (the yazi plugins and the test fixtures)
retain their own license notices.
