#!/usr/bin/env bash
# The Starship prompt configs (.config/starship.toml and its ASCII twin
# starship-plain.toml): they parse without warnings, use only ANSI colour names
# that stay readable under DMS, stay in step with each other, and render every
# module in real interactive bash and zsh shells.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAIN=$ROOT/.config/starship.toml
PLAIN=$ROOT/.config/starship-plain.toml

command -v starship >/dev/null || {
  echo "skip: starship not installed"
  exit 0
}
python3 -c 'import tomllib' 2>/dev/null || {
  echo "skip: needs python3 >= 3.11 with tomllib"
  exit 0
}

TMP=$(mktemp -d)
SOCKDIR=$(mktemp -d /tmp/fmstar.XXXXXX)
SOCK="fm-star-$$"
trap 'tmux -L "$SOCK" kill-server 2>/dev/null || true; rm -rf -- "$TMP" "$SOCKDIR"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# assert_contains <label> <needle> <haystack>
assert_contains() {
  [[ $3 == *"$2"* ]] || fail "$1: expected to contain '$2', got '$3'"
}

# assert_lacks <label> <needle> <haystack>
assert_lacks() {
  [[ $3 != *"$2"* ]] || fail "$1: expected not to contain '$2', got '$3'"
}

# --- static contract -------------------------------------------------------------
python3 - "$MAIN" "$PLAIN" <<'PY' || exit 1
import re
import sys
import tomllib

main_path, plain_path = sys.argv[1:]
main = tomllib.load(open(main_path, 'rb'))
plain = tomllib.load(open(plain_path, 'rb'))
errors = []

# The two files are one prompt in two glyph sets.
if main['format'] != plain['format']:
    errors.append('starship-plain.toml format differs from starship.toml')
if set(main) != set(plain):
    errors.append(f'module tables differ: {sorted(set(main) ^ set(plain))}')
for module in ('hostname', 'directory', 'git_branch', 'git_status', 'python', 'cmd_duration'):
    if f'${module}' not in main['format']:
        errors.append(f'format is missing ${module}')

# ANSI names only. purple (ANSI 5) and bright-black (ANSI 8) are DMS container
# tones, unreadable as text; the only background is the cyan directory pill.
colours = {'black', 'red', 'green', 'blue', 'yellow', 'cyan', 'white'}
colours |= {f'bright-{c}' for c in colours - {'black'}} | {'bright-purple'}
attrs = {'bold', 'italic', 'underline', 'dimmed', 'inverted', 'blink', 'hidden', 'strikethrough', 'none'}


def strings(node, path=''):
    if isinstance(node, dict):
        for key, value in node.items():
            yield from strings(value, f'{path}.{key}' if path else key)
    elif isinstance(node, str):
        yield path, node


def styles(path, value):
    if path.split('.')[-1].endswith('style'):
        yield value
    yield from re.findall(r'\]\(([^)]*)\)', value)


for name, config in (('starship.toml', main), ('starship-plain.toml', plain)):
    for path, value in strings(config):
        if path == '$schema':
            continue
        for style in styles(path, value):
            for token in style.split():
                if token.startswith('$') or token in attrs:
                    continue
                kind, _, colour = token.rpartition(':')
                if colour not in colours or kind not in ('', 'fg', 'bg'):
                    errors.append(f'{name} {path}: "{token}" is not an allowed ANSI colour')
                elif kind == 'bg' and (colour != 'cyan' or not path.startswith('directory.')):
                    errors.append(f'{name} {path}: only the directory pill may set a background')
        if name == 'starship-plain.toml' and not value.isascii():
            errors.append(f'{name} {path}: plain config must be ASCII')

# The pill uses lualine's slanted caps: U+E0BA opens it, U+E0BC closes it.
pill = main['directory']['format']
if not (pill.find('') != -1 and pill.find('') < pill.find('')):
    errors.append('starship.toml directory pill lacks the slanted caps U+E0BA ... U+E0BC')

if errors:
    sys.exit('\n'.join(errors))
PY

# --- fixture: a repo one commit ahead of and one behind its upstream, with an
# untracked file, so every git segment has something to show -------------------
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
gitc() { git -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false "$@"; }
gitc init -q -b main "$TMP/up"
gitc -C "$TMP/up" commit -q --allow-empty -m one
gitc clone -q "$TMP/up" "$TMP/repo"
gitc -C "$TMP/up" commit -q --allow-empty -m two
gitc -C "$TMP/repo" fetch -q
gitc -C "$TMP/repo" commit -q --allow-empty -m three
mkdir -p "$TMP/repo/src/app" "$TMP/home"
touch "$TMP/repo/untracked"
DIR=$TMP/repo/src/app
host=$(uname -n)
host=${host%%.*}

