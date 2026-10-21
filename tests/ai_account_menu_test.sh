#!/usr/bin/env bash
# Drive the real prefix E menu with mocked fzf choices and tokens on stdin.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" CHOICES="$TMP/choices" MENU_LOG="$TMP/menu"
unset TMUX
mkdir -p "$TMP/bin" "$HOME"
ln -s "$ROOT/.local/bin/ai-acct" "$TMP/bin/ai-acct"
# Each fzf call records its input and answers with the next queued choice;
# an empty queue is Esc.
cat > "$TMP/bin/fzf" <<'MOCK'
#!/usr/bin/env bash
{ printf '%s\n' "$*"; cat; printf -- '--\n'; } | tee -a "$MENU_LOG.all" >> "$MENU_LOG"
choice=$(head -n 1 "$CHOICES")
[[ -n $choice ]] || exit 130
tail -n +2 "$CHOICES" > "$CHOICES.next"
mv "$CHOICES.next" "$CHOICES"
printf '%s\n' "$choice"
MOCK
cat > "$TMP/bin/quota-axi" <<'MOCK'
#!/bin/sh
printf '{"providers":[{"provider":"claude","state":{"status":"fresh"},"windows":[]},{"provider":"codex","state":{"status":"fresh"},"windows":[]}]}\n'
MOCK
chmod +x "$TMP/bin/fzf" "$TMP/bin/quota-axi"
export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share" XDG_STATE_HOME="$HOME/.local/state"
export CODEX_HOME="$HOME/.codex"
export PATH="$TMP/bin:$PATH"
MENU="$ROOT/.config/tmux/scripts/ai-account.sh"
dir=$HOME/.config/claude-accounts
fail() { printf 'FAIL: %s\n' "$*" >&2; cat "$MENU_LOG" >&2 || true; exit 1; }
# GNU stat -c, else BSD stat -f (macOS has no -c).
mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
# menu CHOICE... <<< stdin
menu() { printf '%s\n' "$@" > "$CHOICES"; : > "$MENU_LOG"; bash "$MENU" 2>>"$TMP/err"; }

printf 'work\nsynthetic-work\n' | menu add
[[ $(cat "$dir/work.token") == synthetic-work ]] || fail 'add token'
[[ $(mode_of "$dir/work.token") == 600 ]] || fail 'add permissions'
sed '/^--$/q' "$MENU_LOG" > "$TMP/first-menu"
grep -Fqx $'add\t+ Add account' "$TMP/first-menu" || fail 'menu lacks add'
if grep -Fq 'Replace token' "$TMP/first-menu"; then fail 'offered edit with no accounts'; fi
grep -Fq $'use:work\tUse work  ◌ unknown' "$MENU_LOG" || fail 'menu did not return after add'

bash "$MENU" add <<< $'home\nsynthetic-home' 2>>"$TMP/err"
[[ -f $dir/home.token ]] || fail 'direct add action'

menu use:work < /dev/null
[[ $(cat "$dir/active") == work ]] || fail 'use from menu'
menu < /dev/null
grep -Fq $'use:work\tUse work (active)  ◌ unknown' "$MENU_LOG" || fail 'active marker'
grep -Fq $'use:home\tUse home           ◌ unknown' "$MENU_LOG" || fail 'inactive account entry'
# Accounts stay switchable when quota cannot be read.
XDG_CACHE_HOME=/dev/null/cache menu use:home < /dev/null
grep -Fqx $'use:work\tUse work (active)  ◌ unknown' "$MENU_LOG" || fail 'quota failure hid accounts'
[[ $(cat "$dir/active") == home ]] || fail 'use without quota'
menu use:work < /dev/null

# Exercise the real menu and account switch with a failed, absent or stuck helper.
mkdir -p "$TMP/helper-bin"
cp "$ROOT/.local/bin/ai-acct" "$TMP/helper-bin/ai-acct"
ln -sf "$TMP/helper-bin/ai-acct" "$TMP/bin/ai-acct"
for mode in failure missing hang; do
  case "$mode" in
    failure) printf 'raise SystemExit(1)\n' > "$TMP/helper-bin/ai-acct-quota" ;;
    missing) rm -f "$TMP/helper-bin/ai-acct-quota" ;;
    hang) printf 'import time\ntime.sleep(60)\n' > "$TMP/helper-bin/ai-acct-quota" ;;
  esac
  menu use:home < /dev/null
  grep -Fqx $'use:home\tUse home           ◌ unknown' "$MENU_LOG" || fail "$mode helper hid quota state"
  [[ $(cat "$dir/active") == home ]] || fail "$mode helper prevented account switch"
  menu use:work < /dev/null
  [[ $(cat "$dir/active") == work ]] || fail "$mode helper prevented switching back"
done
ln -sf "$ROOT/.local/bin/ai-acct" "$TMP/bin/ai-acct"

printf 'synthetic-new\n' | menu edit work
[[ $(cat "$dir/work.token") == synthetic-new ]] || fail 'edit token'

printf 'job\n' | menu rename work
[[ -f $dir/job.token && ! -e $dir/work.token ]] || fail 'rename'
[[ $(cat "$dir/active") == job ]] || fail 'rename lost active account'

printf 'n\n' | menu remove job
[[ -f $dir/job.token ]] || fail 'remove without confirmation'
printf 'y\n' | menu remove job
[[ ! -e $dir/job.token && ! -e $dir/active ]] || fail 'confirmed remove'

# Invalid input is reported by ai-acct and the menu keeps running.
printf 'Bad Name\nsynthetic-bad\n' | menu add
[[ -z $(find "$dir" -name 'Bad*') ]] || fail 'accepted invalid name'
grep -Fq 'Invalid account name' "$TMP/err" || fail 'invalid name not reported'

# Esc on the account picker changes nothing.
menu edit < /dev/null
[[ $(cat "$dir/home.token") == synthetic-home ]] || fail 'cancelled edit changed token'

if grep -Fq 'synthetic-' "$MENU_LOG.all" "$TMP/err"; then fail 'token reached fzf or the screen'; fi
printf 'ai-account menu: OK\n'
