# dotfiles

Personal configuration files for an Arch Linux + Hyprland desktop, managed with
[GNU stow](https://www.gnu.org/software/stow/). Each top-level entry mirrors its
location in `$HOME`, so stowing the repo symlinks every config into place.

## Repository layout

```
~/dotfiles/
├── .config/            → XDG config (symlinked to ~/.config)
│   ├── atuin/          → shell history database + sync
│   ├── btop/           → resource monitor (config + themes)
│   ├── clangd/         → C/C++ language server settings
│   ├── hypr/           → Hyprland window manager
│   ├── kitty/          → kitty terminal
│   ├── lazydocker/     → Docker TUI
│   ├── lazygit/        → Git TUI
│   ├── nvim/           → Neovim (Lua, lazy.nvim)
│   ├── tmux/           → tmux (modular) + AI-session popups
│   └── yazi/           → terminal file manager
├── .local/bin/         → user scripts placed on $PATH
├── .tmux.conf          → tmux entrypoint (sources ~/.config/tmux/*)
├── .gitignore
└── README.md
```

## Installation

Prerequisite: `stow` (`sudo pacman -S stow`).

1. Clone the repository into your home directory:

   ```bash
   git clone https://github.com/yourusername/dotfiles.git ~/dotfiles
   ```

2. Enter the directory:

   ```bash
   cd ~/dotfiles
   ```

3. Create the symlinks:

   ```bash
   stow --adopt .
   ```

   `--adopt` makes stow take over any pre-existing real files at the target
   paths (moving their content into the repo) instead of erroring out. Run
   `git diff` afterwards to review what was adopted, and `git checkout .` to
   discard changes you did not intend to keep.

## Configurations

| Directory | Tool | Notes |
|-----------|------|-------|
| `.config/nvim` | Neovim | Lua config bootstrapped from `init.lua` → `core` → `configs.lazy`. Plugins managed by [lazy.nvim](https://github.com/folke/lazy.nvim) (~65 plugins) under `lua/plugins/`, with `lua/{core,configs,customize,lib}` for options, setup and helpers. Pinned by `lazy-lock.json`. |
| `.config/hypr` | Hyprland | Modular config: `hyprland.conf` sources `conf/`, `keybindings*.conf`, `monitors.conf`, `workspaces.conf`, `effects/`, plus `hyprlock` (lock screen), `hyprpaper.conf` (wallpaper) and `scripts/`. Integrates [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) via `dms/`. |
| `.config/kitty` | kitty terminal | `SFMono Nerd Font`, modular theme files. Includes a `symbol_map` setup that enlarges Nerd Font icons — see [.config/kitty/README.md](.config/kitty/README.md). |
| `.config/tmux` | tmux | Split across module files sourced by `~/.tmux.conf`, with fzf-driven popups and persistent per-project AI coding sessions — see [.config/tmux/README.md](.config/tmux/README.md). |
| `.config/yazi` | yazi | Terminal file manager: `yazi.toml`, `theme.toml`, `keymap` and `init.lua`. `flavors/` holds vendored upstream color themes (catppuccin, rose-pine, dracula, tokyo-night). |
| `.config/btop` | btop | Resource monitor `btop.conf` plus a `themes/` collection. |
| `.config/atuin` | atuin | Shell-history replacement (`config.toml`) for searchable, synced history. |
| `.config/lazygit` | lazygit | Terminal UI for Git (`config.yml`). |
| `.config/lazydocker` | lazydocker | Terminal UI for Docker (`config.yml`). |
| `.config/clangd` | clangd | C/C++ language-server options (`config.yaml`). |

## Remote helper scripts

`.local/bin/show` and `.local/bin/download` search a list of SSH hosts in
parallel for a given path, then open it or copy it down. They live in
`.local/bin` so `stow` puts them on `$PATH`.

```bash
show     /home/user/project/report.pdf          # sshfs-mount + xdg-open
download /home/user/project/data.csv            # rsync into ./data.csv
download /home/user/project/dir ./local-dir     # explicit destination
```

Both derive their host list directly from `~/.ssh/config` — every non-wildcard
name on a `Host` line. There is no separate list to keep in sync: adding a host
to your ssh config is enough.

Each host costs one parallel ssh probe (3s connect timeout) per lookup. To
narrow a single run:

```bash
REMOTE_HOSTS="rack jupyter" download /path/to/file
SSH_CONFIG=~/.ssh/config.work show /path/to/file
```

`Include` directives in the ssh config are not followed; use `REMOTE_HOSTS` or
`SSH_CONFIG` if your config is split across files.

If a path exists on several hosts, both scripts prompt for a choice. Piping
works too: `echo 1 | download /path`.

`show` mounts the remote root under `/tmp/mnt_show_<host>` and schedules an
unmount 10 minutes later. To unmount early:

```bash
fusermount3 -u /tmp/mnt_show_<host>
```

Unmount failures are appended to `${TMPDIR:-/tmp}/show-unmount.log`.

## Bootstrap scripts

These live in `.local/bin` and build or fetch tooling into `~/.local`, so a
fresh machine needs no root to get a working userland:

- `install_linux_x86_64.sh` — fetch pinned release binaries into `~/.local/bin`.
- `install_zsh.sh` — build ncurses + zsh from source into `~/.local`.
- `install_neovim.sh` — build Neovim from source (run with `bash`, or `chmod +x`
  it first).

## Requirements

- `stow` — to link the configs.
- The individual tools you intend to use: `nvim`, `hypr`(land), `kitty`, `tmux`
  (+ TPM, auto-bootstrapped on first launch), `yazi`, `btop`, `atuin`,
  `lazygit`, `lazydocker`, `clangd`.
- See [.config/tmux/README.md](.config/tmux/README.md) for the extra CLI tools
  its popups and AI-session scripts depend on (`fzf`, `fd`, `rg`, `bat`, `jq`,
  `sqlite3`, `sesh`, …).
