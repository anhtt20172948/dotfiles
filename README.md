# dotfiles

Personal shell, terminal, editor and desktop configuration for an Arch Linux +
Hyprland setup, with shared CLI settings for servers. `install.sh` links the
configuration into `$HOME` and merges agent status-line and context settings;
it requires no root access or GNU Stow.

## Quick start

```bash
git clone https://github.com/anhtt20172948/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh -n     # dry run
./install.sh
```

Server tool provisioning is managed by the separate
[workflow](https://github.com/anhtt20172948/workflow) repository.

## Installation

The linker needs Bash, coreutils (including `readlink -f`) and Python 3.11+
for the agent settings merge. Keep `~/.local/bin` on `PATH` to use the helpers.
Install the applications you need separately.

- Missing destinations are symlinked to this checkout. Existing real directories
  are traversed so machine-only files stay in place.
- Conflicting files or links are moved to `~/.dotfiles-backup/<timestamp>/`.
  Links already pointing here are left alone.
- Shared directories such as `~/.config`, `~/.local/bin` and agent state
  directories stay real; existing directory symlinks outside this checkout are
  preserved, so runtime data stays outside the checkout.
- Root documentation, tests and project-only settings are excluded from linking.

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

### Firstmate settings are per host

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

## Configurations

| Directory | Configuration |
|-----------|---------------|
| `.config/nvim` | Neovim: Lua, lazy.nvim and `lazy-lock.json`; see [Neovim](#neovim). |
| `.config/tmux` | Modular tmux config and persistent AI popups; see [tmux](#tmux). |
| `.config/kitty` | Terminal font and themes; see [font configuration](.config/kitty/README.md). |
| `.config/hypr` | Hyprland, lock screen, wallpaper and DankMaterialShell integration. |
| `.config/yazi` | File manager settings and vendored color themes. |
| `.config/btop` | Resource monitor settings and themes. |
| `.config/atuin` | Shell history settings. |
| `.config/lazygit`, `.config/lazydocker` | Git and Docker TUI settings. |
| `.config/clangd` | C/C++ language server settings. |

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

### Neovim

[init.lua](.config/nvim/init.lua) loads `core`, `configs.lazy` and
`current-theme`. Plugin declarations live in `.config/nvim/lua/plugins`, with
setup and helpers in `lua/core`, `lua/configs`, `lua/customize` and `lua/lib`.
The leader key is Space.

| Binding | Action |
|---------|--------|
| `<leader>gw` | Pick a Git or treehouse worktree. |
| `<leader>ap` / `<leader>aP` | Push through no-mistakes / view pipelines. |
| `<leader>ag` / `<leader>aW` | Start a gnhf loop / an AI session in a worktree. |
| `<leader>aF` / `<leader>aR` | Open Firstmate / review a worker's changes. |
| `<leader>au` | Open the Claude account menu. |

## Agent workflow

The configuration integrates treehouse, no-mistakes, gnhf and Firstmate with
the AI CLIs. Firstmate's launcher offers agent, Claude account, model and
effort choices; an existing Firstmate window is focused directly. See
[docs/agent-workflow.md](docs/agent-workflow.md) for daily use.
Use `workflow` for supported server provisioning; `install.sh` links the
configuration and does not install these tools.

## Claude account switching

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
process and run `ai-acct resume` to continue it from
`${FM_HOME:-$HOME/.local/share/firstmate}`.

`ai-acct list --quota` adds compact quota bars. Quota readings are cached;
older readings show their age and missing readings show an explicit unknown or
unavailable state. The account menu remains usable while quota refreshes.
In Neovim, `:AiAccount` shows quota and `:AiAccount use NAME` selects an account;
the status line shows `AI:NAME`.

## Claude Code mod

`.config/claude-mods/fleet-deck` is a small Claude Code mod (a function-hooks
plugin) that makes the CLI easier to read:

- a compact status entry with the model, context use, the Claude account in use
  and its 5h/7d quota;
- on a machine with a Firstmate home, one quiet row above the prompt (workers,
  PRs waiting, what needs you), a `/fleet` side pane listing every worker, and a
  toast for a finished worker, a ready PR, a landed merge or a failure.

Everything fleet-related reads only `bin/fm-fleet-snapshot.sh --json` of
`$FM_HOME` (default `~/.local/share/firstmate`). Where that script is missing, or
in a Firstmate worker session, those parts do nothing and the status entry still
works. Colours come from the terminal theme and `NO_COLOR` is honoured.

`install.sh` links the folder to `~/.config/claude-mods/fleet-deck` and `.zshenv`
adds that path to `CLAUDE_CODE_PLUGIN_DIRS`, so new shells start Claude Code with
the mod loaded. The existing `statusLine` stays as it is: it also records the
rate limits that `ai-acct` shows, so the mod adds its entry beside it. `/fleet`
toggles the pane and refuses with a message below 110 columns.

Options are rows of `/config` (type `fleet` to filter them):

| Row | Default | Effect |
| --- | --- | --- |
| Chime (`sound`) | off | short chime with a fleet toast (`afplay` on macOS, else `paplay`, `pw-play` or `ffplay`) |
| Fleet toasts (`toasts`) | on | fleet toasts |
| Status entry (`status`) | on | the compact status entry |

To turn the chime on, set Chime to `true` in `/config`. Check a change to the mod
with `claude plugin validate`, `tsc -p` and `claude plugin test` on the folder
(`tests/claude_mod_test.sh` runs the first and last when `claude` is installed).

## Remote helper scripts

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

`show` schedules an unmount after ten minutes. The mount path is
`/tmp/mnt_show_<host>` with `@` and `.` replaced by `_`; to unmount early, use
`fusermount3 -u` with that path. Failures are logged to
`${TMPDIR:-/tmp}/show-unmount.log`.

## Bootstrap scripts

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

## License

[MIT](LICENSE). Vendored components retain their own license notices.
