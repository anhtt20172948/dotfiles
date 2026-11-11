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
if main.get('custom') != plain.get('custom'):
    errors.append('custom modules differ between the two files (they are glyph-free)')
for module in ('custom.root', 'hostname', 'directory', 'git_branch', 'git_status', 'git_metrics',
               'python', 'conda', 'jobs', 'fill', 'cmd_duration', 'time', 'status'):
    if f'${module}' not in main['format'] and f'${{{module}}}' not in main['format']:
        errors.append(f'format is missing ${module}')
# Starship's username module always shows the user over SSH, and its only gate
# (a negated detect_env_vars) would hide root too; the root warning is custom.root.
if '$username' in main['format']:
    errors.append('format has $username, which shows every user over SSH')

for name, config in (('starship.toml', main), ('starship-plain.toml', plain)):
    # `starship init bash` draws a right prompt only under ble.sh, so anything in
    # right_format would vanish in bash; the right side is $fill on the info line.
    if 'right_format' in config:
        errors.append(f'{name}: right_format is invisible in bash, use $fill')
    # `sudo` runs `sudo -n` on every prompt and has no gate.
    if '$sudo' in config['format']:
        errors.append(f'{name}: the sudo module shells out on every prompt')
    # Only the git CLI is cut off at command_timeout; gitoxide is not.
    if config.get('git_status', {}).get('use_git_executable') is not True:
        errors.append(f'{name}: git_status.use_git_executable must be true')
    if config.get('conda', {}).get('ignore_base') is not True:
        errors.append(f'{name}: conda.ignore_base must be true')

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

# Glyphs are \u escapes, so the file itself stays ASCII and survives any editor.
if not open(main_path, 'rb').read().isascii():
    errors.append('starship.toml: write glyphs as \\u escapes, not literal characters')

# The pill uses lualine's slanted caps: U+E0BA opens it, U+E0BC closes it.
pill = main['directory']['format']
if not (pill.find('') != -1 and pill.find('') < pill.find('')):
    errors.append('starship.toml directory pill lacks the slanted caps U+E0BA ... U+E0BC')

if errors:
    sys.exit('\n'.join(errors))
PY

