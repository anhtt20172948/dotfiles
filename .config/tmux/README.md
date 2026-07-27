# tmux config

Modular dotfile-based tmux configuration.

## Structure

```
~/.tmux.conf                    → source-file + TPM bootstrap
~/.config/tmux/
├── options.conf                → terminal, history, base settings
├── keymaps.conf                → navigation, resize, copy-mode, utils
├── plugins.conf                → TPM plugin list (6 plugins)
├── theme.conf                  → Catppuccin theme config
├── status.conf                 → status bar (minimal)
├── popup.conf                  → shared popup dimensions + keybinds
├── hooks.conf                  → dark/light, after-split-window, focus
├── navigation.conf             → vim-tmux-navigator mappings
├── monitor.conf                → Monitor Center config
└── scripts/
    ├── file-finder.sh          → fd + fzf → nvim
    ├── grep-finder.sh          → rg + fzf → nvim (exact line)
    ├── sesh-picker.sh          → sesh + fzf-tmux session picker
    ├── monitor.sh              → system monitor launcher
    └── monitor-preview.sh      → monitor live preview
```

## Popup keybinds

| Key | Action |
|-----|--------|
| `g` | Lazygit |
| `G` | Lazydocker |
| `b` | Btop / Htop |
| `M` | Monitor Center |
| `f` | File finder (fd) |
| `/` | Grep search (rg) |
| `K` | Sesh session picker |
| `T` | Scratchpad toggle |

## Requirements

- tmux ≥ 3.3 (3.6+ recommended for dark/light hooks)
- fzf, fd, rg, bat, sesh (for scripts)
- TPM (auto-bootstrapped)
