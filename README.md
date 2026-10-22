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

## Claude Code mods

`.config/claude-mods` holds Claude Code mods (function-hooks plugins) and is a
local plugin marketplace, `dotfiles-mods`, listed in
`.config/claude-mods/.claude-plugin/marketplace.json`. `install.sh` leaves the
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
`.claude-plugin/plugin.json`, listed in `marketplace.json`, then `./install.sh`.

Check a change to a mod with `claude plugin validate`, `tsc -p` and
`claude plugin test` on its folder (`tests/claude_mod_test.sh` checks the
marketplace and the settings `install.sh` writes, runs each mod's
`tests/*_test.py` with `python3`, and runs the first and last for every mod
when `claude` is installed). `tsc -p` needs the types the engine
lays in `.claude-plugin/types` the first time it loads the mod.

### crew-watch

`.config/claude-mods/crew-watch` draws a fleet dashboard with rounded crew
cards, theme colours, token/request/tool totals, per-model counts and cache-hit
gauges. Each card shows activity and status, models and effort,
input/output/thinking tokens, context usage, cache reads/writes and top tools.
The context gauge needs the model's window: a Codex rollout supplies it, else
Codex's own catalog (`~/.codex/models_cache.json`), and for Claude models a
small table in `crew_usage.py` (`CLAUDE_WINDOWS`), because Claude transcripts
never record it and no local catalog lists Claude models. A model none of them
knows shows `window n/a for <model>`, and a crewmate with no request yet shows
`no request yet`.

`/crew` opens or closes the pane; `/crew refresh` reads the logs immediately.
Keys `1`–`9` expand a crewmate's details, branch, model/tool counts and recent
calls. Cards sit side by side when they fit, above activity lanes on a shared
minute axis; larger fleets get only the lanes. A crew log with local-time
timestamps follows them.
Inline above the prompt, the dashboard shrinks to at most eight rows; dock it
for full details.
It reads the Claude Code transcripts and Codex rollouts each task wrote since it
first started (worktree slots are reused; a relaunch keeps earlier usage),
follows secondmate homes, and shows a summary in the status line. The layout takes inspiration from
[claude-flightdeck](https://github.com/scasella/claude-flightdeck).

Tokens per tool call. The API bills requests, not calls, so each call is
charged with the output tokens of the request that emitted it (split evenly
when one request emits several calls) plus the input its result added to the
next request: the growth of the context window, `next context - this context -
this output`, split between the request's calls by result size. When no next
request exists yet, or the growth is unusable (a compaction shrank the
context), the input is estimated from the result size at four characters per
token and shown with `~`. The expanded crewmate lists `out N in M` per recent
call and `total · avg` per tool; Codex rollouts work the same from their
`token_count` events, and a log without usage fields says so instead of
guessing. This is a call's direct cost: every later request re-reads its result
from the prompt cache, and those re-reads count to the session, never to the
call.

Weekly quota. Vendors do not publish weekly caps in tokens, so none is
hard-coded, and the dashboard says for each figure what it is. Everything is
keyed by provider, account and limit scope (Claude `seven_day`; Codex the window
of at least 7200 minutes of its own `codex` limit), and a vendor percent is only
ever compared with the local usage of the same account.

- **Accounts.** A Claude session is tied to its `ai-acct` account without
  opening any token file: the pane's `AI_ACCT_FINGERPRINT` is matched against
  the fingerprints `agent-statusline-claude` stores in
  `~/.cache/ai-acct/claude-<name>.limits.json`, and only the account *name* is
  kept. Each session writes `session id -> name` into
  `~/.cache/crew-watch/accounts.json`, which is how another session's
  transcripts find their account. A Codex rollout is told apart by a short hash
  of its creator account id (the id is never stored). A session of no known
  account is `unknown`: it shows only its raw share of the local usage and never
  a percent. Another account's usage is never multiplied by this account's
  percent. Only sessions that ran this mod are tied to an account, so an
  account's local usage is a lower bound of its real usage and its share of
  local usage a partial one.
- **Measured vs estimated.** The vendor percent is an anchor `P(t0)` dated by
  the response that carried it: the pane session's last response
  (`$.session.usage()`, dated by the newest response in its own transcript), the
  reading history below (so a pane also shows another account's latest reading
  with its true age), `ai-acct`'s stored window (of unknown age, so always
  stale) and Codex rollout rate-limit events. The card shows `week 26% measured
  4m ago` and `source ...` separately from the estimate `session ~2% of week
  est`, which is the anchor plus the weighted tokens spent since it
  (`P(t0) + slope x tokens`) while the period has not reset. Tokens are weighted
  by relative price per type and model family (`PRICE_RATIO`/`FAMILY_PRICE` in
  `crew_usage.py`), and the slope is that period's own average up to the anchor:
  an explicitly uncalibrated prior, never a fitted weight. A new reading
  re-anchors and records how far the forecast missed it.
- **Settled intervals.** A crewmate's share sums settled intervals: each rise
  of the vendor percent is split by the crewmate's share of the account's usage
  inside that interval alone, so spending after the reading cannot make an
  earlier share shrink. Usage is kept per request, and the task start and the
  window start cut at each request's own time, so an old transcript that was
  resumed and edited recently counts only what the task did, and nothing from
  before the window.