# --- fixture: a repo one commit ahead of and one behind its upstream, with an
# untracked file and a tracked file two lines up and one down, so every git
# segment has something to show ------------------------------------------------
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
gitc() { git -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
gitc init -q -b main "$TMP/up"
gitc -C "$TMP/up" commit -q --allow-empty -m one
gitc clone -q "$TMP/up" "$TMP/repo"
gitc -C "$TMP/up" commit -q --allow-empty -m two
gitc -C "$TMP/repo" fetch -q
printf 'a\nb\nc\n' >"$TMP/repo/tracked"
gitc -C "$TMP/repo" add tracked
gitc -C "$TMP/repo" commit -q -m three
printf 'a\nc\nd\ne\n' >"$TMP/repo/tracked"
mkdir -p "$TMP/repo/src/app" "$TMP/home"
touch "$TMP/repo/untracked"
DIR=$TMP/repo/src/app
host=$(uname -n)
host=${host%%.*}

me=$(id -un)

# prompt <config> <shell> [width] [conda env]: the rendered prompt over SSH, in
# a venv and a conda env, with two background jobs, after a 5.3 s command that
# exited 1, plus any NAME=value pairs in PROMPT_ENV. Starship's config warnings
# go to stderr, so any stderr output fails the test.
PROMPT_ENV=()
prompt() {
  local out err
  out=$(cd "$DIR" && env -i PATH="$PATH" HOME="$TMP/home" TERM=xterm-256color ${PROMPT_ENV[@]+"${PROMPT_ENV[@]}"} \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 STARSHIP_LOG=warn \
    STARSHIP_CACHE="$TMP/cache" STARSHIP_CONFIG="$1" STARSHIP_SHELL="$2" PWD="$DIR" \
    SSH_CONNECTION='10.0.0.1 1 10.0.0.2 22' VIRTUAL_ENV="$TMP/.venv" \
    CONDA_DEFAULT_ENV="${4:-torch}" \
    starship prompt --status 1 --cmd-duration 5300 --jobs 2 --terminal-width "${3:-120}" 2>"$TMP/err")
  err=$(cat "$TMP/err")
  [[ -z $err ]] || fail "$1 ($2) printed warnings: $err"
  printf '%s' "$out"
}

# info_width <prompt>: the visible width of the info line (the prompt's second
# line, after add_newline), with colours and the shells' escape markers removed.
# Every glyph in it is one column wide.
info_width() {
  python3 -c '
import re, sys
line = sys.argv[1].split("\n")[1]
line = re.sub(r"%\{|%\}|\\\[|\\\]", "", line)
print(len(re.sub(r"\x1b\[[0-9;]*m", "", line)))' "$1"
}

for shell in bash zsh; do
  for config in "$MAIN" "$PLAIN"; do
    label="${config##*/} ($shell)"
    out=$(prompt "$config" "$shell")
    for want in "$host" src/app main .venv torch 5s; do
      assert_contains "$label shows $want" "$want" "$out"
    done
    assert_contains "$label shows the lines added" '+2' "$out"
    assert_contains "$label shows the lines deleted" '-1' "$out"
    [[ $out =~ [0-9]{2}:[0-9]{2} ]] || fail "$label shows no clock: $out"
    # The info line's own width depends on the host name (CI runners have long
    # ones), so measure it with $fill empty, then give $fill 40 columns to pad.
    natural=$(info_width "$(prompt "$config" "$shell" 1)")
    wide=$((natural + 40))
    width=$(info_width "$(prompt "$config" "$shell" "$wide")")
    [[ $width == "$wide" ]] ||
      fail "$label: \$fill should right-align the clock at column $wide, got width $width"
    assert_contains "$label marks the failed command red" $'\e[1;31m' "$out"
    assert_lacks "$label shows no repo path above its root" "$TMP" "$out"
    # The user name is noise unless it is root: hidden over SSH, and when the
    # shell's user is not the login user (su to another account).
    if [[ $me != root && $host != *"$me"* && $DIR != *"$me"* ]]; then
      assert_lacks "$label hides the user over SSH" "$me" "$out"
      PROMPT_ENV=(LOGNAME=someone-else)
      assert_lacks "$label hides a user other than the login user" "$me" "$(prompt "$config" "$shell")"
      PROMPT_ENV=()
    fi
    if [[ $(id -u) != 0 ]]; then
      assert_lacks "$label shows root only to root" root "$out"
    fi
    case $shell in
      bash) assert_contains "$label wraps escapes for readline" '\[' "$out" ;;
      zsh) assert_contains "$label wraps escapes for zle" '%{' "$out" ;;
    esac
  done
  for config in "$MAIN" "$PLAIN"; do
    label="${config##*/} ($shell)"
    out=$(prompt "$config" "$shell" 120 base)
    assert_lacks "$label hides the conda base env" base "$out"
    # Too narrow for both sides: $fill shrinks to nothing rather than failing,
    # and every module stays.
    natural=$(info_width "$(prompt "$config" "$shell" 1)")
    out=$(prompt "$config" "$shell" 30)
    [[ $(info_width "$out") == "$natural" ]] ||
      fail "$label at 30 columns should be its unpadded width $natural, got: $out"
    [[ $out =~ [0-9]{2}:[0-9]{2} ]] || fail "$label at 30 columns lost the clock: $out"
  done
  out=$(prompt "$MAIN" "$shell")
  assert_contains "starship.toml ($shell) shows the exit status" $'\xef\x91\xa7 1' "$out"
  assert_contains "starship.toml ($shell) shows the job count" $'\xe2\x9c\xa62' "$out"
  assert_contains "starship.toml ($shell) opens the pill" $'\xee\x82\xba' "$out"
  assert_contains "starship.toml ($shell) closes the pill" $'\xee\x82\xbc' "$out"
  assert_contains "starship.toml ($shell) fills the pill with the accent" '46;30m' "$out"
  assert_contains "starship.toml ($shell) shows ahead" $'\xe2\x87\xa11' "$out"
  assert_contains "starship.toml ($shell) shows behind" $'\xe2\x87\xa31' "$out"
  out=$(prompt "$PLAIN" "$shell")
  assert_contains "starship-plain.toml ($shell) shows the exit status" 'exit:1' "$out"
  assert_contains "starship-plain.toml ($shell) shows the job count" '&2' "$out"
  assert_contains "starship-plain.toml ($shell) shows ahead/behind" '>1' "$out"
  assert_lacks "starship-plain.toml ($shell) draws no pill" $'\xee\x82' "$out"
