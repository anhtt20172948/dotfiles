# dotfiles

Personal configuration files for an Arch Linux + Hyprland desktop. Each
top-level entry mirrors its location in `$HOME`, and `install.sh` symlinks every
config into place - no root access and no GNU stow needed.

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
├── install.sh          → links the repo into $HOME
├── .gitignore
└── README.md
```

## Installation

Prerequisites: `bash` and coreutils (`ln`, `mkdir`, `mv`, `readlink`). No
`sudo` needed.

1. Clone the repository into your home directory:

   ```bash
   git clone https://github.com/yourusername/dotfiles.git ~/dotfiles
   ```

2. Preview, then create the symlinks:

   ```bash
   ~/dotfiles/install.sh --dry-run
   ~/dotfiles/install.sh
   ```

The installer folds directories the way stow does:

- Destination missing: link it as a whole (`~/.config/nvim` →
  `~/dotfiles/.config/nvim`).
- Destination is a real directory: keep it and link its children one by one,
  so files that only exist on this machine stay put.
- Destination already links to the repo (including relative links left by an
  earlier stow install): leave it.
- Anything else in the way (a file, or a symlink pointing elsewhere) is moved to
  `~/.dotfiles-backup/<timestamp>/` before linking; nothing is deleted.

`~/.config`, `~/.local`, `~/.local/{bin,share,state}` and the agent-tool state
dirs (`~/.no-mistakes`, `~/.gnhf`, `~/.config/treehouse`) are always kept as
real directories (or left as-is if they are symlinks to another disk), so apps
and the bootstrap scripts never write into the repo. Repo-only entries (`docs/`,
`tests/`, the repo-level `.claude/`, `.no-mistakes.yaml`, `README.md`,
`install.sh`, git files, editor backups) are never linked. Re-running is safe:
it prints what it linked or backed up and touches nothing that is already in
place.

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

## Agent workflow

Worktree pool, pre-push quality gate, overnight agent loops and a multi-agent
orchestrator on top of the AI CLIs (treehouse, no-mistakes, gnhf, firstmate).
Install with `install_agent_workflow`; tmux `prefix F` / `prefix C`, Neovim
`<leader>ap` / `<leader>ag` / `<leader>aW` / `<leader>aF`. See
[docs/agent-workflow.md](docs/agent-workflow.md).

## Remote helper scripts

`.local/bin/show` and `.local/bin/download` search a list of SSH hosts in
parallel for a given path, then open it or copy it down. They live in
`.local/bin` so `install.sh` puts them on `$PATH`.

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

- `bash` + coreutils - to run `install.sh`.
- The individual tools you intend to use: `nvim`, `hypr`(land), `kitty`, `tmux`
  (+ TPM, auto-bootstrapped on first launch), `yazi`, `btop`, `atuin`,
  `lazygit`, `lazydocker`, `clangd`.
- See [.config/tmux/README.md](.config/tmux/README.md) for the extra CLI tools
  its popups and AI-session scripts depend on (`fzf`, `fd`, `rg`, `bat`, `jq`,
  `sqlite3`, `sesh`, …).
