#!/usr/bin/env bash
# The tmux config as a whole: it loads cleanly on this tmux, and the status bar,
# tab icons and key-hint menu behave as documented. Runs on a private server
# (own socket and TMUX_TMPDIR, temp HOME), so it never touches a live tmux.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
# The socket directory is separate and short: a unix socket path is limited to
# ~100 bytes and macOS's per-user $TMPDIR alone is most of that.
SOCKDIR=$(mktemp -d /tmp/fmtmux.XXXXXX)
SOCK="fm-cfg-$$"
export HOME="$TMP/home" TMUX_TMPDIR="$SOCKDIR"
unset TMUX
trap 'tmux -L "$SOCK" kill-server 2>/dev/null || true; rm -rf -- "$TMP" "$SOCKDIR"' EXIT

command -v tmux >/dev/null || {
  echo "skip: tmux not installed"
  exit 0
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

tm() { tmux -L "$SOCK" "$@"; }

# assert_contains <label> <needle> <haystack>
assert_contains() {
  [[ $3 == *"$2"* ]] || fail "$1: expected to contain '$2', got '$3'"
}

# assert_lacks <label> <needle> <haystack>
assert_lacks() {
  [[ $3 != *"$2"* ]] || fail "$1: expected not to contain '$2', got '$3'"
}

# version_ge <minimum>: is the running tmux at least that version?
version_ge() {
  local v
  v=$(tmux -V | tr -dc '0-9.')
  [[ $(printf '%s\n%s\n' "$v" "$1" | sort -V | head -n1) == "$1" ]]
}

mkdir -p "$HOME/.config" "$HOME/.tmux/plugins/tpm"
ln -s "$ROOT/.config/tmux" "$HOME/.config/tmux"
ln -s "$ROOT/.config/extrakto" "$HOME/.config/extrakto"
ln -s "$ROOT/.tmux.conf" "$HOME/.tmux.conf"
# TPM stand-in: the real one would clone plugins from the network.
printf '#!/bin/sh\nexit 0\n' >"$HOME/.tmux/plugins/tpm/tpm"
chmod +x "$HOME/.tmux/plugins/tpm/tpm"

tm -f /dev/null new-session -d -x 200 -y 40 -s main
errors=$(tm source-file "$HOME/.tmux.conf" 2>&1) || fail "config failed to load: $errors"
[[ -z $errors ]] || fail "config printed errors: $errors"

# --- status bar position and content -----------------------------------------
[[ $(tm show -gv status-position) == top ]] || fail "status bar is not at the top"
left=$(tm show -gv status-left)
right=$(tm show -gv status-right)
for gone in battery online_status '%H:%M' '%Y-%m-%d' session_created; do
  assert_lacks "status-right drops $gone" "$gone" "$right"
done
assert_lacks "status-left drops the duplicated command" "pane_current_command" "$left"
assert_contains "status-right keeps ai-status" "ai-status.sh" "$right"
assert_contains "status-right shows git and ssh context" "status-context.sh" "$right"

# --- dangerous-mode indicators ------------------------------------------------
rendered=$(tm display -p '#{T:status-left}')
assert_lacks "idle: no COPY flag" "COPY" "$rendered"
assert_lacks "idle: no SYNC flag" "SYNC" "$rendered"
tm setw -t main: synchronize-panes on
rendered=$(tm display -p '#{T:status-left}')
assert_contains "sync on: SYNC flag" "SYNC" "$rendered"
assert_contains "sync on: flag is loud" "bg=red,fg=black,bold" "$rendered"
tm setw -t main: synchronize-panes off
tm copy-mode -t main:
rendered=$(tm display -p '#{T:status-left}')
assert_contains "copy-mode: COPY flag" "COPY" "$rendered"
tm send-keys -t main: -X cancel
rendered=$(tm display -p '#{T:status-left}')
assert_lacks "left copy-mode: flag gone" "COPY" "$rendered"
# The session segment colours itself red while the prefix is pending.
assert_contains "prefix colouring branch" "bg=red#,fg=black#,bold" "$left"

# --- active pane ---------------------------------------------------------------
if version_ge 3.3; then
  [[ $(tm show -gwv pane-border-indicators) == both ]] || fail "pane-border-indicators not set on tmux >= 3.3"
fi

# --- window tab icons ----------------------------------------------------------
if version_ge 3.2; then
  fmt=$(tm show -gv window-status-format)
  assert_contains "tab format uses the icon" "@tab_icon" "$fmt"
  # Re-point every rule at a settable variable so each program name can be tried
  # without having to run that program in a pane.
  # (Pattern and replacement live in variables: bash 3.2 on stock macOS keeps
  # the backslashes of an escaped replacement literally.)
  from='#{pane_current_command}'
  to='#{@probe_cmd}'
  for opt in $(tm show -g | awk '/^@tab_icon_[0-9]+ /{print $1}'); do
    val=$(tm show -gv "$opt")
    tm set -g "$opt" "${val//"$from"/$to}"
  done
  icon_for() {
    tm set -g @probe_cmd "$1"
    tm display -p '#{E:@tab_icon}'
  }
  assert_icon() {
    local got
    got=$(icon_for "$1")
    [[ $got == " $2" ]] || fail "icon for '$1': expected ' $2', got '$got'"
  }
  assert_icon nvim $''
  assert_icon vim $''
  assert_icon zsh $''
  assert_icon ssh $'\U000f08c0'
  assert_icon claude $'\U000f06a9'
  assert_icon lazygit $''
  assert_icon git $''
  assert_icon python3.12 $''
  assert_icon sh $'' # not shadowed by the ssh rule
  [[ -z $(icon_for some-unknown-program) ]] || fail "unknown program should get no icon"
  [[ -z $(icon_for vimium) ]] || fail "icon rules must match the whole command name"
fi

# --- plugins -------------------------------------------------------------------
plugins=$(grep -h "set -g @plugin" "$ROOT/.config/tmux/plugins.conf")
for want in tmux-plugins/tpm laktak/extrakto alexwforsythe/tmux-which-key; do
  assert_contains "plugin list has $want" "$want" "$plugins"
done
for gone in tmux-battery tmux-online-status; do
  assert_lacks "plugin list drops $gone" "$gone" "$plugins"
done

# --- key-hint menu config ------------------------------------------------------
# tmux-which-key pastes each command into a single-quoted tmux string without
# escaping, so one stray ' in a command breaks the generated init.tmux.
wk="$ROOT/.config/tmux/plugins/tmux-which-key/config.yaml"
if grep -nE '^\s+command:.*'"'" "$wk"; then
  fail "which-key commands must not contain single quotes"
fi
# Every direct popup binding the menu advertises as "(prefix X)" must exist.
bound=$(tm list-keys -T prefix)
for key in a A F N C g G b M f / s T Q E S m ','; do
  [[ $bound == *" $key "* ]] || fail "prefix $key is documented in the menu but not bound"
done
echo "tmux_config_test: OK"