# prompt <config> <shell>: the rendered prompt over SSH, in a venv, after a
# failed 5.3 s command. Starship's config warnings go to stderr, so any stderr
# output fails the test.
prompt() {
  local out err
  out=$(cd "$DIR" && env -i PATH="$PATH" HOME="$TMP/home" TERM=xterm-256color \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 STARSHIP_LOG=warn \
    STARSHIP_CACHE="$TMP/cache" STARSHIP_CONFIG="$1" STARSHIP_SHELL="$2" PWD="$DIR" \
    SSH_CONNECTION='10.0.0.1 1 10.0.0.2 22' VIRTUAL_ENV="$TMP/.venv" \
    starship prompt --status 1 --cmd-duration 5300 --terminal-width 120 2>"$TMP/err")
  err=$(cat "$TMP/err")
  [[ -z $err ]] || fail "$1 ($2) printed warnings: $err"
  printf '%s' "$out"
}

for shell in bash zsh; do
  for config in "$MAIN" "$PLAIN"; do
    label="${config##*/} ($shell)"
    out=$(prompt "$config" "$shell")
    for want in "$host" src/app main .venv 5s; do
      assert_contains "$label shows $want" "$want" "$out"
    done
    assert_contains "$label marks the failed command red" $'\e[1;31m' "$out"
    assert_lacks "$label shows no repo path above its root" "$TMP" "$out"
    case $shell in
      bash) assert_contains "$label wraps escapes for readline" '\[' "$out" ;;
      zsh) assert_contains "$label wraps escapes for zle" '%{' "$out" ;;
    esac
  done
  out=$(prompt "$MAIN" "$shell")
  assert_contains "starship.toml ($shell) opens the pill" $'\xee\x82\xba' "$out"
  assert_contains "starship.toml ($shell) closes the pill" $'\xee\x82\xbc' "$out"
  assert_contains "starship.toml ($shell) fills the pill with the accent" '46;30m' "$out"
  assert_contains "starship.toml ($shell) shows ahead" $'\xe2\x87\xa11' "$out"
  assert_contains "starship.toml ($shell) shows behind" $'\xe2\x87\xa31' "$out"
  out=$(prompt "$PLAIN" "$shell")
  assert_contains "starship-plain.toml ($shell) shows ahead/behind" '>1' "$out"
  assert_lacks "starship-plain.toml ($shell) draws no pill" $'\xee\x82' "$out"
done

# --- end to end: `starship init` in real interactive bash and zsh ---------------
command -v tmux >/dev/null || {
  echo "skip: tmux not installed, interactive shells not exercised"
  exit 0
}
export TMUX_TMPDIR=$SOCKDIR
unset TMUX
tmux -u -L "$SOCK" -f /dev/null new-session -d -x 120 -y 10 -s init
shells=(bash)
command -v zsh >/dev/null && shells+=(zsh) || echo "skip: zsh not installed"
for shell in "${shells[@]}"; do
  case $shell in
    bash) cmd='bash --noprofile --norc -i' ;;
    zsh) cmd='zsh -f -i' ;;
  esac
  tmux -u -L "$SOCK" new-window -t init -n "$shell" -c "$DIR" \
    "env -i PATH='$PATH' HOME='$TMP/home' TERM=xterm-256color GIT_CONFIG_GLOBAL=/dev/null STARSHIP_CACHE='$TMP/cache' STARSHIP_CONFIG='$MAIN' $cmd"
  tmux -L "$SOCK" send-keys -t "init:$shell" "eval \"\$(starship init $shell)\"" Enter
  screen=''
  for _ in $(seq 1 50); do
    screen=$(tmux -L "$SOCK" capture-pane -p -t "init:$shell")
    [[ $screen == *$'\xee\x82\xbc'*main* ]] && break
    sleep 0.1
  done
  assert_contains "$shell prompt after starship init" $'\xee\x82\xba repo/src/app \xee\x82\xbc' "$screen"
  assert_contains "$shell prompt shows the branch" main "$screen"
  assert_contains "$shell prompt ends in the prompt character" $'\xe2\x9d\xaf' "$screen"
  assert_lacks "$shell prompt leaks no escape markers" '\[' "$screen"
  assert_lacks "$shell prompt leaks no zsh markers" '%{' "$screen"
done

echo "starship_config_test: OK"
