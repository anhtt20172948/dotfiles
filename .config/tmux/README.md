# tmux config

Modular dotfile-based tmux configuration.

## Structure

```
~/.tmux.conf                    → source-file + TPM bootstrap
~/.config/tmux/
├── options.conf                → terminal, history, base settings
├── keymaps.conf                → navigation, resize, copy-mode, utils
├── plugins.conf                → TPM plugin list (7 plugins)
├── status.conf                 → status bar + Catppuccin palette usage
├── popup.conf                  → shared popup dimensions + keybinds
├── hooks.conf                  → pane-focus status refresh
├── navigation.conf             → vim-tmux-navigator mappings
├── monitor.conf                → Monitor Center config
└── scripts/
    ├── monitor-lib.sh          → shared helpers for the two monitor scripts
    ├── monitor.sh              → system monitor launcher (fzf menu)
    ├── monitor-preview.sh      → monitor live preview pane
    ├── file-finder.sh          → fd + fzf → nvim
    ├── grep-finder.sh          → rg + fzf → nvim (exact line)
    ├── sesh-picker.sh          → sesh + fzf session picker
    └── rename-window.sh        → popup window rename prompt
```

There is no `theme.conf` — the Catppuccin palette (`@thm_*`) is provided by the
plugin and consumed directly in `status.conf`.

## Load order

`.tmux.conf` sources the modules in this order, then runs TPM:

```
options → keymaps → plugins → status → popup → hooks → navigation → TPM
```

Two consequences worth remembering when editing:

- **`popup.conf` wins over `keymaps.conf`** for any key bound in both. Check
  `tmux list-keys -T prefix` after adding a binding.
- **`@thm_*` only exists after TPM runs.** Anything referencing the palette must
  expand lazily, so use `set -g`, never `set -gF`. Options that plugins also set
  (e.g. `status-style`, `copy-mode-vi y`) will be overwritten by the plugin.

## Keybinds

Prefix is the default `C-b`.

### Popups

| Key | Action |
|-----|--------|
| `g` | Lazygit |
| `G` | Lazydocker |
| `b` | Btop / Htop |
| `M` | Monitor Center |
| `f` | File finder (fd) |
| `/` | Grep search (rg) |
| `s` | Sesh session picker (replaces default `choose-tree`) |
| `T` | Scratchpad session toggle |

### Panes & windows

| Key | Action |
|-----|--------|
| `h` `j` `k` `l` | Select pane left/down/up/right |
| `H` `J` `K` `L` | Resize pane by 3 (repeatable) |
| `m` | Toggle zoom |
| `\|` / `-` | Split horizontal / vertical (keeps cwd) |
| `c` | New window (keeps cwd) |
| `<` / `>` | Swap pane up / down |
| `W` | Kill window (asks first) |
| `,` | Rename window (popup) |
| `R` | Rename session |

### Utils

| Key | Action |
|-----|--------|
| `r` | Reload config |
| `S` | Toggle synchronize-panes |
| `C-l` | Clear screen + scrollback |

### Copy mode (vi)

| Key | Action |
|-----|--------|
| `v` | Begin selection |
| `C-v` | Rectangle toggle |
| `y` | Copy (bound by tmux-yank → `wl-copy`) |

### Root table

`C-h` `C-j` `C-k` `C-l` and `C-Left` `C-Down` `C-Up` `C-Right` navigate panes and
pass through to Neovim, via vim-tmux-navigator.

## Requirements

- tmux ≥ 3.3 (`display-popup` needs 3.2, `allow-passthrough` needs 3.3,
  Catppuccin v2 needs 3.3+). Developed against 3.7b.
- `fzf`, `fd`, `rg`, `bat`, `sesh` — for the finder/picker scripts
- `lazygit`, `lazydocker`, `btop` (or `htop`) — for the popups
- TPM (auto-bootstrapped on first launch)
