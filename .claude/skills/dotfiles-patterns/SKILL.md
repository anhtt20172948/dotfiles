---
name: dotfiles-patterns
description: "Use when working in this dotfiles repo, especially before editing shared Neovim or tmux modules, choosing where new config or helper scripts belong, or writing commits for config changes"
metadata:
  version: "1.0.0"
  source: local-git-analysis
  analyzed_commits: "120"
---

# Dotfiles Patterns

## Commit Conventions

- Prefer conventional commits such as `feat:` and `fix:` for most changes.
- Bracketed tags also appear in the history, especially `[update]`, `[add]`, and `[reformat]`; one commit even uses the typoed `[udpate]`.
- Keep summaries short and subsystem-focused, usually naming the area being changed: `nvim`, `tmux`, `mason`, `aiterm`, or `config`.

## Code Architecture

- The repo is organized as a `stow`-managed dotfiles tree, with source files rooted under `.config/`, `.local/`, and a few top-level dotfiles like `.tmux.conf`.
- Neovim config lives under `.config/nvim/lua/` and is split into `core/`, `configs/`, `customize/`, `lib/`, and `plugins/`.
- Tmux config lives under `.config/tmux/` and is split between `.conf` fragments and shell helpers in `.config/tmux/scripts/`.
- AI terminal work clusters around `.config/nvim/lua/customize/aiterm*.lua`, `.config/nvim/lua/plugins/aiterm.lua`, and `.config/tmux/scripts/ai-*.sh` plus `persistent-ai.sh`.
- Shared updates often touch several files in one subsystem at once, especially a plugin file plus the customization module or helper scripts plus the tmux popup config.

## Workflows

- When changing AI terminal behavior, update the customization module, the plugin wiring, and the related history or session helpers together.
- When changing tmux AI behavior, update the script set as a unit: `ai-lib.sh`, `ai-picker.sh`, `ai-sessions.sh`, and `persistent-ai.sh`.
- When the user-facing tmux flow changes, also update `popup.conf`, `ai-popup.conf`, or `README.md` so the command flow matches the scripts.
- Mechanical refreshes and config cleanup are commonly committed as standalone update or reformat changes.

## Testing Patterns

- There is no repo-wide automated test suite in the tracked history or top-level tree.
- Validation is usually manual or tool-driven: shell syntax checks for scripts, `luac -p` or headless Neovim load checks for Lua, and focused runtime checks for tmux behavior.
- For Lua config changes, prefer a minimal parse or load check over broad test scaffolding.
