#!/usr/bin/env bash
# Drive the real prefix E menu with mocked fzf choices and tokens on stdin.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
export HOME="$TMP/home" CHOICES="$TMP/choices" MENU_LOG="$TMP/menu"
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
chmod +x "$TMP/bin/fzf"
export PATH="$TMP/bin:$PATH"
MENU="$ROOT/.config/tmux/scripts/ai-account.sh"
dir=$HOME/.config/claude-accounts
fail() { printf 'FAIL: %s\n' "$*" >&2; cat "$MENU_LOG" >&2 || true; exit 1; }
# menu CHOICE... <<< stdin
menu() { printf '%s\n' "$@" > "$CHOICES"; : > "$MENU_LOG"; bash "$MENU" 2>>"$TMP/err"; }

printf 'work\nsynthetic-work\n' | menu add
[[ $(cat "$dir/work.token") == synthetic-work ]] || fail 'add token'
[[ $(stat -c %a "$dir/work.token") == 600 ]] || fail 'add permissions'
sed '/^--$/q' "$MENU_LOG" > "$TMP/first-menu"
grep -Fqx $'add\t+ Add account' "$TMP/first-menu" || fail 'menu lacks add'
if grep -Fq 'Replace token' "$TMP/first-menu"; then fail 'offered edit with no accounts'; fi
grep -Fqx $'use:work\tUse work' "$MENU_LOG" || fail 'menu did not return after add'

bash "$MENU" add <<< $'home\nsynthetic-home' 2>>"$TMP/err"
[[ -f $dir/home.token ]] || fail 'direct add action'

menu use:work < /dev/null
[[ $(cat "$dir/active") == work ]] || fail 'use from menu'
menu < /dev/null
grep -Fqx $'use:work\tUse work (active)' "$MENU_LOG" || fail 'active marker'
grep -Fqx $'use:home\tUse home' "$MENU_LOG" || fail 'inactive account entry'

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