done

# --- root: an unprivileged user namespace maps us to uid 0 ----------------------
# Root is flagged locally, over SSH, and after `su`, which keeps the caller's
# USER and LOGNAME.
if command -v unshare >/dev/null && [[ $(unshare -r id -u 2>/dev/null) == 0 ]]; then
  for config in "$MAIN" "$PLAIN"; do
    for case in local ssh su; do
      case $case in
        local) extra_env=() ;;
        ssh) extra_env=('SSH_CONNECTION=10.0.0.1 1 10.0.0.2 22') ;;
        su) extra_env=("USER=$me" "LOGNAME=$me") ;;
      esac
      out=$(cd "$DIR" && env -i PATH="$PATH" HOME="$TMP/home" TERM=xterm-256color ${extra_env[@]+"${extra_env[@]}"} \
        GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 STARSHIP_CACHE="$TMP/cache" \
        STARSHIP_CONFIG="$config" STARSHIP_SHELL=zsh PWD="$DIR" \
        unshare -r starship prompt --terminal-width 120 2>"$TMP/err")
      [[ -z $(cat "$TMP/err") ]] || fail "${config##*/} as root printed warnings: $(cat "$TMP/err")"
      assert_contains "${config##*/} warns in red when root ($case)" $'%{\e[1;31m%}root' "$out"
    done
  done
else
  echo "skip: no unprivileged user namespaces, root warning not exercised"
fi

# --- end to end: `starship init` in real interactive bash and zsh ---------------
command -v tmux >/dev/null || {
  echo "skip: tmux not installed, interactive shells not exercised"
  exit 0
}
export TMUX_TMPDIR=$SOCKDIR
unset TMUX
# Window 0 idles in sleep: left to the default shell, automatic-rename would
# also call it "bash" or "zsh". Windows are targeted by id regardless, and dead
# panes stay so a shell that exits early can be reported.
tmux -u -L "$SOCK" -f /dev/null new-session -d -x 120 -y 10 -s init 'sleep 600'
tmux -L "$SOCK" set -g remain-on-exit on
shells=(bash)
command -v zsh >/dev/null && shells+=(zsh) || echo "skip: zsh not installed"
for shell in "${shells[@]}"; do
  case $shell in
    bash) cmd='bash --noprofile --norc -i' ;;
    zsh) cmd='zsh -f -i' ;;
  esac
  win=$(tmux -u -L "$SOCK" new-window -P -F '#{window_id}' -t init -c "$DIR" \
    "env -i PATH='$PATH' HOME='$TMP/home' TERM=xterm-256color GIT_CONFIG_GLOBAL=/dev/null STARSHIP_CACHE='$TMP/cache' STARSHIP_CONFIG='$MAIN' SSH_CONNECTION='10.0.0.1 1 10.0.0.2 22' $cmd")
  tmux -L "$SOCK" send-keys -t "$win" "eval \"\$(starship init $shell)\"" Enter
  screen=''
  for _ in $(seq 1 50); do
    screen=$(tmux -L "$SOCK" capture-pane -p -t "$win")
    [[ $screen == *$'\xee\x82\xbc'*main* ]] && break
    sleep 0.1
  done
  [[ $(tmux -L "$SOCK" display -p -t "$win" '#{pane_dead}') == 0 ]] ||
    fail "$shell exited (status $(tmux -L "$SOCK" display -p -t "$win" '#{pane_dead_status}')): $screen"
  assert_contains "$shell prompt after starship init" $'\xee\x82\xba repo/src/app \xee\x82\xbc' "$screen"
  assert_contains "$shell prompt shows the branch" main "$screen"
  assert_contains "$shell prompt over SSH shows the host" "$host" "$screen"
  if [[ $me != root && $host != *"$me"* && $DIR != *"$me"* ]]; then
    assert_lacks "$shell prompt over SSH hides the user" "$me" "$screen"
  fi
  assert_contains "$shell prompt ends in the prompt character" $'\xe2\x9d\xaf' "$screen"
  assert_lacks "$shell prompt leaks no escape markers" '\[' "$screen"
  assert_lacks "$shell prompt leaks no zsh markers" '%{' "$screen"
done

echo "starship_config_test: OK"
