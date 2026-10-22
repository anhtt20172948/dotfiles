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

`.config/claude-mods/crew-watch` draws the Crew Monitor: a header
(`▣ CREW / monitor`, then how fresh the data is and the time), five zones in a
fixed order and a key footer. Each zone sits in its own rounded box, its title
in small capitals on the first row and a short meta against the right edge, with
a blank row between boxes, so the blocks are told apart at a glance.

All themes use `paneStyles()` in `hooks/theme.ts` for the same visual rules:
rounded frames in `border` for every zone, stat tile and help box; bold `text`
for titles (including card names and detail headings); regular `subtle` for
metadata; and regular `border` for heading rules, the footer separator and bar
tracks. Each palette defines those roles; `default` resolves them through the
engine's theme. Agent cards and their expanded details share one status border
rule: running uses `merged`, quiet uses dim `merged`, blocked uses `error`, and
done or inactive uses dim `border`. While a card runs (working or active), a
heavy `━` run moves around its border, and its open details': half its length
each second, left to right along the top edge and right to left along the
bottom one, in the running colour. Every other border stands still. The run
needs a timer, which runs only while the pane is open and in front, some
crewmate runs and Claude Code's Reduce motion setting (`/config`, or
`"prefersReducedMotion": true` in settings) is off; otherwise it is stopped
and the borders keep their colours without the run.