- **Stale readings.** A reading older than 30 minutes, or of unknown age, is
  stale: it keeps its timestamp (`stale 3h ago`), is never called current or an
  upper bound, and shows only what was settled plus the raw local delta since
  (`session since 120k wtok`; `wtok` is price-weighted tokens), with no
  extrapolation, unless the confidence below is `calibrated` and the reading is
  under two hours old (the horizon that calibration measured). A reading whose
  window has reset is dropped as an anchor.
- **Confidence.** Each estimate carries `uncalibrated`, `low` or `calibrated`
  and the number of samples behind it. A sample is a recorded residual of a
  forecast 10 minutes to 2 hours old against a vendor reading that rose by at
  least a point; `calibrated` needs ten of them with the 90th percentile error
  within half the rise. It never means fitted weights. Estimates are shown
  rounded (`~2%`, `<1%`), because a one-point vendor step and an unfitted rate
  cannot support a decimal. The Codex aggregate error measured in the audit was
  about 4 points on 20 samples, so no per-crewmate precision is claimed.

The plan comes from Claude's local auth metadata and the Codex plan type. A
named `ai-acct` account signs in with `CLAUDE_CODE_OAUTH_TOKEN`, which leaves no
credentials file, so it carries only the account name and `token login`. Usage
from other machines or the web is not seen, so a figure is neither exact nor an
upper bound. The first refresh indexes the last week of local logs over several
refreshes (each stops after ten seconds) and shows "indexing local logs" until
it finishes. Claude Code's cached `/usage` is no longer a source: it cannot be
tied to an account.

#### Reading history

Every genuinely new observation is appended as one JSON line to
`${XDG_STATE_HOME:-~/.local/state}/crew-watch/readings.jsonl` (directory mode
700, file mode 600), outside the repository: schema version, provider, account
key, source, `observedAt` (the response's time, `null` when unknown, never faked
as now), `receivedAt`, an anonymous session key, kind and scope, the raw
percent, `resetsAt`, duration, the plan label and, once a reading met an older
one, the forecast's `residual`. A repeated callback of the same response is not
a new observation; the same percent in a later response is. A reading of
unknown time counts once per session. No token, OAuth value, fingerprint, prompt
or tool result is written, and an account of unknown identity is not recorded.
Sessions take a lock and append atomically, so several can run together. The
file is bounded: every observation is kept for two days, older ones only where
the percent moved, and anything older than five weekly periods is dropped (a
rewrite starts past 2 MiB and thins until about 1 MiB). To delete it:

```sh
rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/crew-watch"
```

The dashboard then starts from the live readings again, with no calibration
evidence. `~/.cache/crew-watch/accounts.json` is a cache of session account
names and can be deleted too: sessions of that account show as `unknown` until
they run the mod again.

Its three options in `/config` are `homes` (Firstmate homes, comma-separated;
empty defaults to the session's working directory), `intervalSeconds`
(refresh interval in seconds, default `5`) and `theme`. Parsed log offsets are
cached in `~/.cache/crew-watch/cache.json` so refreshes read only appended
content.

The `theme` option picks the dashboard's colours. `default` uses Claude Code's
own theme keys, so the pane follows your theme; every other value maps the
dashboard's roles (text, subtle, success, warning, blocked, merged, the
per-harness accents and borders) to one palette, defined once in
`hooks/theme.ts`. A theme changes colours only, never text, layout or
truncation. Palettes are truecolor; without `COLORTERM=truecolor` they use the
nearest 256-colour index, and `NO_COLOR` turns colour off. Light palettes are
for light terminals and dark palettes for dark ones: a light palette on a dark
terminal is not legible by design. Each role keeps at least 4.5:1 contrast
(text, subtle) or 3:1 (accents) on its palette's own background.

| `theme` | Palette | Terminal |
| --- | --- | --- |
| `default` | Claude Code's theme keys | any |
| `tokyo-night` | Tokyo Night | dark |
| `catppuccin-mocha` | Catppuccin Mocha | dark |
| `catppuccin-latte` | Catppuccin Latte | light |
| `gruvbox-dark` | Gruvbox Dark | dark |
| `gruvbox-light` | Gruvbox Light | light |
| `nord` | Nord | dark |
| `dracula` | Dracula | dark |
| `solarized-dark` | Solarized Dark | dark |
| `solarized-light` | Solarized Light | light |
| `one-dark` | One Dark | dark |

### pixel-pet

`.config/claude-mods/pixel-pet` draws a pixel-art cat, four rows tall, above the
prompt, with its name, what it is doing and the session's turn, tool and error
counts beside it. Two pixel rows share one text row (`▀`/`▄` with a foreground
and a background colour).

| When | The cat |
| --- | --- |
| idle | walks back and forth and blinks |
| a turn or a tool runs | paws tap, `đang chạy Bash...` |
| a turn ends | closed eyes and blush, `xong rồi! ♥`, for 4 seconds |
| a tool fails or a turn is interrupted | a tear, `Bash lỗi rồi…` |
| idle for 3 minutes | sleeps, `zZz` |

`/pet` hides or shows it. Its name is the Pet name row of `/config` (type `pet`),
`Mochi` by default. Prompts and tools never wait on its updates. It gives way
while a survey holds the band or the band has fewer than four rows, and under
`NO_COLOR` it is drawn as a silhouette with its eyes cut out.

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
