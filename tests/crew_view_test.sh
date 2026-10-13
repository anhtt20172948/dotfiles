#!/usr/bin/env bash
# Exercise the popup and workflow entry through mock executable boundaries.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
export HOME="$TMP/home" FIRSTMATE_DIR="$TMP/firstmate checkout"
export CREW_TEST_DIR="$TMP"
mkdir -p "$HOME/.local/bin" "$FIRSTMATE_DIR/bin"
export PATH="$HOME/.local/bin:$PATH"

cat >"$HOME/.local/bin/tmux" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CREW_TEST_DIR/tmux.log"
case "$1" in
  has-session) exit "${SESSION_RC:-0}" ;;
  list-windows)
    [[ ${LIST_RC:-0} == 0 ]] || exit 1
    printf '%s' "${WINDOWS:-}"
    ;;
  capture-pane) printf 'worker screen\n' ;;
  switch-client) exit "${SWITCH_RC:-0}" ;;
  *) exit 99 ;;
esac
EOF
cat >"$HOME/.local/bin/fzf" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$CREW_TEST_DIR/fzf.args"
cat >"$CREW_TEST_DIR/fzf.input"
[[ ${FZF_RC:-0} == 0 ]] || exit "$FZF_RC"
if [[ ${WORKFLOW_MENU:-0} == 1 && $* == *'Agent Workflow'* ]]; then
  printf 'crew\n'
else
  for arg in "$@"; do
    case "$arg" in
      --preview=*)
        preview=${arg#--preview=}
        preview_shell=$(command -v zsh || command -v bash)
        quoted_index="'3'"
        "$preview_shell" -c "${preview//\{1\}/$quoted_index}" >"$CREW_TEST_DIR/preview"
        ;;
    esac
  done
  printf '%s\n' "${SELECTION:-3}"
fi
EOF
cat >"$FIRSTMATE_DIR/bin/fm-fleet-view.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$FM_HOME" >"$CREW_TEST_DIR/fleet.home"
printf 'Fleet overview\nworker status: working\n'
exit "${FLEET_RC:-0}"
EOF
chmod +x "$HOME/.local/bin/"{tmux,fzf} "$FIRSTMATE_DIR/bin/fm-fleet-view.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
contains() { grep -Fq -- "$2" "$1" || fail "$1 missing: $2"; }
absent() { [[ ! -e "$1" ]] || fail "unexpected file: $1"; }
reset_case() { rm -f "$TMP/"{tmux.log,fzf.args,fzf.input,fleet.home}; }
run_view() {
  local rc=0
  bash "$ROOT/.config/tmux/scripts/crew-view.sh" </dev/null >"$TMP/out" 2>"$TMP/err" || rc=$?
  [[ $rc == "$1" ]] || fail "exit $rc, expected $1: $(cat "$TMP/err")"
  [[ ! -s "$TMP/out" ]] || fail 'UI leaked to stdout'
}

# RED initially: the executable does not yet exist.
export WINDOWS=$'1\tfirstmate\n3\tfm-task-one\n5\tfm-task-two\n7\tnotes\n'
run_view 0
contains "$TMP/fzf.args" 'Fleet overview'
[[ $(cat "$TMP/fzf.input") == $'3\tfm-task-one\n5\tfm-task-two' ]] || fail 'worker filtering'
[[ $(cat "$TMP/fleet.home") == "$FIRSTMATE_DIR" ]] || fail 'FM_HOME override'
contains "$TMP/tmux.log" 'switch-client -t =firstmate:3'
contains "$TMP/tmux.log" 'capture-pane -p -t =firstmate:3 -S -80'
contains "$TMP/preview" 'worker screen'

reset_case
export FZF_RC=130
run_view 0
! grep -q 'switch-client' "$TMP/tmux.log" || fail 'cancel switched client'
unset FZF_RC

reset_case
export SELECTION='8; send-keys bad'
run_view 1
! grep -q 'switch-client' "$TMP/tmux.log" || fail 'invalid selection switched client'
unset SELECTION

reset_case
export SELECTION=9
run_view 1
! grep -q 'switch-client' "$TMP/tmux.log" || fail 'unknown worker switched client'
unset SELECTION

reset_case
export WINDOWS=$'1\tfirstmate\n7\tnotes\n'
run_view 0
contains "$TMP/err" 'Fleet overview'
contains "$TMP/err" 'No workers running'
absent "$TMP/fzf.args"

reset_case
export SESSION_RC=1
run_view 0
contains "$TMP/err" 'Fleet overview'
contains "$TMP/err" 'No firstmate session'
absent "$TMP/fzf.args"
unset SESSION_RC

reset_case
export LIST_RC=1
run_view 1
contains "$TMP/err" 'list workers'
unset LIST_RC

reset_case
export FLEET_RC=1
run_view 1
contains "$TMP/err" 'fleet overview'
absent "$TMP/tmux.log"
unset FLEET_RC

reset_case
mv "$FIRSTMATE_DIR/bin/fm-fleet-view.sh" "$TMP/fleet"
run_view 1
contains "$TMP/err" 'firstmate not found'
absent "$TMP/tmux.log"
mv "$TMP/fleet" "$FIRSTMATE_DIR/bin/fm-fleet-view.sh"

reset_case
export WINDOWS=$'3\tfm-task-one\n' SWITCH_RC=1
run_view 1
contains "$TMP/err" 'switch to worker'
unset SWITCH_RC

reset_case
bash "$ROOT/.config/tmux/scripts/ai-workflow.sh" crew </dev/null >"$TMP/out" 2>"$TMP/err"
contains "$TMP/tmux.log" 'switch-client -t =firstmate:3'
reset_case
WORKFLOW_MENU=1 bash "$ROOT/.config/tmux/scripts/ai-workflow.sh" </dev/null >"$TMP/out" 2>"$TMP/err"
contains "$TMP/tmux.log" 'switch-client -t =firstmate:3'
printf 'crew-view.sh: OK\n'
