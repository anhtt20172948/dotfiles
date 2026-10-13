# Agent workflow

How this dotfiles setup runs AI coding agents beyond a single chat session:
isolated worktrees, a pre-push quality gate, unattended loops and a
multi-agent orchestrator. The tools come from
[kunchenguid](https://github.com/kunchenguid). They drive the agent CLIs
already used by aiterm and the tmux AI popup (`claude`, `codex`, `opencode`).

```
plan / task ──► firstmate (tmux window "firstmate")
                    │ spawns one crewmate per task
                    ▼
        crewmate in a treehouse worktree ──► git push no-mistakes ──► PR
                    │ uses gh-axi / chrome-devtools-axi skills
gnhf --worktree "<goal>"   long unattended loop, one commit per iteration
```

## Components

| Tool | What it does | Installed as | Global config (linked) |
|------|--------------|--------------|------------------------|
| [treehouse](https://github.com/kunchenguid/treehouse) | Pool of reusable git worktrees, so dependencies and build caches survive between tasks | Go binary, `~/.local/bin` | `.config/treehouse/config.toml` |
| [no-mistakes](https://github.com/kunchenguid/no-mistakes) | A local git remote. Pushing to it runs review, test, docs, lint, push, PR and CI fixes in a throwaway worktree | Go binary, `~/.local/bin` | `.no-mistakes/config.yaml` |
| [gnhf](https://github.com/kunchenguid/gnhf) | Overnight loop: small committed step per iteration, rollback on failure, waits out rate limits | npm, `--prefix ~/.local` | `.gnhf/config.yml` |
| [firstmate](https://github.com/kunchenguid/firstmate) | One "first mate" agent that dispatches and supervises crewmates in tmux windows | git checkout, `~/.local/share/firstmate` | `.local/share/firstmate/config/crew-dispatch.json` |
| AXI skills | `gh-axi`, `chrome-devtools-axi`, `lavish` (from `lavish-axi`): agent-friendly CLIs exposed as skills | `npx skills add -g` | none |

Versions are pinned at the top of
[`.local/bin/install_agent_workflow`](../.local/bin/install_agent_workflow).
Everything runs on the host. The Docker location step of the tmux AI popup
does not apply, because these tools launch the agent CLI themselves.

## Install

Requirements: `git`, `tmux`, `curl`, `node` >= 20 with `npm`/`npx`, and the
GitHub CLI logged in:

```bash
sudo pacman -S github-cli
gh auth login
gh auth setup-git      # git pushes over HTTPS use gh's token (no-mistakes needs this)
```

Then, from the repo:

```bash
cd ~/dotfiles
./install.sh                         # links configs and the installer
install_agent_workflow               # or: ./.local/bin/install_agent_workflow
```

The installer is idempotent: re-running skips anything already at the pinned
version. `install_agent_workflow --update` reinstalls the pinned versions.

Two things it takes care of:

- **Folded state dirs.** `install.sh` keeps `~/.no-mistakes`, `~/.gnhf` and
  `~/.config/treehouse` as real directories so tool state (databases, gate
  repos, run logs) never lands in `~/dotfiles`. An older stow install may have
  linked one of them as a whole into the repo; the installer turns such a
  folded link back into a real directory. It only touches links that point
  into this repo, never one you set up yourself.
- **Shadowed gnhf.** gnhf goes to `~/.local/bin`. If another `gnhf` (for
  example an nvm global) comes first on `$PATH`, the installer warns. Remove
  the other copy with `npm rm -g gnhf` under that node.

AXI skills are installed as skills only. `<tool> setup hooks` is skipped on
purpose, so they add no SessionStart hooks on top of ECC's.

Check the result with `<leader>ad` in Neovim (section "Agent workflow") or
`no-mistakes doctor`.

## Daily use

| Task | tmux | Neovim | Shell |
|------|------|--------|-------|
| Menu of all actions | `prefix F` | | `ai-workflow.sh` |
| Push current branch through the gate | `prefix F` → Push | `<leader>ap` | `git push no-mistakes <branch>` |
| Watch gate pipelines | `prefix N` | `<leader>aP` | `no-mistakes` |
| Work in a fresh worktree | `prefix F` → New worktree shell | `<leader>aW` (opens an AI session there) | `treehouse get` |
| Start an overnight loop | `prefix F` → gnhf | `<leader>ag` | `ai-workflow.sh gnhf "<goal>"` |
| Talk to the first mate | `prefix F` → firstmate | `<leader>aF` | `ai-workflow.sh firstmate` |

The tmux menu and the Neovim keys share one implementation,
[`.config/tmux/scripts/ai-workflow.sh`](../.config/tmux/scripts/ai-workflow.sh).
Long-lived work (worktree shells, gnhf, firstmate) opens as a window on the
main tmux server, so gnhf and firstmate need tmux. Keybind details live in
[`.config/tmux/README.md`](../.config/tmux/README.md#agent-workflow).

Tunables (environment variables):

| Variable | Default | Effect |
|----------|---------|--------|
| `AI_GNHF_MAX_ITERATIONS` | `20` | `--max-iterations` passed to gnhf |
| `AI_FIRSTMATE_AGENT` | `claude` | Agent CLI the first mate runs on |
| `FIRSTMATE_DIR` | `~/.local/share/firstmate` | firstmate checkout |

A worktree from `<leader>aW` is leased. Return it with
`treehouse return <path>` when done; the path is shown in the notification.

## Gating a repository with no-mistakes

Once per repository:

```bash
no-mistakes init          # adds the "no-mistakes" remote, needs an "origin"
no-mistakes doctor
```

Optional per-repo settings go in `.no-mistakes.yaml` at the repo root. The
gate reads `commands`, `agent` and `review` **only from the default branch**
(`origin/main`), so commit that file to main before relying on it.

This repository is gated itself. Its [`.no-mistakes.yaml`](../.no-mistakes.yaml)
runs [`tests/run.sh`](../tests/run.sh):

```bash
tests/run.sh lint   # shellcheck on the scripts that are clean
tests/run.sh test   # every tests/*.lua in headless Neovim
tests/run.sh        # both
```

Review findings are not auto-fixed (`auto_fix.review: 0`). The run stops at a
gate and waits for you: approve, ask the pipeline to fix selected findings, or
skip. Answer from the TUI (`prefix N`) or with `no-mistakes axi respond`.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `shallow update not allowed` on `git push no-mistakes` | The clone is shallow: `git fetch --unshallow origin` |
| Push step fails with `could not read Username for 'https://github.com'` | The gate has no git credentials: `gh auth setup-git` |
| A config you had before is gone after `./install.sh` | It was in the way, so the installer moved it to `~/.dotfiles-backup/<timestamp>/`. Merge what you need into the repo copy |
| A run is waiting and nothing happens | It is parked at a gate. Open `prefix N` or run `no-mistakes axi status` |
| Local branch is behind the pipeline after a run | The pipeline committed fixes. Sync with `no-mistakes sync` before new commits |

## Notes

- firstmate runs from its own checkout with its own `AGENTS.md`. Its rules
  apply only inside its sessions; the global agent rules are described in the
  [README](../README.md#installation).
- Docker is not supported yet. The likely path is a `docker exec` wrapper set
  as `agent_path_override` (no-mistakes) and `agentPathOverride` (gnhf), with
  the worktree roots bind-mounted at the same paths inside the container.
- Skipped on purpose: `gsh` (replaces the shell, sends telemetry) and
  `compact-adviser` (sends session context to a third-party API).