One rule colours every harness, provider and model name, through
`harnessStyle()` in `hooks/theme.ts`: a card's harness, model and effort, the
open details' dispatch line, model rows, account heads and workspace harness,
each Quota account's provider and its bars, the Overview's model list (details
mode) and the inline summary. Claude names use `claude` (amber) after `✻`,
Codex names use `codex` (the palette's blue) after `◆`, and any other harness
uses neutral `text` after `▪`. The icons are plain characters one cell wide in
common terminal fonts, so no Nerd Font is needed, and an icon is always
followed by its name, so a terminal without colour still reads the family.
Event authors and detail headings do not take a harness colour. No layout or
background colour changes with these rules.

1. **Overview**: four tiles, each a small box with a big figure over its label:
   `LIVE` crewmates, `RUNNING` (working or active), `DONE`, and `CACHE READ`,
   the fleet's cache share. Under them the fleet's tokens, requests and tool
   calls. Details mode adds a bar of what Tokens is made of (cache read, cache
   write, output, uncached input) across the box's full width, drawn with the
   thin `━` of the pane's other bars so it never runs into the rows above and
   below it, each part in its own colour with a one-cell gap between parts and
   at least one cell for any part above zero; its legend lists each part with a
   `━━` swatch in that colour, three cells apart, wrapping as whole items; and
   both sums written out.
2. **Agents**: one card per crewmate: the status glyph, its name in bold and
   the status word and age on the right; harness, model, effort and task;
   `Context usage` with `used / window · percent` on the right and a bar of it
   on its own line; its own requests, tools and tokens (`in` is all input,
   uncached plus cache read and write); and its latest status line. Everything
   else about it opens with its number, below the cards: a box whose sections
   (status, model, context and tokens, tools, recent calls, last action, source
   and limits, workspace) each open with a ruled heading after a blank row.
   Every line in it is wrapped by the mod to the box's inner width, long words
   split, so no text runs past the border.
3. **Quota & Limits**: one block per provider and account: the name, then a
   `5h` row and a `week` row. Each row has a bar of the vendor's percent in the
   provider's colour, and in a column shared by every row the percent,
   `◷ stale` once the reading is over 30 minutes old and the time to its reset
   (`53% · resets 1h 12m`). A window with no percent shows `—` and why
   (`no 5h reading`, `window reset`) and draws no bar; too narrow for a bar beside
   the figure, the bar takes the next row. The 5-hour percent is the vendor's
   own reading (the pane session's rate limits, ai-acct's stored `five_hour`
   window, a Codex rollout's 300-minute window), shown as reported and never
   estimated or recorded in the reading history. `i` adds each account's notes.
4. **Activity**: the whole crew's logged events per minute as a bar chart of
   block characters (`▁▂▃▄▅▆▇█`, two rows tall), one cell per minute over up to
   the last hour (fewer minutes when the zone is narrower than 60 cells; a bar
   and a gap each from 119), scaled to the busiest minute, which the zone's meta
   names (`LAST 60 MIN · peak 29/min`); `60m ago` and `now` under it. A quiet
   minute is a dim `▁`.
5. **Recent Events**: the newest three to five events, newest first, one short
   row each, with a filter; `Enter` on a row shows its full text. A row reads
   time, the tag drawn as a badge, the crewmate (when more than one is live),
   then two right-aligned columns under an `in` / `out` header: the input the
   call's result added (`~` when estimated from its size) and its share of the
   request's output, as the details' recent calls count them, `—` for a status
   line or a call nobody measured. The command comes last and takes the rest of
   the row. When the token columns would leave the command under 16 cells they
   are dropped, and the header row says so.

The context figure and its bar need the model's window: a Codex rollout
supplies it, else Codex's own catalog (`~/.codex/models_cache.json`), and for
Claude models a small table in `crew_usage.py` (`CLAUDE_WINDOWS`), because
Claude transcripts never record it and no local catalog lists Claude models. A model none of them
knows shows `window n/a for <model>`, and a crewmate with no request yet shows
`no request yet`.

`/crew` opens or closes the pane; `/crew refresh` reads the logs immediately.
The keys work while the pane has the keyboard (`ctrl+x tab`, or a click); the
key footer names them and says so while the pane is unfocused.

| Key | Action |
| --- | --- |
| `1`–`9` | open or close that crewmate's details (one at a time) |
| `d` | compact or details mode; details adds every figure and note |
| `i` | quota notes: each account's source and age, estimates, crew shares and caveats |
| `l` | more or fewer log entries |
| `f` | log filter: All, Tools, Status, Errors, and Agent while details are open |
| `h` | help: keys, status words and what each metric counts |
| `Tab`, `Shift+Tab`, `Enter` | move between the pane's controls, log rows included, and press one (the engine's keys); `Enter` on a log row shows or hides its full text |
| `↑` `↓` `PgUp` `PgDn` `Home` `End` | scroll the pane (the engine's keys) |
| `Esc` | back to the prompt (the engine's key) |

The engine decides which keys a pane gets, so some keys of the handoff design
differ. A pane hotkey must be one digit or lowercase letter, so help is `h`,
not `?`. `Esc` always returns the keyboard to the prompt and never reaches the
mod, so details close with their own number. The arrows scroll the pane and
cannot move between crewmates; `Tab` does that. The engine documents only
`Enter` for pressing the focused control, so nothing is bound to `Space`. No
letter used here is an engine key inside a focused pane, and `q` and `x` are
left alone (`ctrl+x x` closes the pane). `Enter` cannot be a pane hotkey: it
always presses whichever control has the focus. So each log row is a control
of its own, and `Tab` to a row, then `Enter`, opens its full text; the quota
notes take the letter `i`, and `d` still switches the whole pane between
compact and details.

What it shows, and what it does not:

- **Freshness.** `● LIVE · updated 4s ago · 13:48` while reads succeed; `◷ STALE` once
  two refresh intervals and one read's 20 s timeout pass without a new report
  (30 s at the default 5 s interval); `× SOURCE ERROR` with the reason and the
  age of the last good data when a read fails. A report's own warnings show as
  `!` lines.
- **Status.** Each crewmate has a glyph and a word, so no colour is needed:
  `● WORKING` and `● ACTIVE` (activity under 2 minutes), `◐ QUIET` (2 to 15
  minutes), `○ STALE` (over 15), `✓ DONE`, `× BLOCKED` and `◷ PAUSED` from the
  task's status line, `? UNKNOWN` with no activity and no status yet. Only
  working and active count as active. Each card ends with the crewmate's latest
  status line (else its last tool call); in the row layout it is the third row,
  left out only under 24 rows (a blocked one's stays). A running (working or
  active) card has a purple border with a heavy run moving around it, a quiet
  one a dim purple border and a blocked one a red border; a done card has a dim neutral border and a green
  `✓ DONE`, so it sits back from the running ones.
- **Overview.** `Tokens` is uncached input + cache read + cache write + output,
  summed over the live crew since each task started. Thinking (reasoning) is
  part of output, as both vendors bill it, so it is never added a second time;
  Codex's cached input is split out of its input first, so nothing is counted
  twice. `Cache` is cache read / (uncached input + cache read + cache write),
  the share of all input served from the prompt cache, never called a hit rate.
  The `CACHE READ` tile shows this share; it is not labelled a hit rate. The
  details-mode legend names each part (`━━ uncached in 24`), because a small
  count beside `828k` reads like `24k`: a crewmate with 24 uncached, 827,917 cache-read and
  57,268 cache-write tokens has a cache share of 827,917 / 885,209 = 93.5%,
  shown as 94%. Details mode writes both sums out with every term, says how
  much of output was thinking where the log reports it, and lists requests per
  model.
- **Accounts.** Every quota figure belongs to one provider and account and is
  never summed across accounts or providers: two Claude accounts and a Codex
  account are three rows. A Claude account is named by its ai-acct name, a Codex
  one by its plan (its id is a hash) unless two would then read the same.
  `i` (and details mode) adds, per account, the reading's age and source, the
  account's estimate, the crew's session and tools-direct shares and the notes
  on what the figures can and cannot say; an open crewmate's details name the
  account its usage went to.
- **Missing data** shows as `—` or a sentence saying why, never as a zero: a
  harness whose logs cannot be read, an unknown model window, an account with no
  reading, no crewmates, no activity in the chart's window.
- **Events.** A row is the time, a tag drawn as a badge (the tool's name such
  as `BASH` or `EDIT`, `STAT` for a status line, `× ERR` for an error; a file
  edit purple, another call cyan, a status line green, an error red), the
  crewmate when more than one is live, the token columns, then the command or
  path in bold and the rest dim: `12:45:51   BASH         ~0    373  wc -l <…/report.md`. A preview writes the home folder as
  `~` (and its dashed form in Claude's transcript folders) and cuts every path
  of three or more parts to its last part, so the user name never shows in a
  screenshot; URLs and short paths such as `/dev/null` stay whole. The full
  text (`Enter` on the row) and the crewmate details write the home folder as
  `~` too.
  The collector keeps the latest ten events per crewmate and cuts long commands
  itself; the full text says `(source truncated)` where it did. An error is a
  status line whose state is blocked, failed or needs-decision; no severity is
  guessed from free text.

The layout follows the pane's own size, not the terminal's. From 40 columns
each zone has its box; a narrower pane keeps only a heading rule per zone. The
four tiles sit in one row while each keeps 11 cells, else two to a row, else
one. From 110 columns the cards sit two to a row; below that they stack; below 70 columns, past four
crewmates (three in one column) or under 24 rows each crewmate is a two-line
row. Under 24 rows Activity and the log preview fold to one line each; from 36
rows the log shows five entries. A docked pane is about 90 columns wide until
it is widened. Inline above the prompt (below 110 terminal columns, or outside
fullscreen) the pane is a summary of at most eight rows, and never more than the
engine shows it: header, totals, up to three crewmates and one quota line per
provider. Short of rows (a 24-row terminal shows five) the providers share one
quota line before any crewmate gives way, so no provider's row scrolls out of
sight; on a narrow pane that shared line is cut at its edge.

To preview a change, run Claude Code in fullscreen with the mod loaded from the
checkout and the installed copy turned off for that session, then type
`/crew`; the session reloads the mod on every save:

```sh
CLAUDE_CODE_NO_FLICKER=1 claude \
  --plugin-dir "$PWD/.config/claude-mods/crew-watch" \
  --settings '{"enabledPlugins":{"crew-watch@dotfiles-mods":false}}'
```

The engine writes the mod's types to `.claude-plugin/types`, which git ignores.
Run it from a Firstmate home (or set `homes`) to see a crew. The tests draw the
pane at 60, 80 and 120 columns and check that no row runs past it.

It reads the Claude Code transcripts and Codex rollouts each task wrote since it
first started (worktree slots are reused; a relaunch keeps earlier usage),
follows secondmate homes, and shows a summary in the status line. The layout takes inspiration from
[claude-flightdeck](https://github.com/scasella/claude-flightdeck).

Pane background. The pane is not transparent, and a mod cannot make it so.
When docked, the engine fills the whole pane column (and its divider) with its
own background colour, behind whatever the mod draws, and the mod API has no
transparent or terminal-default colour: `Color` is a theme key or a raw colour,
`Pane` has no background prop, and values such as `transparent` or `default` are
ignored. A mod can only cover that fill with an explicit colour, never remove
it, so a transparent terminal does not show through the docked pane. crew-watch
therefore sets no `backgroundColor` anywhere (an event's badge is inverse video:
its tag colour swaps with the fill behind it, so no colour of its own is set), the palette backgrounds in
`hooks/theme.ts` exist only to check text contrast, and a test keeps it so; it
adds no background option, since an explicit colour would only paint a patchwork
over the engine's fill.

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
