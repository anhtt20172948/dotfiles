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
├── ai-popup.conf               → minimal config for persistent AI sessions
└── scripts/
    ├── ai-lib.sh               → shared helpers for the four ai-* scripts
    ├── ai-picker.sh            → fzf picker + previews for AI coding CLIs
    ├── ai-sessions.sh          → per-tool new, live and saved session picker
    ├── persistent-ai.sh        → persistent, per-project AI popup controller
    ├── ai-status.sh            → status-bar segment: live agent count
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

`C-b a` opens the tool picker, then that tool's session list. It is the browse
path, and the only route to `New session`. `C-b A` is the fast path: it attaches
the most recently used live agent for this project in one keystroke, and falls
back to `C-b a` when nothing is running.

Each session list begins with `New session`, followed by the live and saved
conversations for the current project. New sessions are independent; selecting a
live one attaches it, and selecting a saved one resumes it.

`Esc` always means *back*: it returns from a session list to the tool picker,
and closes the popup from the tool picker itself.

In a session list, `Ctrl-x` stops one running session while preserving its
history, and `Ctrl-d` confirms before deleting a saved history (to the trash, not
`rm`). Everything else is `Ctrl-j`/`Ctrl-k` to move and `Enter` to pick —
deliberately few keys, so there is nothing to memorise.

#### Leaving the popup

`Esc` or `C-b d` closes the popup and leaves the agent running.

`Esc` is a **root-table** binding (`bind-key -n`), which means tmux consumes it
and the agent never receives it. That is a deliberate tradeoff, chosen for
one-key close: you give up `Esc` as an interrupt and `Esc Esc` as Claude's
rewind.

What keeps that acceptable is that **`Ctrl-c` is not bound and passes straight
through**, and both Codex and Claude Code treat it as an interrupt — so a
running agent is still stoppable from inside the popup, just with a different
key. If you ever reconsider this binding, weigh it against that fact rather than
against "you cannot interrupt the agent at all", which is not the case.

`M-Escape` would be no use as a middle ground: most terminals send Alt as an ESC
prefix, so it arrives as `Esc Esc` — exactly the rewind chord.

This is also why `escape-time` is 25ms rather than 10 in `ai-popup.conf`. With
`Esc` bound, tmux must wait that long to distinguish a bare `Esc` from the start
of an Alt/CSI sequence; too low and an arrow key or Alt chord gets split, which
here causes a **spurious detach** rather than a merely garbled keystroke.

#### Reaping

Agents are persistent by design, so nothing removes them automatically, and they
do accumulate — a few rounds of experimenting leaves orphans behind.

`Ctrl-x` in a session list stops them one at a time. For a bulk sweep, set
`AI_POPUP_TTL_DAYS` to a positive number and sessions untouched for that many
days are pruned when the popup opens; it defaults to `0` (disabled) because
silently killing a long-running agent should be an explicit choice. Attached
sessions are never pruned. Failing both, `tmux -L ai-popup kill-server` clears
the lot.

### Popups

| Key | Action |
|-----|--------|
| `a` | AI picker — tool, then session list (the only path to `New session`) |
| `A` | Quick-attach the most recently used live agent for this project |
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
- `fzf` ≥ 0.56 (`--accept-nth`), `fd`, `rg`, `bat`, `jq`, `sqlite3`, `sesh` —
  for the finder/picker scripts
- `lazygit`, `lazydocker`, `btop` (or `htop`) — for the popups
- `codex`, `opencode`, `claude` — for the AI coding picker. All three are
  optional and independent; a missing one is shown as *not installed*.
- TPM (auto-bootstrapped on first launch)

### Two invariants in the AI scripts

**`ai-sessions.sh` stdout is a machine channel, not a screen.** The controller
runs it as `selection=$(ai-sessions.sh --tool X)` and parses the single
`action<TAB>tool<TAB>value` line it prints, so every prompt, message and screen
clear must go to stderr. Getting this wrong is not a cosmetic bug: the UI text
lands in `$selection`, its escape sequences parse as the action field, and the
next selection dies with *"invalid AI session selection"*. The give-away is
`Continue? [y/N]   Press any key to return...` sharing one line — that is
`read -p` (stderr, visible) with everything around it (stdout, swallowed).

**A live session is only deduplicated once its conversation id is known.** The
list is joined from two independent sources — tmux (live) and the tool's own store
(saved) — on `@ai_popup_session_id`. A session started as `New session` cannot
have that id at birth: only the agent knows it, and it is assigned after launch.
Until `link_new_session` in `ai-sessions.sh` pairs them up, one conversation shows
twice, and picking the saved copy would start a *second* agent on it. That
pairing declines whenever the match is not unambiguous, because a wrong guess
would point `Ctrl-d` at the wrong history.

**Codex creates `~/.codex/sessions/` lazily**, on the first real conversation, and
nests rollouts under `YYYY/MM/DD/` — hence `ai_recent_files "$HOME/.codex/sessions" 6`.
An empty Codex list on a machine you have not yet held a Codex conversation on is
therefore expected, not broken. Ignore the `thread history DB` line in
`codex doctor`: it stays missing even after real conversations, so it is not the
history store.

### Shell and userland

`scripts/` is shellcheck-clean at the strictest severity, and that is meant to
stay an invariant:

```sh
shellcheck --shell=bash -x --severity=style scripts/*.sh   # must exit 0
```

`-x` is required so the `source=` directives resolve; without it every `$AI_*`
reports SC2154. Each sourcing script also carries `# shellcheck
source-path=SCRIPTDIR`, which is what makes the command above work from any
directory — `source=./ai-lib.sh` alone resolves relative to the *current* one, so
it passes from inside `scripts/` and fails from the repo root.

The two sourced libraries carry a file-level `# shellcheck disable=SC2034`, since
from a single-file view every variable they define looks unused. One trap when
writing those comments: a line may not *begin* with `# shellcheck` even in prose,
or it is parsed as a malformed directive and takes down every file that sources
it.

**bash 3.2 is the floor, not bash 4+**, because that is what stock macOS ships
as `/bin/bash` and dotfiles get cloned before Homebrew exists. Verify with
`/bin/bash -n scripts/*.sh` on macOS, and keep these out of the scripts:

- `declare -A`, `mapfile`/`readarray`, `${x^}`, `${x,,}`
- expanding a possibly-empty array without `:-` under `set -u`

The `ai-*` scripts are also GNU-userland-free. `date -d`, `find -printf`, `stat -c`
and `timeout` are all GNU-only and every one of them used to fail silently on
macOS, so `ai-lib.sh` probes for the flavour once and provides `ai_fmt_epoch`,
`ai_iso_to_epoch`, `ai_recent_files`, `ai_run_limited` and `ai_trash` instead —
no `coreutils` needed. `ai_run_limited` falls back to a `perl` alarm rather than a
backgrounded `sleep`, because a watchdog holding the command-substitution pipe
open would make every call block for the full timeout. Note that
`ai_iso_to_epoch` parses through `jq`, not `date -j -f`: BSD `date` reads the
string in `$TZ` and would be off by the local UTC offset on the `Z`-suffixed
timestamps both Codex and Claude write. No `coreutils` dependency is needed or
wanted.
